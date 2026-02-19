--- citeref.nvim – configuration defaults and merging
---@class CiterefConfig
---@field filetypes string[]                 Filetypes where citeref activates
---@field bib_files string[]|fun():string[]  Explicit bib paths, or a function returning them
---@field keymaps CiterefKeymapConfig
---@field picker CiterefPickerConfig

---@class CiterefKeymapConfig
---@field enabled           boolean       Set false to disable ALL default keymaps
---@field cite_markdown_i   string|false  Insert citation (markdown @key)  – insert mode
---@field cite_markdown_n   string|false  Insert citation (markdown @key)  – normal mode
---@field cite_latex_i      string|false  Insert citation (\cite{})        – insert mode
---@field cite_latex_n      string|false  Insert citation (\cite{})        – normal mode
---@field cite_replace_n    string|false  Replace citation under cursor    – normal mode only
---@field crossref_figure_i string|false  Insert figure crossref           – insert mode
---@field crossref_figure_n string|false  Insert figure crossref           – normal mode
---@field crossref_table_i  string|false  Insert table crossref            – insert mode
---@field crossref_table_n  string|false  Insert table crossref            – normal mode

---@class CiterefPickerConfig
---@field layout "vertical"|"horizontal"
---@field preview_size string   e.g. "50%"

local M = {}

---@type CiterefConfig
M.defaults = {
  -- Neovim filetype values (always lowercase) for the file extensions you care about:
  --   .md / .markdown  → "markdown"
  --   .Rmd / .rmd      → "rmd"
  --   .qmd / .Qmd      → "quarto"
  --   .jmd / .Jmd      → "markdown" (Julia markdown, Neovim calls it markdown)
  --   .tex             → "tex"  (or "latex" depending on content)
  --   .rnw / .Rnw      → "rnoweb"
  --   pandoc files     → "pandoc"
  filetypes = {
    "markdown",
    "rmd",
    "quarto",
    "rnoweb",
    "pandoc",
    "tex",
    "latex",
  },

  -- By default we look for ~/Documents/zotero.bib + any *.bib in cwd.
  -- Users can supply an explicit list or a callable.
  bib_files = nil,

  keymaps = {
    enabled           = true,
    -- citations
    cite_markdown_i   = "<C-a>m",      -- insert mode
    cite_markdown_n   = "<leader>am",  -- normal mode
    cite_latex_i      = "<C-a>l",
    cite_latex_n      = "<leader>al",
    cite_replace_n    = "<leader>ar",  -- normal mode only (cursor must be on a key)
    -- cross-references
    crossref_figure_i = "<C-a>f",
    crossref_figure_n = "<leader>af",
    crossref_table_i  = "<C-a>t",
    crossref_table_n  = "<leader>at",
  },

  picker = {
    layout       = "vertical",
    preview_size = "50%",
  },
}

---@type CiterefConfig
M.options = {}
local _initialized = false

--- Called once (optionally) by the user via require('citeref').setup(opts).
--- Safe to call multiple times – later calls win.
---@param opts? table
function M.set(opts)
  M.options      = vim.tbl_deep_extend("force", M.defaults, opts or {})
  _initialized   = true
end

--- Return resolved config, initialising with defaults if setup() was never called.
---@return CiterefConfig
function M.get()
  if not _initialized then
    M.options    = vim.deepcopy(M.defaults)
    _initialized = true
  end
  return M.options
end

return M
