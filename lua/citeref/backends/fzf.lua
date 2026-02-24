--- citeref.nvim – fzf-lua backend
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
			local next = LATEX_FORMATS[(i % #LATEX_FORMATS) + 1]
			return next
		end
	end
	return LATEX_FORMATS[1]
end

--- Build the insertion text for a latex format.
---@param keys string[]
---@param cmd string  e.g. "citep"
---@return string
local function format_latex(keys, cmd)
	return "\\" .. cmd .. "{" .. table.concat(keys, ", ") .. "}"
end

-- ─────────────────────────────────────────────────────────────
-- Shared previewer factory
-- ─────────────────────────────────────────────────────────────

--- Build a fzf-lua buffer previewer that renders CiterefEntry metadata.
---@param entries CiterefEntry[]
local function entry_previewer(entries)
	local Previewer = require("fzf-lua.previewer.builtin")
	local P = Previewer.buffer_or_file:extend()

	function P:new(o, opts, fzf_win)
		P.super.new(self, o, opts, fzf_win)
		setmetatable(self, P)
		return self
	end

	function P:parse_entry(entry_str)
		return { path = entry_str:match("^([^%s│]+)") }
	end

	function P:populate_preview_buf(entry_str)
		local key = entry_str:match("^([^%s│]+)"):gsub(" %(current%)$", "")
		local found = nil
		for _, e in ipairs(entries) do
			if e.key == key then
				found = e
				break
			end
		end
		if not found then
			return false
		end

		if not self.preview_bufnr or not vim.api.nvim_buf_is_valid(self.preview_bufnr) then
			self.preview_bufnr = vim.api.nvim_create_buf(false, true)
			vim.bo[self.preview_bufnr].bufhidden = "wipe"
		end

		vim.api.nvim_buf_set_lines(self.preview_bufnr, 0, -1, false, vim.split(parse.entry_preview(found), "\n"))
		self:set_preview_buf(self.preview_bufnr)
		self.preview_bufloaded = true
		return true
	end

	return P
end

--- Build a fzf-lua previewer that opens the source file at the chunk line.
---@param lookup table<string, CiterefChunk>
local function chunk_previewer(lookup)
	local Previewer = require("fzf-lua.previewer.builtin")
	local P = Previewer.buffer_or_file:extend()

	function P:new(o, opts, fzf_win)
		P.super.new(self, o, opts, fzf_win)
		setmetatable(self, P)
		return self
	end

	function P:parse_entry(entry_str)
		local chunk = lookup[entry_str]
		if chunk and chunk.file and chunk.file ~= "" then
			return { path = chunk.file, line = chunk.line, col = 1 }
		end
		return { path = "" }
	end

	return P
end

-- ─────────────────────────────────────────────────────────────
-- Citation picker
-- ─────────────────────────────────────────────────────────────

---@param format "markdown"|"latex"
---@param entries CiterefEntry[]
---@param ctx table
function M.pick_citation(format, entries, ctx)
	local cfg = require("citeref.config").get()

	local lookup = {}
	local lines = {}
	for _, e in ipairs(entries) do
		local d = parse.entry_display(e)
		lookup[d] = e
		lines[#lines + 1] = d
	end

	-- State for latex format cycling (only used when format == "latex")
	local default_cmd = (format == "latex") and require("citeref.config").get().default_latex_format or "cite"
	local latex_fmt = LATEX_FORMATS[1]
	for _, f in ipairs(LATEX_FORMATS) do
		if f.cmd == default_cmd then
			latex_fmt = f
			break
		end
	end

	local function current_title()
		if format == "latex" then
			return string.format(" Citations [LaTeX: %s]  <C-l> cycle ", latex_fmt.label)
		else
			return " Citations [Markdown] "
		end
	end

	local function do_insert(selected, fzf_win)
		if #selected == 0 then
			return
		end
		local keys = {}
		for _, l in ipairs(selected) do
			local e = lookup[l]
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
		util.insert_at_context(ctx, text)
		vim.defer_fn(function()
			vim.notify("citeref: inserted " .. text, vim.log.levels.INFO)
		end, 100)
	end

	-- fzf runs inside a terminal buffer. The only reliable way to have a
	-- side-effect keybind that does NOT close fzf is via winopts.on_create,
	-- which fires after the terminal window is created. We register a
	-- terminal-mode map (buffer = 0) there. The `actions` table is for binds
	-- that accept/submit items — they always close fzf.
	local on_create = nil
	if format == "latex" then
		on_create = function()
			vim.keymap.set("t", "<C-l>", function()
				latex_fmt = next_latex_format(latex_fmt.cmd)
				vim.notify("citeref: LaTeX format → " .. latex_fmt.label, vim.log.levels.INFO)
			end, { buffer = 0, nowait = true, desc = "citeref: cycle LaTeX format" })
		end
	end

	require("fzf-lua").fzf_exec(function(cb)
		for _, l in ipairs(lines) do
			cb(l)
		end
		cb()
	end, {
		prompt = "> ",
		previewer = entry_previewer(entries),
		winopts = {
			title = current_title(),
			preview = {
				layout = cfg.picker.layout or "vertical",
				vertical = "down:" .. cfg.picker.preview_size,
				horizontal = "right:" .. cfg.picker.preview_size,
				wrap = "wrap",
				scrollbar = "border",
			},
			on_create = on_create,
		},
		actions = {
			["default"] = function(selected)
				do_insert(selected)
			end,
		},
	})
end

-- ─────────────────────────────────────────────────────────────
-- Replace citation under cursor
-- ─────────────────────────────────────────────────────────────

---@param entries CiterefEntry[]
---@param info table
function M.replace(entries, info)
	local buf = vim.api.nvim_get_current_buf()
	local cfg = require("citeref.config").get()
	local row = vim.api.nvim_win_get_cursor(0)[1]
	local lookup = {}

	require("fzf-lua").fzf_exec(function(cb)
		for _, e in ipairs(entries) do
			local d = parse.entry_display(e)
			if e.key == info.key then
				d = d .. " (current)"
			end
			lookup[d] = e
			cb(d)
		end
		cb()
	end, {
		prompt = "replace with> ",
		previewer = entry_previewer(entries),
		winopts = {
			title = " Replace @" .. info.key .. " ",
			preview = {
				layout = cfg.picker.layout or "vertical",
				vertical = "down:50%",
				horizontal = "right:50%",
				wrap = "wrap",
				scrollbar = "border",
			},
		},
		actions = {
			["default"] = function(selected)
				if #selected == 0 then
					return
				end
				local e = lookup[selected[1]]
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
	local title = ref_type == "fig" and " Figure Crossref " or " Table Crossref "
	local cfg = require("citeref.config").get()
	local lookup = {}
	local display_list = {}

	for _, c in ipairs(chunks) do
		lookup[c.display] = c
		display_list[#display_list + 1] = c.display
	end

	require("fzf-lua").fzf_exec(function(cb)
		for _, d in ipairs(display_list) do
			cb(d)
		end
		cb()
	end, {
		prompt = "chunk> ",
		previewer = chunk_previewer(lookup),
		winopts = {
			title = title,
			preview = {
				layout = "horizontal",
				vertical = "down:50%",
				horizontal = "right:65%",
				wrap = "wrap",
			},
		},
		actions = {
			["default"] = function(selected)
				if #selected == 0 then
					return
				end
				local chunk = lookup[selected[1]]
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
				local crossref = string.format("\\@ref(%s:%s)", ref_type, chunk.label)
				util.insert_at_context(ctx, crossref)
				vim.defer_fn(function()
					vim.notify("citeref: inserted " .. crossref, vim.log.levels.INFO)
				end, 100)
			end,
		},
	})
end

return M
