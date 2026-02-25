--- citeref.nvim – nvim-cmp backend
local parse = require("citeref.parse")
local M = {}

-- ─────────────────────────────────────────────────────────────
-- State
-- ─────────────────────────────────────────────────────────────

local _mode = "all"
local _format = "markdown"

local function reset()
  _mode = "all"
  _format = "markdown"
end

-- ─────────────────────────────────────────────────────────────
-- Item builders (same logic as blink backend)
-- ─────────────────────────────────────────────────────────────

local KIND = { Reference = 18, Value = 12, Field = 5 }

local function citation_items(format)
  local entries = parse.load_entries()
  local items = {}
  for _, e in ipairs(entries) do
    local insert
    if format == "latex" then
      insert = "\\cite{" .. e.key .. "}"
    elseif format == "latex_key" then
      insert = e.key .. "}" -- user already typed \cite{, just need the key; they close with }
    else
      insert = "@" .. e.key
    end
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
  local bufnr = vim.api.nvim_get_current_buf()
  local items = {}
  for _, c in ipairs(chunks) do
    local insert, detail, kind_val
    if c.label == "" then
      insert = "[unnamed chunk · line " .. c.line .. " · " .. vim.fn.fnamemodify(c.file, ":t") .. "]"
      detail = "⚠ needs a label to use in a cross-reference"
      kind_val = KIND.Field
    else
      insert = parse.format_crossref(ref_type, c.label, bufnr)
      detail = ref_type .. " · line " .. c.line .. (c.is_current and "" or " · " .. vim.fn.fnamemodify(c.file, ":t"))
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

--- In Quarto, crossrefs use plain `@label` regardless of fig/tab type,
--- so each chunk should appear exactly once rather than twice.
local function crossref_items_quarto()
  local chunks = parse.load_chunks()
  local items = {}
  for _, c in ipairs(chunks) do
    local insert, detail, kind_val
    if c.label == "" then
      insert = "[unnamed chunk · line " .. c.line .. " · " .. vim.fn.fnamemodify(c.file, ":t") .. "]"
      detail = "⚠ needs a label to use in a cross-reference"
      kind_val = KIND.Field
    else
      insert = "@" .. c.label
      detail = "chunk · line " .. c.line .. (c.is_current and "" or " · " .. vim.fn.fnamemodify(c.file, ":t"))
      kind_val = KIND.Value
    end
    items[#items + 1] = {
      label = insert,
      kind = kind_val,
      detail = detail,
      insertText = c.label ~= "" and insert or "",
      data = { type = "crossref", label = c.label, line = c.line, file = c.file },
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
  -- "all": in Quarto emit each chunk once; in rmarkdown keep fig+tab separate
  local bufnr = vim.api.nvim_get_current_buf()
  local ft = vim.bo[bufnr].filetype
  local items = {}
  vim.list_extend(items, citation_items("markdown"))
  if ft == "quarto" then
    vim.list_extend(items, crossref_items_quarto())
  else
    vim.list_extend(items, crossref_items("fig"))
    vim.list_extend(items, crossref_items("tab"))
  end
  return items
end

-- ─────────────────────────────────────────────────────────────
-- nvim-cmp source object
-- ─────────────────────────────────────────────────────────────

local Source = {}
Source.__index = Source

function Source.new()
  return setmetatable({}, Source)
end

function Source:get_trigger_characters()
  return { "{", "@" }
end

function Source:is_available()
  return true
end

function Source:get_debug_name()
  return "citeref"
end

function Source:complete(request, callback)
  local before = request.context.cursor_before_line
  local bufnr = vim.api.nvim_get_current_buf()
  local ft = vim.bo[bufnr].filetype

  -- LaTeX citation trigger: \cite{...}
  if before:match("\\[%a]*cite[%a]*%{$") then
    callback({ items = citation_items("latex_key"), isIncomplete = false })
    return
  end

  -- R Markdown crossref trigger: fires from \@ onward, covering \@, \@ref, \@ref(, \@ref(partial.
  -- Must be checked before the plain @ trigger to avoid the @ in \@ matching citations.
  if ft ~= "quarto" and before:match("\\@%a*%(?[%w_%-%.]*$") then
    local items = {}
    vim.list_extend(items, crossref_items("fig"))
    vim.list_extend(items, crossref_items("tab"))
    callback({ items = items, isIncomplete = false })
    return
  end

  -- @ trigger: citations in all filetypes; crossrefs too in Quarto.
  -- Guard against matching the @ inside \@ sequences handled above.
  if before:match("@[%w_%-:%.]*$") and not before:match("\\@") then
    if ft == "quarto" then
      callback({ items = current_items(), isIncomplete = false })
    else
      callback({ items = citation_items("markdown"), isIncomplete = false })
    end
    return
  end

  callback({ items = {}, isIncomplete = false })
end

-- ─────────────────────────────────────────────────────────────
-- Backend interface
-- ─────────────────────────────────────────────────────────────

local _registered = false

function M.register()
  if _registered then
    return
  end
  local ok, cmp = pcall(require, "cmp")
  if ok then
    cmp.register_source("citeref", Source.new())
    _registered = true
  end
end

---@param mode "citation"|"crossref_fig"|"crossref_tab"|"all"
---@param format? "markdown"|"latex"
function M.show(mode, format)
  _mode = mode or "all"
  _format = format or "markdown"
  M.register()
  require("cmp").complete({ config = { sources = { { name = "citeref" } } } })
  vim.api.nvim_create_autocmd("User", {
    pattern = "CmpMenuClosed",
    once = true,
    callback = reset,
  })
end

return M
