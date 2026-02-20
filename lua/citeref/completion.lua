--- citeref.nvim – completion source
--- Registers a source with blink.cmp (preferred) or nvim-cmp (fallback).
--- Items are built from the same bib/chunk data as the fzf-lua pickers.

local M = {}

-- ─────────────────────────────────────────────────────────────
-- Backend (reads config – no auto-detection)
-- ─────────────────────────────────────────────────────────────

local function engine()
  local backend = require("citeref.config").get().backend
  if backend == "blink" or backend == "cmp" then return backend end
  if backend == nil then
    if pcall(require, "blink.cmp") then return "blink" end
    if pcall(require, "cmp")       then return "cmp"   end
  end
  return "none"
end

-- ─────────────────────────────────────────────────────────────
-- State – set before triggering so get_completions reads it.
--
--   _current_mode:
--     "citation"     → show citation items only
--     "crossref_fig" → show figure crossref items only
--     "crossref_tab" → show table crossref items only
--     "all"          → show everything (auto-triggered via @)
--
--   _current_format (citations only):
--     "markdown" → @key
--     "latex"    → \cite{key}
-- ─────────────────────────────────────────────────────────────

local _current_mode   = "all"
local _current_format = "markdown"

local function reset_state()
  _current_mode   = "all"
  _current_format = "markdown"
end

-- ─────────────────────────────────────────────────────────────
-- Build completion items
-- ─────────────────────────────────────────────────────────────

local KIND = { Reference = 18, Value = 12, Field = 5 }

---@param format "markdown"|"latex"
---@return table[]
local function citation_items(format)
  format = format or "markdown"
  local ok, citation = pcall(require, "citeref.citation")
  if not ok then return {} end

  -- Resolve bib files (same logic as citation.lua but without side-effect warnings)
  local bib_files = {}
  local seen      = {}
  local function add(path)
    local exp = vim.fn.expand(path)
    if not seen[exp] and vim.fn.filereadable(exp) == 1 then
      seen[exp]              = true
      bib_files[#bib_files+1] = exp
    end
  end

  local ok2, cfg_mod = pcall(require, "citeref.config")
  if ok2 then
    local cfg = cfg_mod.get()
    if cfg.bib_files then
      local files = type(cfg.bib_files) == "function" and cfg.bib_files() or cfg.bib_files
      for _, f in ipairs(files) do add(f) end
    end
  end
  for _, f in ipairs(vim.fn.globpath(vim.fn.getcwd(), "*.bib", false, true)) do
    add(f)
  end

  local items = {}
  for _, path in ipairs(bib_files) do
    for _, entry in ipairs(citation.parse_bib(path)) do
      local insert = format == "latex"
        and ("\\cite{" .. entry.key .. "}")
        or  ("@" .. entry.key)
      local detail = table.concat(
        vim.tbl_filter(function(s) return s ~= "" end, {
          entry.author, entry.year, entry.journaltitle,
        }), " · "
      )
      items[#items+1] = {
        label         = insert,
        kind          = KIND.Reference,
        detail        = detail ~= "" and detail or nil,
        documentation = entry.title ~= "" and {
          kind  = "plaintext",
          value = entry.title
            .. (entry.abstract ~= "" and ("\n\n" .. entry.abstract) or ""),
        } or nil,
        insertText    = insert,
        data          = { type = "citation", key = entry.key, format = format },
      }
    end
  end
  return items
end

--- Get all chunks via crossref module (current buf + sibling files, named + unnamed).
--- Returns only named chunks for insertion (unnamed can't be cross-referenced),
--- but shows them in the list with a clear label so the user knows they exist.
---@return CiterefChunk[]
local function get_all_chunks()
  local ok, crossref = pcall(require, "citeref.crossref")
  if not ok then return {} end
  return crossref.all_chunks()
end

---@return table[]
local function crossref_fig_items()
  local items = {}
  for _, c in ipairs(get_all_chunks()) do
    local insert, detail, kind_val
    if c.label == "" then
      -- Unnamed chunk: show it but mark as unusable for crossref
      insert   = "[unnamed chunk · line " .. c.line .. " · " .. vim.fn.fnamemodify(c.file, ":t") .. "]"
      detail   = "⚠ needs a label to use in \\@ref(fig:...)"
      kind_val = KIND.Field  -- distinct kind so user can see it's different
    else
      insert   = "\\@ref(fig:" .. c.label .. ")"
      detail   = "figure · line " .. c.line .. (c.is_current and "" or " · " .. vim.fn.fnamemodify(c.file, ":t"))
      kind_val = KIND.Value
    end
    items[#items+1] = {
      label      = insert,
      kind       = kind_val,
      detail     = detail,
      insertText = c.label ~= "" and insert or "",  -- don't insert anything for unnamed
      data       = { type = "crossref_fig", label = c.label, line = c.line, file = c.file },
    }
  end
  return items
end

---@return table[]
local function crossref_tab_items()
  local items = {}
  for _, c in ipairs(get_all_chunks()) do
    local insert, detail, kind_val
    if c.label == "" then
      insert   = "[unnamed chunk · line " .. c.line .. " · " .. vim.fn.fnamemodify(c.file, ":t") .. "]"
      detail   = "⚠ needs a label to use in \\@ref(tab:...)"
      kind_val = KIND.Reference
    else
      insert   = "\\@ref(tab:" .. c.label .. ")"
      detail   = "table · line " .. c.line .. (c.is_current and "" or " · " .. vim.fn.fnamemodify(c.file, ":t"))
      kind_val = KIND.Field
    end
    items[#items+1] = {
      label      = insert,
      kind       = kind_val,
      detail     = detail,
      insertText = c.label ~= "" and insert or "",
      data       = { type = "crossref_tab", label = c.label, line = c.line, file = c.file },
    }
  end
  return items
end

--- Return items appropriate for the current mode/format state.
---@return table[]
local function current_items()
  local mode = _current_mode
  if mode == "citation" then
    return citation_items(_current_format)
  elseif mode == "crossref_fig" then
    return crossref_fig_items()
  elseif mode == "crossref_tab" then
    return crossref_tab_items()
  else
    -- "all" – auto-triggered via @; show citations (markdown) + both crossref types
    local items = {}
    vim.list_extend(items, citation_items("markdown"))
    vim.list_extend(items, crossref_fig_items())
    vim.list_extend(items, crossref_tab_items())
    return items
  end
end

-- ─────────────────────────────────────────────────────────────
-- blink.cmp source
-- ─────────────────────────────────────────────────────────────

local BlinkSource = {}
BlinkSource.__index = BlinkSource

function BlinkSource.new()
  return setmetatable({}, BlinkSource)
end

function BlinkSource:get_trigger_characters()
  return { "@" }
end

function BlinkSource:get_completions(ctx, callback)
  callback({
    items                  = current_items(),
    is_incomplete_forward  = false,
    is_incomplete_backward = false,
  })
end

function BlinkSource:enabled()
  -- Always return true here. Filetype scoping is handled by blink.cmp's own
  -- per_filetype config (see README). If the user adds "citeref" only to
  -- per_filetype.markdown etc., blink will only call this source in those
  -- filetypes. A filetype check here would conflict with that.
  return true
end

-- ─────────────────────────────────────────────────────────────
-- nvim-cmp source
-- ─────────────────────────────────────────────────────────────

local CmpSource = {}
CmpSource.__index = CmpSource

function CmpSource.new()
  return setmetatable({}, CmpSource)
end

function CmpSource:get_trigger_characters()
  return { "@" }
end

function CmpSource:is_available()
  -- Always true; filetype scoping is handled by nvim-cmp's filetype source config.
  return true
end

function CmpSource:complete(_, callback)
  callback({ items = current_items(), isIncomplete = false })
end

function CmpSource:get_debug_name()
  return "citeref"
end

-- ─────────────────────────────────────────────────────────────
-- Force-open helpers (keymaps when fzf-lua absent)
-- ─────────────────────────────────────────────────────────────

local function trigger_menu()
  M.register()  -- no-op if already registered
  local e = engine()
  if e == "blink" then
    require("blink.cmp").show({ providers = { "citeref" } })
    vim.api.nvim_create_autocmd("User", {
      pattern  = "BlinkCmpMenuHide",
      once     = true,
      callback = reset_state,
    })
  elseif e == "cmp" then
    require("cmp").complete({ config = { sources = { { name = "citeref" } } } })
    vim.api.nvim_create_autocmd("User", {
      pattern  = "CmpMenuClosed",
      once     = true,
      callback = reset_state,
    })
  else
    reset_state()
    vim.notify(
      "citeref: no completion engine available (blink.cmp or nvim-cmp required)",
      vim.log.levels.WARN
    )
  end
end

--- Open menu with citation items in markdown (@key) format.
function M.show_citations_markdown()
  _current_mode   = "citation"
  _current_format = "markdown"
  trigger_menu()
end

--- Open menu with citation items in LaTeX (\cite{key}) format.
function M.show_citations_latex()
  _current_mode   = "citation"
  _current_format = "latex"
  trigger_menu()
end

--- Open menu with figure crossref items only (\@ref(fig:...)).
function M.show_crossref_fig()
  _current_mode   = "crossref_fig"
  _current_format = "markdown"
  trigger_menu()
end

--- Open menu with table crossref items only (\@ref(tab:...)).
function M.show_crossref_tab()
  _current_mode   = "crossref_tab"
  _current_format = "markdown"
  trigger_menu()
end

-- ─────────────────────────────────────────────────────────────
-- Registration
-- ─────────────────────────────────────────────────────────────

local _registered = false

function M.register()
  if _registered then return end
  local e = engine()
  if e == "blink" then
    local ok, blink = pcall(require, "blink.cmp")
    if ok and blink.add_provider then
      blink.add_provider("citeref", { name = "citeref", module = "citeref.completion" })
    end
    _registered = true
  elseif e == "cmp" then
    local ok, cmp = pcall(require, "cmp")
    if ok then
      cmp.register_source("citeref", CmpSource.new())
      _registered = true
    end
  end
end

--- blink.cmp calls this when module = "citeref.completion"
function M.new()
  return BlinkSource.new()
end

return M
