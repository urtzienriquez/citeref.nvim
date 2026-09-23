--- citeref.nvim – shared LaTeX citation format definitions
--- Backends import this so the list is defined in one place.

---@class CiterefLatexFormat
---@field cmd   string  e.g. "citep"
---@field label string  e.g. "\\citep{}"

---@type CiterefLatexFormat[]
local M = {
  { cmd = "cite", label = "\\cite{}" },
  { cmd = "citep", label = "\\citep{}" },
  { cmd = "citet", label = "\\citet{}" },
  { cmd = "citeauthor", label = "\\citeauthor{}" },
  { cmd = "citeyear", label = "\\citeyear{}" },
  { cmd = "citealt", label = "\\citealt{}" },
  { cmd = "textcite", label = "\\textcite{}" },
  { cmd = "parencite", label = "\\parencite{}" },
  { cmd = "footcite", label = "\\footcite{}" },
  { cmd = "autocite", label = "\\autocite{}" },
  { cmd = "nocite", label = "\\nocite{}" },
}

---@param keys string[]
---@param cmd string  e.g. "citep"
---@return string
function M.format(keys, cmd)
  return "\\" .. cmd .. "{" .. table.concat(keys, ", ") .. "}"
end

---@param inner string  text between the opening brace and the insertion point
---@return string[]
local function split_keys(inner)
  local keys = {}
  for k in inner:gmatch("[^,]+") do
    k = vim.trim(k)
    if k ~= "" then
      keys[#keys + 1] = k
    end
  end
  return keys
end

---@class CiterefLatexCite
---@field cmd       string        e.g. "citep"
---@field start_col integer       0-based column of the backslash
---@field open_col  integer       0-based column of the key-list "{"
---@field close_col integer|nil   0-based column of the matching "}" (nil if unclosed)
---@field keys      string[]      keys already present

--- Find the LaTeX cite command (\cite, \citep, \parencite[p.~5]{...}, …)
--- enclosing the 0-based cursor column `col` on `line`.
--- In normal mode the cursor may be anywhere from the backslash to the closing
--- brace; in insert mode (cursor between chars) it must be past the backslash.
---@param line string
---@param col integer
---@param is_insert? boolean
---@return CiterefLatexCite|nil
function M.enclosing_cite(line, col, is_insert)
  local pos = 1
  while true do
    local s, e, cmd = line:find("\\(%a+)", pos)
    if not s then
      return nil
    end
    pos = e + 1
    if cmd:find("cite", 1, true) then
      -- Skip whitespace and optional [...] arguments
      local p = e + 1
      while true do
        local ws = line:match("^%s*", p)
        p = p + #ws
        if line:sub(p, p) == "[" then
          local close = line:find("]", p, true)
          if not close then
            break
          end
          p = close + 1
        else
          break
        end
      end
      if line:sub(p, p) == "{" then
        local open_col = p - 1
        local close = line:find("[{}]", p + 1)
        if close and line:sub(close, close) == "{" then
          close = nil -- nested brace: not a plain key list
        else
          local close_col = close and (close - 1) or nil
          local lo = is_insert and s or (s - 1)
          local hi = close_col or math.huge
          if col >= lo and col <= hi then
            local inner = line:sub(p + 1, close and (close - 1) or #line)
            return {
              cmd = cmd,
              start_col = s - 1,
              open_col = open_col,
              close_col = close_col,
              keys = split_keys(inner),
            }
          end
          if close then
            pos = close + 1
          end
        end
      end
    end
  end
end

--- Build the text to insert (at the end of `inner`) that appends `new_keys`
--- to an existing key list, skipping keys already present.
---@param inner string     current text between "{" and the insertion point
---@param new_keys string[]
---@return string|nil      nil when every key is already cited
function M.append_keys(inner, new_keys)
  local seen = {}
  for _, k in ipairs(split_keys(inner)) do
    seen[k] = true
  end
  local add = {}
  for _, k in ipairs(new_keys) do
    if not seen[k] then
      seen[k] = true
      add[#add + 1] = k
    end
  end
  if #add == 0 then
    return nil
  end
  local text = table.concat(add, ", ")
  local trimmed = inner:gsub("%s+$", "")
  if trimmed == "" then
    return text
  elseif trimmed:sub(-1) == "," then
    return (trimmed == inner) and (" " .. text) or text
  end
  return ", " .. text
end

return M
