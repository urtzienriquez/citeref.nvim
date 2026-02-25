--- citeref.nvim – telescope backend
local util = require("citeref.util")
local parse = require("citeref.parse")

local M = {}

local function parse_size(s)
	if type(s) == "number" then
		return s
	end
	local pct = tostring(s):match("^(%d+)%%$")
	return pct and (tonumber(pct) / 100) or 0.5
end

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
-- Shared ranking helper
-- ─────────────────────────────────────────────────────────────

---@param entries CiterefEntry[]
---@param query string
---@return CiterefEntry[]
local function rank_entries(entries, query)
	if not query or query == "" then
		return entries
	end
	local q = query:lower()
	local key_start, key_contains, other_matches = {}, {}, {}
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

-- ─────────────────────────────────────────────────────────────
-- Shared previewer factories
-- ─────────────────────────────────────────────────────────────

local function entry_previewer()
	return require("telescope.previewers").new_buffer_previewer({
		title = "Entry",
		define_preview = function(self, entry)
			vim.api.nvim_buf_set_lines(
				self.state.bufnr,
				0,
				-1,
				false,
				vim.split(parse.entry_preview(entry.value), "\n")
			)
			if self.state.winid and vim.api.nvim_win_is_valid(self.state.winid) then
				vim.wo[self.state.winid].wrap = true
			end
		end,
	})
end

local function chunk_previewer()
	local conf = require("telescope.config").values
	return require("telescope.previewers").new_buffer_previewer({
		title = "Chunk",
		define_preview = function(self, entry)
			local chunk = entry.value
			if chunk.file and chunk.file ~= "" then
				conf.buffer_previewer_maker(chunk.file, self.state.bufnr, {
					bufname = self.state.bufname,
					winid = self.state.winid,
					callback = function(bufnr)
						pcall(vim.api.nvim_win_set_cursor, self.state.winid, { chunk.line, 0 })
						pcall(vim.api.nvim_buf_call, bufnr, function()
							vim.cmd("norm! zz")
						end)
					end,
				})
			else
				vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, { chunk.header or "" })
			end
		end,
	})
end

-- ─────────────────────────────────────────────────────────────
-- Citation picker
-- ─────────────────────────────────────────────────────────────

---@param format "markdown"|"latex"
---@param entries CiterefEntry[]
---@param ctx table
function M.pick_citation(format, entries, ctx)
	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local sorters = require("telescope.sorters")
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")
	local cfg = require("citeref.config").get()
	local layout = cfg.picker.layout or "vertical"

	-- Mutable state for latex format cycling
	local default_cmd = (format == "latex") and cfg.default_latex_format or "cite"
	local latex_fmt = LATEX_FORMATS[1]
	for _, f in ipairs(LATEX_FORMATS) do
		if f.cmd == default_cmd then
			latex_fmt = f
			break
		end
	end

	local function current_title()
		if format == "latex" then
			return string.format(" Citations %s [<C-l> cycle] ", latex_fmt.label)
		else
			return " Citations @ "
		end
	end

	pickers
		.new({}, {
			prompt_title = current_title(),
			layout_strategy = layout == "vertical" and "vertical" or "horizontal",
			layout_config = {
				vertical = { preview_height = parse_size(cfg.picker.preview_size), preview_cutoff = 0 },
				horizontal = { preview_width = parse_size(cfg.picker.preview_size), preview_cutoff = 0 },
			},
			finder = finders.new_dynamic({
				fn = function(query)
					return rank_entries(entries, query)
				end,
				entry_maker = function(e)
					local d = parse.entry_display(e)
					return { value = e, display = d, ordinal = d }
				end,
			}),
			previewer = entry_previewer(),
			sorter = sorters.empty(),
			attach_mappings = function(prompt_bufnr, map)
				-- Confirm (insert citation)
				actions.select_default:replace(function()
					local picker = action_state.get_current_picker(prompt_bufnr)
					local selected = picker:get_multi_selection()
					if #selected == 0 then
						selected = { action_state.get_selected_entry() }
					end
					actions.close(prompt_bufnr)
					if not selected or #selected == 0 then
						return
					end

					local keys = {}
					for _, sel in ipairs(selected) do
						if sel and sel.value then
							keys[#keys + 1] = sel.value.key
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
					util.insert_at_context(ctx, text)
					vim.defer_fn(function()
						vim.notify("citeref: inserted " .. text, vim.log.levels.INFO)
					end, 100)
				end)

				-- Cycle latex format with <C-l> (no-op for markdown)
				if format == "latex" then
					map({ "i", "n" }, "<C-l>", function()
						latex_fmt = next_latex_format(latex_fmt.cmd)
						local picker = action_state.get_current_picker(prompt_bufnr)
						local border = picker.prompt_border
						if border and border.change_title then
							border:change_title(current_title())
						end
					end)
				end

				return true
			end,
		})
		:find()
end

-- ─────────────────────────────────────────────────────────────
-- Replace citation under cursor
-- ─────────────────────────────────────────────────────────────

---@param entries CiterefEntry[]
---@param info table
function M.replace(entries, info)
	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local sorters = require("telescope.sorters")
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")
	local buf = vim.api.nvim_get_current_buf()
	local row = vim.api.nvim_win_get_cursor(0)[1]
	local cfg = require("citeref.config").get()
	local layout = cfg.picker.layout or "vertical"

	pickers
		.new({}, {
			prompt_title = "Replace @" .. info.key,
			layout_strategy = layout == "vertical" and "vertical" or "horizontal",
			layout_config = {
				vertical = { preview_height = parse_size(cfg.picker.preview_size), preview_cutoff = 0 },
				horizontal = { preview_width = parse_size(cfg.picker.preview_size), preview_cutoff = 0 },
			},
			finder = finders.new_dynamic({
				fn = function(query)
					return rank_entries(entries, query)
				end,
				entry_maker = function(e)
					local d = parse.entry_display(e)
					if e.key == info.key then
						d = d .. " (current)"
					end
					return { value = e, display = d, ordinal = d }
				end,
			}),
			previewer = entry_previewer(),
			sorter = sorters.empty(),
			attach_mappings = function(prompt_bufnr)
				actions.select_default:replace(function()
					local sel = action_state.get_selected_entry()
					actions.close(prompt_bufnr)
					if not sel or sel.value.key == info.key then
						vim.defer_fn(function()
							vim.notify("citeref: same citation selected – no change", vim.log.levels.INFO)
						end, 100)
						return
					end
					local replacement = info.style == "latex" and sel.value.key or ("@" .. sel.value.key)
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
							vim.notify(
								string.format("citeref: %s → %s", info.key, sel.value.key),
								vim.log.levels.INFO
							)
						else
							vim.notify("citeref: replacement failed – " .. tostring(err), vim.log.levels.ERROR)
						end
					end, 100)
				end)
				return true
			end,
		})
		:find()
end

-- ─────────────────────────────────────────────────────────────
-- Crossref picker
-- ─────────────────────────────────────────────────────────────

---@param ref_type "fig"|"tab"
---@param chunks CiterefChunk[]
---@param ctx table
function M.pick_crossref(ref_type, chunks, ctx)
	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")
	local title = ref_type == "fig" and "Figure Crossref" or "Table Crossref"
	local cfg = require("citeref.config").get()

	pickers
		.new({}, {
			prompt_title = title,
			layout_strategy = "horizontal",
			layout_config = {
				horizontal = { preview_width = parse_size(cfg.picker.preview_size), preview_cutoff = 0 },
			},
			finder = finders.new_table({
				results = chunks,
				entry_maker = function(c)
					return { value = c, display = c.display, ordinal = c.display }
				end,
			}),
			previewer = chunk_previewer(),
			sorter = conf.generic_sorter({}),
			attach_mappings = function(prompt_bufnr)
				actions.select_default:replace(function()
					local sel = action_state.get_selected_entry()
					actions.close(prompt_bufnr)
					if not sel then
						return
					end
					local chunk = sel.value
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
				end)
				return true
			end,
		})
		:find()
end

return M
