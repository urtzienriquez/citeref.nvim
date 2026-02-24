--- citeref.nvim – blink.cmp backend
local parse = require("citeref.parse")

local M = {}

-- ─────────────────────────────────────────────────────────────
-- State
-- ─────────────────────────────────────────────────────────────

local _mode = "all" -- "all"|"citation"|"crossref_fig"|"crossref_tab"
local _format = "markdown"

local function reset()
	_mode = "all"
	_format = "markdown"
end

-- ─────────────────────────────────────────────────────────────
-- Item builders (shared with cmp backend via parse module)
-- ─────────────────────────────────────────────────────────────

local KIND = { Reference = 18, Value = 12, Field = 5 }

local function citation_items(format)
	local entries = parse.load_entries()
	local items = {}
	for _, e in ipairs(entries) do
		local insert = format == "latex" and ("\\cite{" .. e.key .. "}") or ("@" .. e.key)
		local detail = table.concat(
			vim.tbl_filter(function(s)
				return s ~= ""
			end, { e.author, e.year, e.journaltitle }),
			" · "
		)
		items[#items + 1] = {
			label = insert,
			kind = KIND.Reference,
			detail = detail ~= "" and detail or nil,
			documentation = e.title ~= "" and {
				kind = "plaintext",
				value = e.title .. (e.abstract ~= "" and ("\n\n" .. e.abstract) or ""),
			} or nil,
			insertText = insert,
			data = { type = "citation", key = e.key, format = format },
		}
	end
	return items
end

local function crossref_items(ref_type)
	local chunks = parse.load_chunks()
	local items = {}
	for _, c in ipairs(chunks) do
		local insert, detail, kind_val
		if c.label == "" then
			insert = "[unnamed chunk · line " .. c.line .. " · " .. vim.fn.fnamemodify(c.file, ":t") .. "]"
			detail = "⚠ needs a label to use in \\@ref(" .. ref_type .. ":...)"
			kind_val = KIND.Field
		else
			insert = "\\@ref(" .. ref_type .. ":" .. c.label .. ")"
			detail = ref_type
				.. " · line "
				.. c.line
				.. (c.is_current and "" or " · " .. vim.fn.fnamemodify(c.file, ":t"))
			kind_val = KIND.Value
		end
		items[#items + 1] = {
			label = insert,
			kind = kind_val,
			detail = detail,
			insertText = c.label ~= "" and insert or "",
			data = { type = "crossref_" .. ref_type, label = c.label, line = c.line, file = c.file },
		}
	end
	return items
end

local function current_items()
	if _mode == "citation" then
		return citation_items(_format)
	end
	if _mode == "crossref_fig" then
		return crossref_items("fig")
	end
	if _mode == "crossref_tab" then
		return crossref_items("tab")
	end
	-- "all"
	local items = {}
	vim.list_extend(items, citation_items("markdown"))
	vim.list_extend(items, crossref_items("fig"))
	vim.list_extend(items, crossref_items("tab"))
	return items
end

-- ─────────────────────────────────────────────────────────────
-- blink.cmp source object
-- ─────────────────────────────────────────────────────────────

local Source = {}
Source.__index = Source

function Source.new()
	return setmetatable({}, Source)
end

function Source:get_trigger_characters()
	return { "@" }
end

function Source:get_completions(ctx, callback)
	local before = ctx.line:sub(1, ctx.cursor[2])
	if not before:match("@[%w_%-:%.]*$") then
		callback({ items = {}, is_incomplete_forward = false, is_incomplete_backward = false })
		return
	end
	callback({ items = current_items(), is_incomplete_forward = false, is_incomplete_backward = false })
end

function Source:enabled()
	return true
end

-- ─────────────────────────────────────────────────────────────
-- Backend interface
-- ─────────────────────────────────────────────────────────────

local _registered = false

--- Called once to register the source with blink.cmp.
function M.register()
	if _registered then
		return
	end
	local ok, blink = pcall(require, "blink.cmp")
	if ok and blink.add_provider then
		blink.add_provider("citeref", { name = "citeref", module = "citeref.backends.blink" })
	end
	_registered = true
end

--- blink calls this when module = "citeref.backends.blink"
function M.new()
	return Source.new()
end

--- Open the completion menu in a specific mode (called by keymaps).
---@param mode "citation"|"crossref_fig"|"crossref_tab"|"all"
---@param format? "markdown"|"latex"
function M.show(mode, format)
	_mode = mode or "all"
	_format = format or "markdown"
	M.register()
	require("blink.cmp").show({ providers = { "citeref" } })
	vim.api.nvim_create_autocmd("User", {
		pattern = "BlinkCmpMenuHide",
		once = true,
		callback = reset,
	})
end

return M
