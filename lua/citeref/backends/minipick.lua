--- citeref.nvim – mini.pick backend
local util = require("citeref.util")
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

--- mini.pick items are plain strings shown in the picker list.
--- We keep a parallel lookup table keyed by display string.

---@param entries CiterefEntry[]
---@param current_key? string   highlight the current citation in replace mode
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

--- Render a CiterefEntry into lines for the preview window.
---@param entry CiterefEntry
---@return string[]
local function entry_preview_lines(entry)
	return vim.split(parse.entry_preview(entry), "\n")
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

	local items, lookup = citation_display_list(entries)

	-- Build a mappings table; <C-l> cycles the LaTeX format (no-op for markdown).
	-- mini.pick mappings receive (picker_obj, query) and must return false to keep
	-- the picker open or nil/true to close it.
	local mappings = {}
	if format == "latex" then
		mappings["<C-l>"] = {
			char = "<C-l>",
			func = function()
				latex_fmt = next_latex_format(latex_fmt.cmd)
				-- Update the picker name shown in the window border/header.
				-- MiniPick exposes set_picker_opts() to mutate live options.
				MiniPick.set_picker_opts({ source = { name = current_name() } })
				vim.notify("citeref: " .. latex_fmt.label, vim.log.levels.INFO)
				-- Return false = keep picker open
				return false
			end,
		}
	end

	local chosen = MiniPick.start({
		source = {
			name = current_name(),
			items = items,
			preview = function(buf_id, item)
				local e = lookup[item]
				if e then
					vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, entry_preview_lines(e))
				end
			end,
			-- choose_marked is called when the user marks entries (with <C-x> by default)
			-- and confirms; choose is called for a single selection.
			choose = function(item)
				if not item then
					return
				end
				local e = lookup[item]
				if not e then
					return
				end

				local text
				if format == "latex" then
					text = format_latex({ e.key }, latex_fmt.cmd)
				else
					text = parse.format_citation({ e.key })
				end

				vim.cmd("stopinsert")
				vim.schedule(function()
					util.insert_at_context(ctx, text)
					vim.notify("citeref: inserted " .. text, vim.log.levels.INFO)
				end)
			end,

			choose_marked = function(marked_items)
				if not marked_items or #marked_items == 0 then
					return
				end
				local keys = {}
				for _, item in ipairs(marked_items) do
					local e = lookup[item]
					if e then
						keys[#keys + 1] = e.key
					end
				end
				if #keys == 0 then
					return
				end
				table.sort(keys)

				local text
				if format == "latex" then
					text = format_latex(keys, latex_fmt.cmd)
				else
					text = parse.format_citation(keys)
				end

				vim.cmd("stopinsert")
				vim.schedule(function()
					util.insert_at_context(ctx, text)
					vim.notify("citeref: inserted " .. text, vim.log.levels.INFO)
				end)
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
				local e = lookup[item]
				if e then
					vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, entry_preview_lines(e))
				end
			end,
			choose = function(item)
				if not item then
					return
				end
				local e = lookup[item]
				-- Strip " (current)" suffix that was added for display
				if not e then
					local stripped = item:gsub(" %(current%)$", "")
					e = lookup[stripped]
				end
				if not e or e.key == info.key then
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

	-- Build a per-item file previewer: open the source file at the chunk's line.
	-- mini.pick's built-in file previewer is invoked via MiniPick.default_preview(),
	-- but we need to jump to the right line ourselves.
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
					-- Read the file and display it in the preview buffer, then
					-- highlight the chunk header line.
					local ok, lines = pcall(function()
						return vim.fn.readfile(chunk.file)
					end)
					if ok and lines then
						vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)
						-- Attempt to set a reasonable filetype for syntax highlighting
						local ext = chunk.file:match("%.([^%.]+)$") or ""
						local ft_map = { rmd = "markdown", qmd = "markdown", Rmd = "markdown", Qmd = "markdown" }
						pcall(function()
							vim.bo[buf_id].filetype = ft_map[ext] or ext
						end)
						-- Scroll the preview window to the chunk line
						vim.schedule(function()
							-- Find a window displaying buf_id
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
					-- Unnamed chunk or unreadable file – just show the header line
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
					vim.defer_fn(function()
						vim.notify(
							"citeref: chunk has no label – add a label to use it in a cross-reference",
							vim.log.levels.WARN
						)
					end, 100)
					return
				end
				local crossref = parse.format_crossref(ref_type, chunk.label, ctx.bufnr)
				util.insert_at_context(ctx, crossref)
				vim.defer_fn(function()
					vim.notify("citeref: inserted " .. crossref, vim.log.levels.INFO)
				end, 100)
			end,
		},
	})
end

return M
