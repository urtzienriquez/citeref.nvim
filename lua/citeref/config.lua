--- citeref.nvim – configuration defaults and merging
---@class CiterefConfig
---@field backend "fzf"|"telescope"|"blink"|"cmp"  Required – no auto-detection
---@field filetypes string[]
---@field bib_files string[]|fun():string[]
---@field keymaps CiterefKeymapConfig
---@field picker CiterefPickerConfig

---@class CiterefKeymapConfig
---@field enabled           boolean
---@field cite_markdown_i   string|false
---@field cite_markdown_n   string|false
---@field cite_latex_i      string|false
---@field cite_latex_n      string|false
---@field cite_replace_n    string|false
---@field crossref_figure_i string|false
---@field crossref_figure_n string|false
---@field crossref_table_i  string|false
---@field crossref_table_n  string|false

---@class CiterefPickerConfig
---@field layout "vertical"|"horizontal"
---@field preview_size string

local M = {}

---@type CiterefConfig
M.defaults = {
  -- Backend is REQUIRED. Set one of:
  --   "fzf"       → fzf-lua: full picker with preview, insert + normal mode
  --   "telescope" → telescope.nvim: full picker with preview, insert + normal mode
  --   "blink"     → blink.cmp: completion menu, insert mode only
  --   "cmp"       → nvim-cmp: completion menu, insert mode only
  backend = nil,

  filetypes = {
    "markdown",
    "rmd",
    "quarto",
    "rnoweb",
    "pandoc",
    "tex",
    "latex",
  },

  bib_files = nil,

  keymaps = {
    enabled           = true,
    cite_markdown_i   = "<C-a>m",
    cite_markdown_n   = "<leader>am",
    cite_latex_i      = "<C-a>l",
    cite_latex_n      = "<leader>al",
    cite_replace_n    = "<leader>ar",
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

local VALID_BACKENDS = { fzf = true, telescope = true, blink = true, cmp = true }

---@param opts? table
function M.set(opts)
  M.options    = vim.tbl_deep_extend("force", M.defaults, opts or {})
  _initialized = true

  if M.options.backend == nil then
    vim.notify(
      "citeref: backend is not set.\n"
      .. "  Add backend = 'fzf', 'telescope', 'blink', or 'cmp' to your setup() call.",
      vim.log.levels.WARN
    )
  elseif not VALID_BACKENDS[M.options.backend] then
    vim.notify(
      "citeref: unknown backend '" .. tostring(M.options.backend) .. "'.\n"
      .. "  Valid values: 'fzf', 'telescope', 'blink', 'cmp'.",
      vim.log.levels.ERROR
    )
  end
end

---@return CiterefConfig
function M.get()
  if not _initialized then
    M.options    = vim.deepcopy(M.defaults)
    _initialized = true
    -- Warn on first use if setup() was never called
    vim.schedule(function()
      vim.notify(
        "citeref: setup() was not called – backend is not set.\n"
        .. "  Add require('citeref').setup({ backend = 'fzf' }) to your config.",
        vim.log.levels.WARN
      )
    end)
  end
  return M.options
end

return M
