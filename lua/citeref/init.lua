--- citeref.nvim
--- A citation and cross-reference picker for Neovim.
---
--- Usage (optional – the plugin works without calling setup):
---
---   require("citeref").setup({
---     filetypes  = { "markdown", "quarto", "tex" },
---     bib_files  = { "~/my-library.bib" },
---     keymaps    = {
---       enabled           = true,
---       cite_markdown_i   = "<C-a>m",     -- insert mode
---       cite_markdown_n   = "<leader>am", -- normal mode
---       cite_latex_i      = "<C-a>l",
---       cite_latex_n      = "<leader>al",
---       cite_replace_n    = "<leader>ar", -- normal only
---       crossref_figure_i = "<C-a>f",
---       crossref_figure_n = "<leader>af",
---       crossref_table_i  = "<C-a>t",
---       crossref_table_n  = "<leader>at",
---       -- set any key to false to disable just that mapping
---     },
---   })

local M = {}

-- ─────────────────────────────────────────────────────────────
-- Public API – lazily loaded modules
-- ─────────────────────────────────────────────────────────────

--- Insert a markdown-style citation (@key).
function M.cite_markdown()   require("citeref.citation").pick_markdown() end

--- Insert a LaTeX-style citation (\cite{key}).
function M.cite_latex()      require("citeref.citation").pick_latex()    end

--- Replace the citation key under the cursor.
function M.cite_replace()    require("citeref.citation").replace()       end

--- Insert a figure cross-reference (\@ref(fig:label)).
function M.crossref_figure() require("citeref.crossref").pick_figure()   end

--- Insert a table cross-reference (\@ref(tab:label)).
function M.crossref_table()  require("citeref.crossref").pick_table()    end

-- ─────────────────────────────────────────────────────────────
-- Keymap helpers
-- ─────────────────────────────────────────────────────────────

--- Set a buffer-local keymap only when the user hasn't already mapped the key
--- in this buffer (respects user overrides set before or after attach).
---@param modes string|string[]
---@param lhs string
---@param rhs function|string
---@param desc string
local function set_keymap_if_free(modes, lhs, rhs, desc)
  if type(modes) == "string" then modes = { modes } end
  for _, mode in ipairs(modes) do
    -- Check whether the user has mapped this key in the buffer already.
    -- nvim_buf_get_keymap returns an empty table when nothing is mapped.
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

--- Install buffer-local keymaps according to the resolved config.
--- Mirrors exactly the pattern from keymaps.lua:
---   insert-mode  <C-a>X  →  open picker, insert, stay in insert
---   normal-mode  <leader>aX → open picker, insert, stay in normal
local function set_keymaps()
  local cfg = require("citeref.config").get()
  local km  = cfg.keymaps

  if not km.enabled then return end

  local map = set_keymap_if_free

  -- Citations – markdown (@key)
  if km.cite_markdown_i then
    map("i", km.cite_markdown_i, M.cite_markdown, "citeref: insert citation (markdown)")
  end
  if km.cite_markdown_n then
    map("n", km.cite_markdown_n, M.cite_markdown, "citeref: insert citation (markdown)")
  end

  -- Citations – LaTeX (\cite{key})
  if km.cite_latex_i then
    map("i", km.cite_latex_i, M.cite_latex, "citeref: insert citation (LaTeX)")
  end
  if km.cite_latex_n then
    map("n", km.cite_latex_n, M.cite_latex, "citeref: insert citation (LaTeX)")
  end

  -- Replace citation under cursor (normal only – cursor must be on a key)
  if km.cite_replace_n then
    map("n", km.cite_replace_n, M.cite_replace, "citeref: replace citation under cursor")
  end

  -- Cross-references – figure
  if km.crossref_figure_i then
    map("i", km.crossref_figure_i, M.crossref_figure, "citeref: insert figure crossref")
  end
  if km.crossref_figure_n then
    map("n", km.crossref_figure_n, M.crossref_figure, "citeref: insert figure crossref")
  end

  -- Cross-references – table
  if km.crossref_table_i then
    map("i", km.crossref_table_i, M.crossref_table, "citeref: insert table crossref")
  end
  if km.crossref_table_n then
    map("n", km.crossref_table_n, M.crossref_table, "citeref: insert table crossref")
  end
end

-- ─────────────────────────────────────────────────────────────
-- Attach – called per buffer when the filetype matches
-- ─────────────────────────────────────────────────────────────

local attached_bufs = {}

--- Attach citeref to the current buffer: install keymaps and mark it attached.
--- Idempotent – safe to call multiple times on the same buffer.
function M.attach()
  local buf = vim.api.nvim_get_current_buf()
  if attached_bufs[buf] then return end
  attached_bufs[buf] = true

  set_keymaps()

  -- Clean up when the buffer is deleted
  vim.api.nvim_create_autocmd("BufDelete", {
    buffer   = buf,
    once     = true,
    callback = function() attached_bufs[buf] = nil end,
  })
end

--- Print attachment and keymap status for the current buffer. Useful for debugging.
function M.debug()
  local buf = vim.api.nvim_get_current_buf()
  local ft  = vim.bo[buf].filetype
  local cfg = require("citeref.config").get()

  print(string.format("citeref debug — buf=%d  ft=%q  attached=%s",
    buf, ft, tostring(attached_bufs[buf] == true)))
  print("Active filetypes: " .. table.concat(cfg.filetypes, ", "))

  local km = vim.api.nvim_buf_get_keymap(buf, "n")
  local found = {}
  for _, k in ipairs(km) do
    if k.desc and k.desc:match("^citeref:") then
      found[#found+1] = string.format("  n  %s  →  %s", k.lhs, k.desc)
    end
  end
  local kmi = vim.api.nvim_buf_get_keymap(buf, "i")
  for _, k in ipairs(kmi) do
    if k.desc and k.desc:match("^citeref:") then
      found[#found+1] = string.format("  i  %s  →  %s", k.lhs, k.desc)
    end
  end
  if #found == 0 then
    print("No citeref keymaps found in this buffer.")
  else
    print("citeref keymaps in this buffer:")
    for _, l in ipairs(found) do print(l) end
  end
end

-- ─────────────────────────────────────────────────────────────
-- setup() – optional user configuration
-- ─────────────────────────────────────────────────────────────

--- Configure citeref. All options are optional; sane defaults apply without
--- calling this function at all.
---@param opts? table
function M.setup(opts)
  require("citeref.config").set(opts)

  -- If the user calls setup() after some buffers have already attached
  -- (e.g. fast startup), re-trigger attachment logic for currently open
  -- relevant buffers.
  local cfg       = require("citeref.config").get()
  local ft_set    = {}
  for _, ft in ipairs(cfg.filetypes) do ft_set[ft] = true end

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      local ft = vim.bo[buf].filetype
      if ft_set[ft] and not attached_bufs[buf] then
        -- Switch context, attach, restore
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
