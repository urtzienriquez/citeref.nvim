--- plugin/citeref.lua
---
--- This file is sourced automatically by Neovim at startup because it lives in
--- the plugin/ directory.  It MUST stay lightweight: all it does is register a
--- FileType autocommand.  The heavy modules (citation, crossref, fzf-lua …) are
--- required only when a matching buffer is opened – that IS the lazy-loading.
---
--- Users do NOT need to call require("citeref").setup() for the plugin to work.
--- setup() exists only to override defaults.

-- Guard: only register once even if rtp contains the plugin twice.
if vim.g.loaded_citeref then return end
vim.g.loaded_citeref = true

-- vim.schedule defers registration until after the plugin manager (e.g.
-- lazy.nvim) has finished setting up the runtimepath.  Without this, dev
-- plugins whose lua/ directory is added to rtp late would fail to require
-- their own modules if any event fires during startup before rtp is ready.
vim.schedule(function()
  vim.api.nvim_create_autocmd("FileType", {
    -- pattern = "*" so the filetype list can be changed by setup() at any time
    -- without having to re-register the autocmd.
    pattern  = "*",
    group    = vim.api.nvim_create_augroup("citeref", { clear = true }),
    callback = function(ev)
      -- All requires happen here, inside the callback, never at file-source time.
      local ok_cfg, cfg_mod = pcall(require, "citeref.config")
      if not ok_cfg then return end  -- rtp not ready yet (shouldn't happen after schedule)

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

  -- Re-trigger FileType for any buffers that were opened before our autocmd
  -- was registered (e.g. the first file opened by `nvim somefile.md`).
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      local ft = vim.bo[buf].filetype
      if ft and ft ~= "" then
        vim.api.nvim_exec_autocmds("FileType", { buffer = buf, modeline = false })
      end
    end
  end
end)
