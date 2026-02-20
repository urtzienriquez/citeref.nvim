--- citeref.nvim – public API and buffer attachment

local M = {}

-- ─────────────────────────────────────────────────────────────
-- Backend resolution
-- ─────────────────────────────────────────────────────────────

local _resolved_backend = nil

--- Returns the active backend: explicit config, or auto-detected.
--- Auto-detection uses pcall(require) once and caches the result.
--- This runs on first keypress, not at startup, so cost is acceptable.
local function resolved_backend()
  if _resolved_backend then return _resolved_backend end
  local explicit = require("citeref.config").get().backend
  if explicit then
    _resolved_backend = explicit
    return _resolved_backend
  end
  -- Auto-detect: try each in priority order. pcall avoids errors but does
  -- load the module — acceptable since this is deferred to first use.
  if pcall(require, "fzf-lua")   then _resolved_backend = "fzf"   ; return _resolved_backend end
  if pcall(require, "blink.cmp") then _resolved_backend = "blink" ; return _resolved_backend end
  if pcall(require, "cmp")       then _resolved_backend = "cmp"   ; return _resolved_backend end
  return nil  -- not cached so we retry on next keypress
end

local function use_fzf()
  return resolved_backend() == "fzf"
end

-- ─────────────────────────────────────────────────────────────
-- Public API
-- ─────────────────────────────────────────────────────────────

local function no_backend_warn()
  vim.notify(
    "citeref: no backend available.\n"
    .. "  Set backend = 'fzf', 'blink', or 'cmp' in setup(), or install one of those plugins.",
    vim.log.levels.WARN
  )
end

local function insert_mode()
  return vim.api.nvim_get_mode().mode:find("i") ~= nil
end

function M.cite_markdown()
  if not resolved_backend() then return no_backend_warn() end
  if use_fzf() then
    require("citeref.citation").pick_markdown()
  elseif insert_mode() then
    require("citeref.completion").show_citations_markdown()
  else
    vim.notify("citeref: normal-mode cite requires backend = 'fzf'", vim.log.levels.WARN)
  end
end

function M.cite_latex()
  if not resolved_backend() then return no_backend_warn() end
  if use_fzf() then
    require("citeref.citation").pick_latex()
  elseif insert_mode() then
    require("citeref.completion").show_citations_latex()
  else
    vim.notify("citeref: normal-mode cite requires backend = 'fzf'", vim.log.levels.WARN)
  end
end

function M.cite_replace()
  if not resolved_backend() then return no_backend_warn() end
  if use_fzf() then
    require("citeref.citation").replace()
  else
    vim.notify("citeref: cite_replace requires backend = 'fzf'", vim.log.levels.WARN)
  end
end

function M.crossref_figure()
  if not resolved_backend() then return no_backend_warn() end
  if use_fzf() then
    require("citeref.crossref").pick_figure()
  elseif insert_mode() then
    require("citeref.completion").show_crossref_fig()
  else
    vim.notify("citeref: normal-mode crossref requires backend = 'fzf'", vim.log.levels.WARN)
  end
end

function M.crossref_table()
  if not resolved_backend() then return no_backend_warn() end
  if use_fzf() then
    require("citeref.crossref").pick_table()
  elseif insert_mode() then
    require("citeref.completion").show_crossref_tab()
  else
    vim.notify("citeref: normal-mode crossref requires backend = 'fzf'", vim.log.levels.WARN)
  end
end

-- ─────────────────────────────────────────────────────────────
-- Keymaps
-- ─────────────────────────────────────────────────────────────

local function map(mode, lhs, rhs, desc)
  -- Only set if not already mapped in this buffer
  for _, km in ipairs(vim.api.nvim_buf_get_keymap(0, mode)) do
    if km.lhs == lhs then return end
  end
  vim.keymap.set(mode, lhs, rhs, { buffer = true, silent = true, desc = desc })
end

local function set_keymaps()
  local km = require("citeref.config").get().keymaps
  if not km.enabled then return end

  if km.cite_markdown_i   then map("i", km.cite_markdown_i,   M.cite_markdown,   "citeref: insert citation (markdown)") end
  if km.cite_markdown_n   then map("n", km.cite_markdown_n,   M.cite_markdown,   "citeref: insert citation (markdown)") end
  if km.cite_latex_i      then map("i", km.cite_latex_i,      M.cite_latex,      "citeref: insert citation (LaTeX)")    end
  if km.cite_latex_n      then map("n", km.cite_latex_n,      M.cite_latex,      "citeref: insert citation (LaTeX)")    end
  if km.cite_replace_n    then map("n", km.cite_replace_n,    M.cite_replace,    "citeref: replace citation under cursor") end
  if km.crossref_figure_i then map("i", km.crossref_figure_i, M.crossref_figure, "citeref: insert figure crossref")    end
  if km.crossref_figure_n then map("n", km.crossref_figure_n, M.crossref_figure, "citeref: insert figure crossref")    end
  if km.crossref_table_i  then map("i", km.crossref_table_i,  M.crossref_table,  "citeref: insert table crossref")     end
  if km.crossref_table_n  then map("n", km.crossref_table_n,  M.crossref_table,  "citeref: insert table crossref")     end
end

-- ─────────────────────────────────────────────────────────────
-- Attach
-- ─────────────────────────────────────────────────────────────

local attached = {}

function M.attach()
  local buf = vim.api.nvim_get_current_buf()
  if attached[buf] then return end
  attached[buf] = true

  set_keymaps()

  vim.api.nvim_create_autocmd("BufDelete", {
    buffer = buf, once = true,
    callback = function() attached[buf] = nil end,
  })
end

-- ─────────────────────────────────────────────────────────────
-- Setup & debug
-- ─────────────────────────────────────────────────────────────

function M.setup(opts)
  require("citeref.config").set(opts)

  -- Attach to any already-open matching buffers (e.g. setup() called late)
  local cfg    = require("citeref.config").get()
  local ft_set = {}
  for _, ft in ipairs(cfg.filetypes) do ft_set[ft] = true end

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and ft_set[vim.bo[buf].filetype] and not attached[buf] then
      local wins = vim.fn.win_findbuf(buf)
      if #wins > 0 then
        local cur = vim.api.nvim_get_current_win()
        vim.api.nvim_set_current_win(wins[1])
        M.attach()
        vim.api.nvim_set_current_win(cur)
      end
    end
  end
end

function M.debug()
  local buf = vim.api.nvim_get_current_buf()
  local cfg = require("citeref.config").get()
  print(string.format("citeref  buf=%d  ft=%q  attached=%s  backend=%s",
    buf, vim.bo[buf].filetype, tostring(attached[buf] == true), tostring(resolved_backend())))
  for _, mode in ipairs({ "n", "i" }) do
    for _, k in ipairs(vim.api.nvim_buf_get_keymap(buf, mode)) do
      if k.desc and k.desc:match("^citeref:") then
        print(string.format("  %s  %s", mode, k.lhs))
      end
    end
  end
end

return M
