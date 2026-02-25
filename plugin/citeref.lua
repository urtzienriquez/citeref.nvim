--- plugin/citeref.lua
if vim.g.loaded_citeref then
  return
end
vim.g.loaded_citeref = true

vim.schedule(function()
  local group = vim.api.nvim_create_augroup("citeref", { clear = true })

  vim.api.nvim_create_autocmd("FileType", {
    pattern = "*",
    group = group,
    callback = function(ev)
      local ok_cfg, cfg_mod = pcall(require, "citeref.config")
      if not ok_cfg then
        return
      end

      local cfg = cfg_mod.get()
      local ft_set = {}
      for _, ft in ipairs(cfg.filetypes) do
        ft_set[ft] = true
      end
      if not ft_set[ev.match] then
        return
      end

      local ok, err = pcall(require("citeref").attach)
      if not ok then
        vim.notify("citeref: attach error – " .. tostring(err), vim.log.levels.ERROR)
      end
    end,
  })

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      local ft = vim.bo[buf].filetype
      if ft and ft ~= "" then
        vim.api.nvim_exec_autocmds("FileType", {
          group = group,
          buffer = buf,
          data = { match = ft },
          modeline = false,
        })
      end
    end
  end
end)
