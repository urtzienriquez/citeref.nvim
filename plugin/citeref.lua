--- plugin/citeref.lua
---
--- Sourced at startup by Neovim. Kept intentionally minimal — just registers
--- the FileType autocommand that attaches citeref to matching buffers.
---
--- When used with lazy.nvim, pair this with an ft = {...} trigger in your spec
--- so that the lua/ modules are not loaded until a matching file is opened:
---
---   { dir = "~/path/to/citeref.nvim",
---     ft  = { "markdown", "rmd", "quarto", "rnoweb", "pandoc", "tex", "latex" },
---     dependencies = { "ibhagwan/fzf-lua" } }
---
--- The ft trigger makes lazy.nvim fire a FileType event for the first matching
--- buffer, which our autocommand below then picks up — no re-trigger needed.

if vim.g.loaded_citeref then return end
vim.g.loaded_citeref = true

vim.schedule(function()
  vim.api.nvim_create_autocmd("FileType", {
    pattern  = "*",
    group    = vim.api.nvim_create_augroup("citeref", { clear = true }),
    callback = function(ev)
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
end)
