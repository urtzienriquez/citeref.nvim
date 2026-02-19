--- citeref.nvim
--- A citation and cross-reference picker for Neovim.
---
--- fzf-lua is used when available; otherwise keymaps fall back to
--- forcing the completion menu open via blink.cmp or nvim-cmp.
---
--- Optional setup() – sane defaults apply without calling it:
---
---   require("citeref").setup({
---     filetypes  = { "markdown", "rmd", "quarto", "rnoweb", "pandoc", "tex", "latex" },
---     bib_files  = { "~/Documents/zotero.bib" },
---     keymaps    = {
---       enabled           = true,
---       cite_markdown_i   = "<C-a>m",
---       cite_markdown_n   = "<leader>am",
---       cite_latex_i      = "<C-a>l",
---       cite_latex_n      = "<leader>al",
---       cite_replace_n    = "<leader>ar",
---       crossref_figure_i = "<C-a>f",
---       crossref_figure_n = "<leader>af",
---       crossref_table_i  = "<C-a>t",
---       crossref_table_n  = "<leader>at",
---     },
---   })

local M = {}

-- ─────────────────────────────────────────────────────────────
-- Backend detection (fzf-lua preferred, completion fallback)
-- ─────────────────────────────────────────────────────────────

local _has_fzf = nil

local function has_fzf()
  if _has_fzf == nil then
    _has_fzf = pcall(require, "fzf-lua")
  end
  return _has_fzf
end

-- ─────────────────────────────────────────────────────────────
-- Public API
-- Each function picks the right backend at call time.
-- ─────────────────────────────────────────────────────────────

function M.cite_markdown()
  if has_fzf() then
    require("citeref.citation").pick_markdown()
  else
    local mode = vim.api.nvim_get_mode().mode
    if mode:find("i") then
      require("citeref.completion").show_citations_markdown()
    else
      vim.notify("citeref: cite_markdown in normal mode requires fzf-lua", vim.log.levels.WARN)
    end
  end
end

function M.cite_latex()
  if has_fzf() then
    require("citeref.citation").pick_latex()
  else
    local mode = vim.api.nvim_get_mode().mode
    if mode:find("i") then
      require("citeref.completion").show_citations_latex()
    else
      vim.notify("citeref: cite_latex in normal mode requires fzf-lua", vim.log.levels.WARN)
    end
  end
end

function M.cite_replace()
  if has_fzf() then
    require("citeref.citation").replace()
  else
    vim.notify("citeref: cite_replace requires fzf-lua", vim.log.levels.WARN)
  end
end

function M.crossref_figure()
  if has_fzf() then
    require("citeref.crossref").pick_figure()
  else
    local mode = vim.api.nvim_get_mode().mode
    if mode:find("i") then
      require("citeref.completion").show_crossref_fig()
    else
      vim.notify("citeref: crossref_figure in normal mode requires fzf-lua", vim.log.levels.WARN)
    end
  end
end

function M.crossref_table()
  if has_fzf() then
    require("citeref.crossref").pick_table()
  else
    local mode = vim.api.nvim_get_mode().mode
    if mode:find("i") then
      require("citeref.completion").show_crossref_tab()
    else
      vim.notify("citeref: crossref_table in normal mode requires fzf-lua", vim.log.levels.WARN)
    end
  end
end

-- ─────────────────────────────────────────────────────────────
-- Keymap helpers
-- ─────────────────────────────────────────────────────────────

local function set_keymap_if_free(modes, lhs, rhs, desc)
  if type(modes) == "string" then modes = { modes } end
  for _, mode in ipairs(modes) do
    local existing = vim.api.nvim_buf_get_keymap(0, mode)
    local occupied = false
    for _, km in ipairs(existing) do
      if km.lhs == lhs then occupied = true ; break end
    end
    if not occupied then
      vim.keymap.set(mode, lhs, rhs, { buffer = true, silent = true, desc = desc })
    end
  end
end

local function set_keymaps()
  local cfg = require("citeref.config").get()
  local km  = cfg.keymaps
  if not km.enabled then return end

  local map = set_keymap_if_free

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

local attached_bufs  = {}
local _backend_checked = false
local _backend_ok      = false

--- Returns true if at least one usable backend is available (cached after first call).
local function has_any_backend()
  if _backend_checked then return _backend_ok end
  _backend_checked = true
  _backend_ok = pcall(require, "fzf-lua")
    or pcall(require, "blink.cmp")
    or pcall(require, "cmp")
  return _backend_ok
end

function M.attach()
  local buf = vim.api.nvim_get_current_buf()
  if attached_bufs[buf] then return end

  if not has_any_backend() then
    vim.notify(
      "citeref: no backend found. Install fzf-lua, blink.cmp, or nvim-cmp.",
      vim.log.levels.WARN
    )
    return  -- don't attach, don't set keymaps, don't try again for this buf
  end

  attached_bufs[buf] = true
  set_keymaps()
  require("citeref.completion").register()

  vim.api.nvim_create_autocmd("BufDelete", {
    buffer   = buf,
    once     = true,
    callback = function() attached_bufs[buf] = nil end,
  })
end

-- ─────────────────────────────────────────────────────────────
-- Debug
-- ─────────────────────────────────────────────────────────────

function M.debug()
  local buf = vim.api.nvim_get_current_buf()
  local ft  = vim.bo[buf].filetype
  local cfg = require("citeref.config").get()

  print(string.format("citeref debug — buf=%d  ft=%q  attached=%s",
    buf, ft, tostring(attached_bufs[buf] == true)))
  print("Backend: " .. (has_fzf() and "fzf-lua" or (has_any_backend() and "completion (blink/cmp)" or "NONE – plugin inactive")))
  print("Active filetypes: " .. table.concat(cfg.filetypes, ", "))

  local found = {}
  for _, mode in ipairs({ "n", "i" }) do
    for _, k in ipairs(vim.api.nvim_buf_get_keymap(buf, mode)) do
      if k.desc and k.desc:match("^citeref:") then
        found[#found+1] = string.format("  %s  %s  →  %s", mode, k.lhs, k.desc)
      end
    end
  end
  if #found == 0 then
    print("No citeref keymaps found in this buffer.")
  else
    print("citeref keymaps:")
    for _, l in ipairs(found) do print(l) end
  end
end

-- ─────────────────────────────────────────────────────────────
-- setup()
-- ─────────────────────────────────────────────────────────────

function M.setup(opts)
  require("citeref.config").set(opts)

  local cfg    = require("citeref.config").get()
  local ft_set = {}
  for _, ft in ipairs(cfg.filetypes) do ft_set[ft] = true end

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      local ft = vim.bo[buf].filetype
      if ft_set[ft] and not attached_bufs[buf] then
        local cur_win = vim.api.nvim_get_current_win()
        local wins    = vim.fn.win_findbuf(buf)
        if #wins > 0 then
          vim.api.nvim_set_current_win(wins[1])
          M.attach()
          vim.api.nvim_set_current_win(cur_win)
        end
      end
    end
  end
end

return M
