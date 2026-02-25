--- citeref.nvim – mini.pick backend
local parse = require("citeref.parse")

local M = {}

-- ─────────────────────────────────────────────────────────────
-- LaTeX citation formats
-- ─────────────────────────────────────────────────────────────

local LATEX_FORMATS = require("citeref.latex_formats")

local function next_latex_format(current_cmd)
	for i, f in ipairs(LATEX_FORMATS) do
		if f.cmd == current_cmd then
			return LATEX_FORMATS[(i % #LATEX_FORMATS) + 1]
		end
	end
	return LATEX_FORMATS[1]
end

local function format_latex(keys, cmd)
	return "\\" .. cmd .. "{" .. table.concat(keys, ", ") .. "}"
end

-- ─────────────────────────────────────────────────────────────
-- Shared helpers
-- ─────────────────────────────────────────────────────────────

---@param entries CiterefEntry[]
---@param current_key? string
---@return string[], table<string, CiterefEntry>
local function citation_display_list(entries, current_key)
	local items = {}
	local lookup = {}
	for _, e in ipairs(entries) do
		local d = parse.entry_display(e)
		if current_key and e.key == current_key then
			d = d .. " (current)"
		end
		items[#items + 1] = d
		lookup[d] = e
	end
	return items, lookup
end

---@param chunks CiterefChunk[]
---@return string[], table<string, CiterefChunk>
local function chunk_display_list(chunks)
	local items = {}
	local lookup = {}
	for _, c in ipairs(chunks) do
		items[#items + 1] = c.display
		lookup[c.display] = c
	end
	return items, lookup
end

---@param entry CiterefEntry
---@return string[]
local function entry_preview_lines(entry)
	return vim.split(parse.entry_preview(entry), "\n")
end

-- ─────────────────────────────────────────────────────────────
-- Core insertion helper
-- ─────────────────────────────────────────────────────────────

--- mini.pick's choose callback fires after the picker window has already
--- closed. Neovim is always in normal mode at that point regardless of the
--- mode before the picker opened. Use vim.schedule to let picker teardown
--- finish, then insert directly and optionally re-enter insert mode.
---@param ctx table
---@param text string
local function insert_after_pick(ctx, text)
	vim.schedule(function()
		if ctx.win and vim.api.nvim_win_is_valid(ctx.win) then
			pcall(vim.api.nvim_set_current_win, ctx.win)
		end
		if ctx.buf and vim.api.nvim_buf_is_valid(ctx.buf) then
			pcall(vim.api.nvim_set_current_buf, ctx.buf)
		end

		local row = ctx.row
		-- After picker closes we are in normal mode, so insert after the char
		-- at ctx.col (same +1 offset insert_at_context uses for normal mode).
		local col = ctx.col + 1

		local ok = pcall(vim.api.nvim_buf_set_text, ctx.buf, row - 1, col, row - 1, col, { text })
		if not ok then
			pcall(vim.api.nvim_put, { text }, "c", false, true)
			vim.notify("citeref: inserted " .. text, vim.log.levels.INFO)
			return
		end

		local new_col = col + #text
		local line = vim.api.nvim_buf_get_lines(ctx.buf, row - 1, row, false)[1] or ""
		new_col = math.min(new_col, math.max(0, #line - 1))
		pcall(vim.api.nvim_win_set_cursor, ctx.win or 0, { row, new_col })

		if ctx.was_insert_mode then
			vim.cmd("startinsert")
		end

		vim.notify("citeref: inserted " .. text, vim.log.levels.INFO)
	end)
end

-- ─────────────────────────────────────────────────────────────
-- Citation picker
-- ─────────────────────────────────────────────────────────────

---@param format "markdown"|"latex"
---@param entries CiterefEntry[]
---@param ctx table
function M.pick_citation(format, entries, ctx)
	local MiniPick = require("mini.pick")

	local default_cmd = (format == "latex") and require("citeref.config").get().default_latex_format or "cite"
	local latex_fmt = LATEX_FORMATS[1]
	for _, f in ipairs(LATEX_FORMATS) do
		if f.cmd == default_cmd then
			latex_fmt = f
			break
		end
	end

	local function current_name()
		if format == "latex" then
			return string.format("Citations %s [<C-l> cycle]", latex_fmt.label)
		else
			return "Citations @"
		end
	end

	local function build_text(keys)
		table.sort(keys)
		if format == "latex" then
			return format_latex(keys, latex_fmt.cmd)
		else
			return parse.format_citation(keys)
		end
	end

	local items, lookup = citation_display_list(entries)

	local mappings = {}
	if format == "latex" then
		mappings["<C-l>"] = {
			char = "<C-l>",
			func = function()
				latex_fmt = next_latex_format(latex_fmt.cmd)
				MiniPick.set_picker_opts({ source = { name = current_name() } })
				vim.notify("citeref: " .. latex_fmt.label, vim.log.levels.INFO)
				return false -- keep picker open
			end,
		}
	end

	MiniPick.start({
		source = {
			name = current_name(),
			items = items,
			preview = function(buf_id, item)
				local e = lookup[item]
				if e then
					vim.bo[buf_id].modifiable = true
					vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, entry_preview_lines(e))
				end
			end,
			choose = function(item)
				-- MiniPick.get_picker_matches() must be called HERE, inside choose,
				-- before the picker closes and the state is torn down.
				-- .marked is a list of the items marked with <C-x>.
				-- If nothing is marked, fall back to the single focused item.
				local keys = {}
				local ok, matches = pcall(MiniPick.get_picker_matches)
				local marked = ok and matches and matches.marked or {}

				if #marked > 0 then
					for _, marked_item in ipairs(marked) do
						local e = lookup[marked_item]
						if e then
							keys[#keys + 1] = e.key
						end
					end
				else
					local e = item and lookup[item]
					if e then
						keys[#keys + 1] = e.key
					end
				end

				if #keys == 0 then
					return
				end
				insert_after_pick(ctx, build_text(keys))
			end,
		},
		mappings = mappings,
	})
end

-- ─────────────────────────────────────────────────────────────
-- Replace citation under cursor
-- ─────────────────────────────────────────────────────────────

---@param entries CiterefEntry[]
---@param info table
function M.replace(entries, info)
	local MiniPick = require("mini.pick")
	local buf = vim.api.nvim_get_current_buf()
	local row = vim.api.nvim_win_get_cursor(0)[1]

	local items, lookup = citation_display_list(entries, info.key)

	MiniPick.start({
		source = {
			name = "Replace @" .. info.key,
			items = items,
			preview = function(buf_id, item)
				local stripped = item:gsub(" %(current%)$", "")
				local e = lookup[item] or lookup[stripped]
				if e then
					vim.bo[buf_id].modifiable = true
					vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, entry_preview_lines(e))
				end
			end,
			choose = function(item)
				if not item then
					return
				end
				local stripped = item:gsub(" %(current%)$", "")
				local e = lookup[item] or lookup[stripped]
				if not e or e.key == info.key then
					vim.schedule(function()
						vim.notify("citeref: same citation selected – no change", vim.log.levels.INFO)
					end)
					return
				end
				local replacement = info.style == "latex" and e.key or ("@" .. e.key)
				vim.schedule(function()
					local ok, err = pcall(
						vim.api.nvim_buf_set_text,
						buf,
						row - 1,
						info.start_col,
						row - 1,
						info.end_col + 1,
						{ replacement }
					)
					if ok then
						vim.notify(string.format("citeref: %s → %s", info.key, e.key), vim.log.levels.INFO)
					else
						vim.notify("citeref: replacement failed – " .. tostring(err), vim.log.levels.ERROR)
					end
				end)
			end,
		},
	})
end

-- ─────────────────────────────────────────────────────────────
-- Crossref picker
-- ─────────────────────────────────────────────────────────────

---@param ref_type "fig"|"tab"
---@param chunks CiterefChunk[]
---@param ctx table
function M.pick_crossref(ref_type, chunks, ctx)
	local MiniPick = require("mini.pick")
	local title = ref_type == "fig" and "Figure Crossref" or "Table Crossref"

	local items, lookup = chunk_display_list(chunks)

	MiniPick.start({
		source = {
			name = title,
			items = items,
			preview = function(buf_id, item)
				local chunk = lookup[item]
				if not chunk then
					return
				end
				if chunk.file and chunk.file ~= "" and vim.fn.filereadable(chunk.file) == 1 then
					local ok, lines = pcall(vim.fn.readfile, chunk.file)
					if ok and lines then
						vim.bo[buf_id].modifiable = true
						vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)
						local ext = chunk.file:match("%.([^%.]+)$") or ""
						local ft_map = { rmd = "markdown", qmd = "markdown", Rmd = "markdown", Qmd = "markdown" }
						pcall(function()
							vim.bo[buf_id].filetype = ft_map[ext] or ext
						end)
						vim.schedule(function()
							for _, win in ipairs(vim.api.nvim_list_wins()) do
								if vim.api.nvim_win_get_buf(win) == buf_id then
									pcall(vim.api.nvim_win_set_cursor, win, { chunk.line, 0 })
									pcall(vim.api.nvim_win_call, win, function()
										vim.cmd("norm! zz")
									end)
									break
								end
							end
						end)
					end
				else
					vim.bo[buf_id].modifiable = true
					vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, { chunk.header or "(no preview)" })
				end
			end,
			choose = function(item)
				if not item then
					return
				end
				local chunk = lookup[item]
				if not chunk then
					return
				end
				if chunk.label == "" then
					vim.schedule(function()
						vim.notify(
							"citeref: chunk has no label – add a label to use it in a cross-reference",
							vim.log.levels.WARN
						)
					end)
					return
				end
				local crossref = parse.format_crossref(ref_type, chunk.label, ctx.bufnr)
				insert_after_pick(ctx, crossref)
			end,
		},
	})
end

return M
