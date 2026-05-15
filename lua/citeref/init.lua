--- citeref.nvim – public API and buffer attachment
local M = {}

-- ─────────────────────────────────────────────────────────────
-- Helpers
-- ─────────────────────────────────────────────────────────────

local function is_picker()
  local b = require("citeref.config").get().backend
  return b == "fzf" or b == "telescope" or b == "snacks" or b == "minipick"
end

local function insert_mode()
  return vim.api.nvim_get_mode().mode:find("i") ~= nil
end

local registry = require("citeref.backends")
local parse = require("citeref.parse")

-- ─────────────────────────────────────────────────────────────
-- Public API
-- ─────────────────────────────────────────────────────────────

function M.cite_markdown()
  if is_picker() then
    local entries = parse.load_entries()
    if #entries == 0 then
      return
    end
    registry.call("pick_citation", "markdown", entries, require("citeref.util").save_context())
  elseif insert_mode() then
    registry.call("show", "citation", "markdown")
  else
    vim.notify(
      "citeref: normal-mode cite requires a picker backend (fzf, telescope, snacks, or minipick).",
      vim.log.levels.WARN
    )
  end
end

function M.cite_latex()
  if is_picker() then
    local entries = parse.load_entries()
    if #entries == 0 then
      return
    end

    local cfg = require("citeref.config").get()
    local LATEX_FORMATS = require("citeref.latex_formats")

    local default_label = "\\cite{}"
    for _, f in ipairs(LATEX_FORMATS) do
      if f.cmd == cfg.default_latex_format then
        default_label = f.label
        break
      end
    end

    local options = {}
    options[#options + 1] = { cmd = nil, label = "default (" .. default_label .. ")" }
    for _, f in ipairs(LATEX_FORMATS) do
      options[#options + 1] = { cmd = f.cmd, label = f.label }
    end

    local ctx = require("citeref.util").save_context()
    vim.ui.select(options, {
      prompt = "LaTeX format: ",
      format_item = function(item)
        return item.label
      end,
    }, function(choice)
      local cmd = choice and choice.cmd or nil
      registry.call("pick_citation", "latex", entries, ctx, cmd)
    end)
  elseif insert_mode() then
    registry.call("show", "citation", "latex")
  else
    vim.notify(
      "citeref: normal-mode cite requires a picker backend (fzf, telescope, snacks, or minipick).",
      vim.log.levels.WARN
    )
  end
end

function M.cite_myst()
  if is_picker() then
    local entries = parse.load_entries()
    if #entries == 0 then
      return
    end

    local cfg = require("citeref.config").get()
    local MYST_FORMATS = require("citeref.myst_formats")

    local default_label = "{cite:p}"
    for _, f in ipairs(MYST_FORMATS) do
      if f.cmd == cfg.default_myst_format then
        default_label = f.label
        break
      end
    end

    local options = {}
    options[#options + 1] = { cmd = nil, label = "default (" .. default_label .. ")" }
    for _, f in ipairs(MYST_FORMATS) do
      options[#options + 1] = { cmd = f.cmd, label = f.label }
    end

    local ctx = require("citeref.util").save_context()
    vim.ui.select(options, {
      prompt = "MyST format: ",
      format_item = function(item)
        return item.label
      end,
    }, function(choice)
      local cmd = choice and choice.cmd or nil
      registry.call("pick_citation", "myst", entries, ctx, cmd)
    end)
  else
    vim.notify(
      "citeref: myst cite requires a picker backend (fzf, telescope, snacks, or minipick).",
      vim.log.levels.WARN
    )
  end
end

function M.cite_replace()
  if not is_picker() then
    vim.notify(
      "citeref: cite_replace requires a picker backend (fzf, telescope, snacks, or minipick).",
      vim.log.levels.WARN
    )
    return
  end
  local info = parse.citation_under_cursor()
  if not info then
    vim.notify("citeref: cursor is not on a citation.", vim.log.levels.WARN)
    return
  end
  local entries = parse.load_entries()
  if #entries == 0 then
    return
  end
  registry.call("replace", entries, info)
end

function M.crossref_figure()
  if is_picker() then
    local labels = parse.load_labels("fig")
    if #labels == 0 then
      vim.notify("citeref: no figure labels found.", vim.log.levels.WARN)
      return
    end
    -- Capture filetype now (before picker opens and focus changes)
    local bufnr = vim.api.nvim_get_current_buf()
    local ctx = require("citeref.util").save_context()
    ctx.bufnr = bufnr
    registry.call("pick_crossref", "fig", labels, ctx)
  elseif insert_mode() then
    registry.call("show", "crossref_fig")
  else
    vim.notify(
      "citeref: normal-mode crossref requires a picker backend (fzf, telescope, snacks, or minipick).",
      vim.log.levels.WARN
    )
  end
end

function M.crossref_table()
  if is_picker() then
    local labels = parse.load_labels("tab")
    if #labels == 0 then
      vim.notify("citeref: no table labels found.", vim.log.levels.WARN)
      return
    end
    local bufnr = vim.api.nvim_get_current_buf()
    local ctx = require("citeref.util").save_context()
    ctx.bufnr = bufnr
    registry.call("pick_crossref", "tab", labels, ctx)
  elseif insert_mode() then
    registry.call("show", "crossref_tab")
  else
    vim.notify(
      "citeref: normal-mode crossref requires a picker backend (fzf, telescope, snacks, or minipick).",
      vim.log.levels.WARN
    )
  end
end

-- ─────────────────────────────────────────────────────────────
-- Register a custom backend
-- ─────────────────────────────────────────────────────────────

--- Register a third-party or user-defined backend.
--- The backend table should implement any of:
---   pick_citation(format, entries, ctx, cmd?)
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
    if km.lhs == lhs then
      return
    end
  end
  vim.keymap.set(mode, lhs, rhs, { buffer = true, silent = true, desc = desc })
end

local function set_keymaps()
  local km = require("citeref.config").get().keymaps
  if not km.enabled then
    return
  end
  if km.cite_markdown_i then
    map("i", km.cite_markdown_i, M.cite_markdown, "citeref: insert citation (markdown)")
  end
  if km.cite_markdown_n then
    map("n", km.cite_markdown_n, M.cite_markdown, "citeref: insert citation (markdown)")
  end
  if km.cite_latex_i then
    map("i", km.cite_latex_i, M.cite_latex, "citeref: insert citation (LaTeX)")
  end
  if km.cite_latex_n then
    map("n", km.cite_latex_n, M.cite_latex, "citeref: insert citation (LaTeX)")
  end
  if km.cite_myst_i then
    map("i", km.cite_myst_i, M.cite_myst, "citeref: insert citation (MyST)")
  end
  if km.cite_myst_n then
    map("n", km.cite_myst_n, M.cite_myst, "citeref: insert citation (MyST)")
  end
  if km.cite_replace_n then
    map("n", km.cite_replace_n, M.cite_replace, "citeref: replace citation under cursor")
  end
  if km.crossref_figure_i then
    map("i", km.crossref_figure_i, M.crossref_figure, "citeref: insert figure crossref")
  end
  if km.crossref_figure_n then
    map("n", km.crossref_figure_n, M.crossref_figure, "citeref: insert figure crossref")
  end
  if km.crossref_table_i then
    map("i", km.crossref_table_i, M.crossref_table, "citeref: insert table crossref")
  end
  if km.crossref_table_n then
    map("n", km.crossref_table_n, M.crossref_table, "citeref: insert table crossref")
  end
end

-- ─────────────────────────────────────────────────────────────
-- Attach
-- ─────────────────────────────────────────────────────────────

local attached = {}

function M.attach()
  local buf = vim.api.nvim_get_current_buf()
  if attached[buf] then
    return
  end
  attached[buf] = true
  set_keymaps()
  vim.api.nvim_create_autocmd("BufDelete", {
    buffer = buf,
    once = true,
    callback = function()
      attached[buf] = nil
    end,
  })
end

-- ─────────────────────────────────────────────────────────────
-- On-the-fly format overrides
-- ─────────────────────────────────────────────────────────────

--- Set the default LaTeX cite format for the current session.
--- Valid values: see citeref.config.valid_latex_formats
---@param format string
function M.set_latex_format(format)
  local config = require("citeref.config")
  if not config.valid_latex_formats[format] then
    local keys = vim.tbl_keys(config.valid_latex_formats)
    table.sort(keys)
    vim.notify(
      "citeref: invalid latex format '"
        .. tostring(format)
        .. "'.\n"
        .. "  Valid: " .. table.concat(keys, ", "),
      vim.log.levels.WARN
    )
    return
  end
  config.options = config.options or vim.deepcopy(config.defaults)
  config.options.default_latex_format = format
  vim.notify("citeref: latex format set to '" .. format .. "'.", vim.log.levels.INFO)
end

--- Set the default MyST cite role for the current session.
--- Valid values: see citeref.config.valid_myst_formats
---@param format string
function M.set_myst_format(format)
  local config = require("citeref.config")
  if not config.valid_myst_formats[format] then
    local keys = vim.tbl_keys(config.valid_myst_formats)
    table.sort(keys)
    vim.notify(
      "citeref: invalid myst format '"
        .. tostring(format)
        .. "'.\n"
        .. "  Valid: " .. table.concat(keys, ", "),
      vim.log.levels.WARN
    )
    return
  end
  config.options = config.options or vim.deepcopy(config.defaults)
  config.options.default_myst_format = format
  vim.notify("citeref: myst format set to '" .. format .. "'.", vim.log.levels.INFO)
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

  local cfg = require("citeref.config").get()
  local ft_set = {}
  for _, ft in ipairs(cfg.filetypes) do
    ft_set[ft] = true
  end
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
  print(
    string.format(
      "citeref  buf=%d  ft=%q  attached=%s  backend=%s",
      buf,
      vim.bo[buf].filetype,
      tostring(attached[buf] == true),
      tostring(cfg.backend)
    )
  )
  for _, mode in ipairs({ "n", "i" }) do
    for _, k in ipairs(vim.api.nvim_buf_get_keymap(buf, mode)) do
      if k.desc and k.desc:match("^citeref:") then
        print(string.format("  %s  %s", mode, k.lhs))
      end
    end
  end
end

return M
