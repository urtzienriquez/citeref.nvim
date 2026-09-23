--- citeref.nvim – shared utilities
local M = {}

function M.save_context()
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_get_current_buf()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local mode = vim.api.nvim_get_mode().mode
  return {
    win = win,
    buf = buf,
    row = row,
    col = col,
    was_insert_mode = mode:find("i") ~= nil,
  }
end

function M.set_cursor_after(buf, win, row, start_col, inserted_text)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local winid = (win and vim.api.nvim_win_is_valid(win)) and win or 0
  local target_col = start_col + #inserted_text
  pcall(vim.api.nvim_set_current_win, winid)
  pcall(vim.api.nvim_set_current_buf, buf)
  pcall(vim.api.nvim_win_set_cursor, winid, { row, target_col })
end

function M.reenter_insert(buf, win, row, col, inserted_len)
  local winid = (win and vim.api.nvim_win_is_valid(win)) and win or 0
  pcall(vim.api.nvim_set_current_win, winid)
  pcall(vim.api.nvim_set_current_buf, buf)

  local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""
  local target_col = col + inserted_len
  pcall(vim.api.nvim_win_set_cursor, winid, { row, target_col })

  local key = target_col >= #line and vim.api.nvim_replace_termcodes("a", true, false, true)
    or vim.api.nvim_replace_termcodes("i", true, false, true)

  vim.cmd("set eventignore+=InsertEnter")
  vim.api.nvim_feedkeys(key, "n", true)
  local restore = vim.api.nvim_replace_termcodes(
    "<C-o>:set eventignore-=InsertEnter<CR>",
    true, false, true
  )
  vim.api.nvim_feedkeys(restore, "n", true)
end

function M.insert_at_context(ctx, text)
  if not ctx or not text or text == "" then
    return
  end
  if not vim.api.nvim_buf_is_valid(ctx.buf) then
    return
  end
  if ctx.win and vim.api.nvim_win_is_valid(ctx.win) then
    pcall(vim.api.nvim_set_current_win, ctx.win)
  end
  pcall(vim.api.nvim_set_current_buf, ctx.buf)

  local row = ctx.row
  local col = ctx.was_insert_mode and ctx.col or ctx.col + 1

  local ok = pcall(function()
    vim.api.nvim_buf_set_text(ctx.buf, row - 1, col, row - 1, col, { text })
  end)
  if not ok then
    pcall(vim.api.nvim_put, { text }, "c", false, true)
    return
  end

  M.set_cursor_after(ctx.buf, ctx.win, row, col, text)
  if ctx.was_insert_mode then
    M.reenter_insert(ctx.buf, ctx.win, row, col, #text)
  end
end

--- Append keys to the LaTeX cite command enclosing the saved cursor position,
--- e.g. \citep{a, b} → \citep{a, b, c}.
---@param ctx table  context from save_context()
---@param keys string[]
---@return string|nil inserted text, nil if nothing was inserted
function M.append_to_latex_cite(ctx, keys)
  if not ctx or not vim.api.nvim_buf_is_valid(ctx.buf) then
    return nil
  end
  local LATEX_FORMATS = require("citeref.latex_formats")
  if ctx.win and vim.api.nvim_win_is_valid(ctx.win) then
    pcall(vim.api.nvim_set_current_win, ctx.win)
  end
  pcall(vim.api.nvim_set_current_buf, ctx.buf)

  local row = ctx.row
  local line = vim.api.nvim_buf_get_lines(ctx.buf, row - 1, row, false)[1] or ""
  local cite = LATEX_FORMATS.enclosing_cite(line, ctx.col, ctx.was_insert_mode)
  if not cite then
    return nil
  end

  local col = cite.close_col
  if not col then
    col = ctx.was_insert_mode and ctx.col or ctx.col + 1
    col = math.max(col, cite.open_col + 1)
  end
  local inner = line:sub(cite.open_col + 2, col)
  local text = LATEX_FORMATS.append_keys(inner, keys)
  if not text then
    vim.notify("citeref: already cited", vim.log.levels.INFO)
    return nil
  end
  local inserted = cite.close_col and text or (text .. "}")

  local ok = pcall(vim.api.nvim_buf_set_text, ctx.buf, row - 1, col, row - 1, col, { inserted })
  if not ok then
    return nil
  end

  -- Leave the cursor right after the appended keys (before "}")
  M.set_cursor_after(ctx.buf, ctx.win, row, col, text)
  if ctx.was_insert_mode then
    M.reenter_insert(ctx.buf, ctx.win, row, col, #text)
  end
  return text
end

return M
