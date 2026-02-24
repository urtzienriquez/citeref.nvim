--- citeref.nvim – snacks.nvim picker backend
local util = require("citeref.util")
local parse = require("citeref.parse")

local M = {}

-- ─────────────────────────────────────────────────────────────
-- Helpers
-- ─────────────────────────────────────────────────────────────

--- Write lines into a snacks preview buffer, which is non-modifiable by default.
local function set_preview_lines(buf, lines, ft)
	local ma = vim.bo[buf].modifiable
	vim.bo[buf].modifiable = true
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].filetype = ft or "text"
	vim.bo[buf].modifiable = ma
end

--- Return the snacks preset name from picker.layout.
--- Accepts any snacks preset: "default", "vertical", "horizontal", "telescope",
--- "ivy", "ivy_split", "select", "sidebar", "vscode".
local function preset_name()
	return require("citeref.config").get().picker.layout or "vertical"
end

--- Rank entries: keys starting with query → keys containing query → title/author matches.
--- Within each group, preserve alphabetical-by-key input order.
---@param entries CiterefEntry[]
---@param query string
---@return CiterefEntry[]
local function rank_entries(entries, query)
	if not query or query == "" then
		return entries
	end
	local q = query:lower()
	local key_start = {}
	local key_contains = {}
	local other_matches = {}
	for _, e in ipairs(entries) do
		local k = e.key:lower()
		if k:find("^" .. q) then
			key_start[#key_start + 1] = e
		elseif k:find(q, 1, true) then
			key_contains[#key_contains + 1] = e
		elseif
			e.title:lower():find(q, 1, true)
			or e.author:lower():find(q, 1, true)
			or e.journaltitle:lower():find(q, 1, true)
		then
			other_matches[#other_matches + 1] = e
		end
	end
	local results = {}
	vim.list_extend(results, key_start)
	vim.list_extend(results, key_contains)
	vim.list_extend(results, other_matches)
	return results
end

--- Build a live finder function that re-ranks on every keystroke.
--- snacks calls this with (opts, ctx) on every query change when live = true,
--- using ctx.filter.search as the current query string.
---@param entries CiterefEntry[]
---@param current_key? string  mark current key in replace picker
---@return function
local function make_finder(entries, current_key)
	return function(_, ctx)
		local query = (ctx and ctx.filter and ctx.filter.search) or ""
		local ranked = rank_entries(entries, query)
		local items = {}
		for idx, e in ipairs(ranked) do
			local display = parse.entry_display(e)
			if current_key and e.key == current_key then
				display = display .. " (current)"
			end
			items[#items + 1] = {
				idx = idx,
				score = idx,
				text = display,
				entry = e,
				preview = parse.entry_preview(e),
			}
		end
		return items
	end
end

-- ─────────────────────────────────────────────────────────────
-- Citation picker
-- ─────────────────────────────────────────────────────────────

---@param format "markdown"|"latex"
---@param entries CiterefEntry[]
---@param ctx table
function M.pick_citation(format, entries, ctx)
	local Snacks = require("snacks")
	local title = format == "latex" and " Citations [LaTeX] " or " Citations [Markdown] "

	Snacks.picker({
		title = title,
		finder = make_finder(entries),
		live = true,
		format = function(item)
			return { { item.text, "Normal" } }
		end,
		preview = function(ctx_p)
			local item = ctx_p.item
			if not item then
				return
			end
			set_preview_lines(ctx_p.buf, vim.split(item.preview or "", "\n"))
		end,
		layout = { preset = preset_name() },
		confirm = function(picker)
			local selected = picker:selected({ fallback = true })
			picker:close()
			vim.schedule(function()
				local keys = {}
				for _, it in ipairs(selected) do
					if it and it.entry then
						keys[#keys + 1] = it.entry.key
					end
				end
				if #keys == 0 then
					return
				end
				table.sort(keys)
				local text = parse.format_citation(keys, format)
				util.insert_at_context(ctx, text)
				vim.notify("citeref: inserted " .. text, vim.log.levels.INFO)
			end)
		end,
	})
end

-- ─────────────────────────────────────────────────────────────
-- Replace citation under cursor
-- ─────────────────────────────────────────────────────────────

---@param entries CiterefEntry[]
---@param info table
function M.replace(entries, info)
	local Snacks = require("snacks")
	local buf = vim.api.nvim_get_current_buf()
	local row = vim.api.nvim_win_get_cursor(0)[1]

	Snacks.picker({
		title = " Replace @" .. info.key .. " ",
		finder = make_finder(entries, info.key),
		live = true,
		format = function(item)
			return { { item.text, "Normal" } }
		end,
		preview = function(ctx_p)
			local item = ctx_p.item
			if not item then
				return
			end
			set_preview_lines(ctx_p.buf, vim.split(item.preview or "", "\n"))
		end,
		layout = { preset = preset_name() },
		confirm = function(picker, item)
			picker:close()
			if not item or not item.entry then
				return
			end
			local e = item.entry
			if e.key == info.key then
				vim.defer_fn(function()
					vim.notify("citeref: same citation selected – no change", vim.log.levels.INFO)
				end, 100)
				return
			end
			local replacement = info.style == "latex" and e.key or ("@" .. e.key)
			local ok, err = pcall(
				vim.api.nvim_buf_set_text,
				buf,
				row - 1,
				info.start_col,
				row - 1,
				info.end_col + 1,
				{ replacement }
			)
			vim.defer_fn(function()
				if ok then
					vim.notify(string.format("citeref: %s → %s", info.key, e.key), vim.log.levels.INFO)
				else
					vim.notify("citeref: replacement failed – " .. tostring(err), vim.log.levels.ERROR)
				end
			end, 100)
		end,
	})
end

-- ─────────────────────────────────────────────────────────────
-- Crossref picker
-- ─────────────────────────────────────────────────────────────

---@param ref_type "fig"|"tab"
---@param chunks CiterefChunk[]
---@param ctx table
function M.pick_crossref(ref_type, chunks, ctx)
	local Snacks = require("snacks")
	local title = ref_type == "fig" and " Figure Crossref " or " Table Crossref "

	local items = {}
	for idx, c in ipairs(chunks) do
		local item = {
			idx = idx,
			score = idx,
			text = c.display,
			chunk = c,
		}
		if c.file and c.file ~= "" and vim.fn.filereadable(c.file) == 1 then
			item.file = c.file
			item.pos = { c.line, 0 }
		end
		items[#items + 1] = item
	end

	Snacks.picker({
		title = title,
		items = items,
		format = function(item)
			return { { item.text, "Normal" } }
		end,
		layout = { preset = preset_name() },
		confirm = function(picker, item)
			picker:close()
			vim.schedule(function()
				if not item or not item.chunk then
					return
				end
				local chunk = item.chunk
				if chunk.label == "" then
					vim.notify(
						"citeref: chunk has no label – add a label to use it in a cross-reference",
						vim.log.levels.WARN
					)
					return
				end
				local crossref = string.format("\\@ref(%s:%s)", ref_type, chunk.label)
				util.insert_at_context(ctx, crossref)
				vim.notify("citeref: inserted " .. crossref, vim.log.levels.INFO)
			end)
		end,
	})
end

return M
