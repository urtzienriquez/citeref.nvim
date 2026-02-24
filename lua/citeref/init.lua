--- citeref.nvim – public API and buffer attachment
local M = {}

-- ─────────────────────────────────────────────────────────────
-- Helpers
-- ─────────────────────────────────────────────────────────────

local function is_picker()
  local b = require("citeref.config").get().backend
  return b == "fzf" or b == "telescope" or b == "snacks"
end

local function insert_mode()
  return vim.api.nvim_get_mode().mode:find("i") ~= nil
end

local registry = require("citeref.backends")
local parse    = require("citeref.parse")

-- ─────────────────────────────────────────────────────────────
-- Public API
-- ─────────────────────────────────────────────────────────────

function M.cite_markdown()
  if is_picker() then
    local entries = parse.load_entries()
    if #entries == 0 then return end
    registry.call("pick_citation", "markdown", entries, require("citeref.util").save_context())
  elseif insert_mode() then
    registry.call("show", "citation", "markdown")
  else
    vim.notify("citeref: normal-mode cite requires a picker backend (fzf or telescope).", vim.log.levels.WARN)
  end
end

function M.cite_latex()
  if is_picker() then
    local entries = parse.load_entries()
    if #entries == 0 then return end
    registry.call("pick_citation", "latex", entries, require("citeref.util").save_context())
  elseif insert_mode() then
    registry.call("show", "citation", "latex")
  else
    vim.notify("citeref: normal-mode cite requires a picker backend (fzf or telescope).", vim.log.levels.WARN)
  end
end

function M.cite_replace()
  if not is_picker() then
    vim.notify("citeref: cite_replace requires a picker backend (fzf or telescope).", vim.log.levels.WARN)
    return
  end
  local info = parse.citation_under_cursor()
  if not info then
    vim.notify("citeref: cursor is not on a citation.", vim.log.levels.WARN)
    return
  end
  local entries = parse.load_entries()
  if #entries == 0 then return end
  registry.call("replace", entries, info)
end

function M.crossref_figure()
  if is_picker() then
    local chunks = parse.load_chunks()
    if #chunks == 0 then
      vim.notify("citeref: no code chunks found.", vim.log.levels.WARN) ; return
    end
    registry.call("pick_crossref", "fig", chunks, require("citeref.util").save_context())
  elseif insert_mode() then
    registry.call("show", "crossref_fig")
  else
    vim.notify("citeref: normal-mode crossref requires a picker backend (fzf or telescope).", vim.log.levels.WARN)
  end
end

function M.crossref_table()
  if is_picker() then
    local chunks = parse.load_chunks()
    if #chunks == 0 then
      vim.notify("citeref: no code chunks found.", vim.log.levels.WARN) ; return
    end
    registry.call("pick_crossref", "tab", chunks, require("citeref.util").save_context())
  elseif insert_mode() then
    registry.call("show", "crossref_tab")
  else
    vim.notify("citeref: normal-mode crossref requires a picker backend (fzf or telescope).", vim.log.levels.WARN)
  end
end

-- ─────────────────────────────────────────────────────────────
-- Register a custom backend
-- ─────────────────────────────────────────────────────────────

--- Register a third-party or user-defined backend.
--- The backend table should implement any of:
---   pick_citation(format, entries, ctx)
---   pick_crossref(ref_type, chunks, ctx)
---   replace(entries, info)
---   register()        -- completion backends: register source with engine
---   show(mode, fmt)   -- completion backends: open menu
---@param name string
---@param backend table
function M.register_backend(name, backend)
  registry.register(name, backend)
end

-- ─────────────────────────────────────────────────────────────
-- Keymaps
-- ─────────────────────────────────────────────────────────────

local function map(mode, lhs, rhs, desc)
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

  -- Register completion backend source eagerly so the engine knows about it
  -- before the user types anything (needed for nvim-cmp; blink is fine lazy).
  local b = require("citeref.config").get().backend
  if b == "blink" or b == "cmp" then
    local ok, backend_mod = pcall(require, "citeref.backends." .. b)
    if ok and type(backend_mod.register) == "function" then
      backend_mod.register()
    end
  end

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
    buf, vim.bo[buf].filetype, tostring(attached[buf] == true),
    tostring(cfg.backend)))
  for _, mode in ipairs({ "n", "i" }) do
    for _, k in ipairs(vim.api.nvim_buf_get_keymap(buf, mode)) do
      if k.desc and k.desc:match("^citeref:") then
        print(string.format("  %s  %s", mode, k.lhs))
      end
    end
  end
end

return M
