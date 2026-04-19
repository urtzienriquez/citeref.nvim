--- citeref.nvim – shared MyST citation format definitions
--- Backends import this so the list is defined in one place.

---@class CiterefMystFormat
---@field cmd   string  e.g. "cite:p"
---@field label string  e.g. "{cite:p}"

---@type CiterefMystFormat[]
local M = {
  { cmd = "cite:p", label = "{cite:p}" },
  { cmd = "cite:t", label = "{cite:t}" },
}

---@param current_cmd string
---@return CiterefMystFormat
function M.next(current_cmd)
  for i, f in ipairs(M) do
    if f.cmd == current_cmd then
      return M[(i % #M) + 1]
    end
  end
  return M[1]
end

---@param keys string[]
---@param cmd string
---@param prefix? string
---@param suffix? string
---@return string
function M.format(keys, cmd, prefix, suffix)
  local body = table.concat(keys, "; ")
  if prefix and prefix ~= "" then
    body = "{" .. prefix .. "}" .. body
  end
  if suffix and suffix ~= "" then
    body = body .. "{" .. suffix .. "}"
  end
  return "{" .. cmd .. "}`" .. body .. "`"
end

---@param keys string[]
---@param old_key string
---@param new_key string
---@return string[]
function M.replace_key(keys, old_key, new_key)
  local out = vim.deepcopy(keys)
  for i, key in ipairs(out) do
    if key == old_key then
      out[i] = new_key
      return out
    end
  end
  out[#out + 1] = new_key
  return out
end

return M
