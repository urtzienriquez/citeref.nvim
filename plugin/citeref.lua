--- plugin/citeref.lua
---
--- Sourced at startup by Neovim. Registers the FileType autocommand that
--- attaches citeref to matching buffers.
---
--- lazy.nvim spec:
---   { "urtzienriquez/citeref.nvim",
---     ft  = { "markdown", "rmd", "quarto", "rnoweb", "pandoc", "tex", "latex" },
---     dependencies = { "ibhagwan/fzf-lua" },   -- optional
---     config = function()
---       require("citeref").setup({ bib_files = { "~/Documents/zotero.bib" } })
---     end }
---
--- setup() is OPTIONAL — the plugin works with sane defaults without it.

if vim.g.loaded_citeref then return end
vim.g.loaded_citeref = true

vim.schedule(function()
  local group = vim.api.nvim_create_augroup("citeref", { clear = true })

  vim.api.nvim_create_autocmd("FileType", {
    pattern  = "*",
    group    = group,
    callback = function(ev)
      -- config.get() always returns valid config (initialises defaults if
      -- setup() was never called), so the plugin works out-of-the-box.
      local ok_cfg, cfg_mod = pcall(require, "citeref.config")
      if not ok_cfg then return end

      local cfg    = cfg_mod.get()
      local ft_set = {}
      for _, ft in ipairs(cfg.filetypes) do ft_set[ft] = true end
      if not ft_set[ev.match] then return end

      local ok, err = pcall(require("citeref").attach)
      if not ok then
        vim.notify("citeref: attach error – " .. tostring(err), vim.log.levels.ERROR)
      end
    end,
  })

  -- Re-trigger FileType for any buffers already open when the autocmd registers.
  -- This covers the case where lazy.nvim fires the synthetic FileType event
  -- before vim.schedule runs (race between ft= trigger and schedule queue).
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      local ft = vim.bo[buf].filetype
      if ft and ft ~= "" then
        vim.api.nvim_exec_autocmds("FileType", {
          group   = group,
          buffer  = buf,
          data    = { match = ft },
          modeline = false,
        })
      end
    end
  end
end)
