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

--- Join citation keys the way citeref writes them: comma-separated, no spaces.
---@param keys string[]
---@return string
function M.join(keys)
  return table.concat(keys, ",")
end

---@param keys string[]
---@param cmd string  e.g. "citep"
---@return string
function M.format(keys, cmd)
  return "\\" .. cmd .. "{" .. M.join(keys) .. "}"
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

--- Append `new_keys` to `existing`, skipping keys already present.
---@param existing string[]
---@param new_keys string[]
---@return string[]|nil  nil when every key is already cited
function M.merge_keys(existing, new_keys)
  local out = vim.deepcopy(existing)
  local seen = {}
  for _, k in ipairs(out) do
    seen[k] = true
  end
  local added = false
  for _, k in ipairs(new_keys) do
    if not seen[k] then
      seen[k] = true
      out[#out + 1] = k
      added = true
    end
  end
  return added and out or nil
end

--- Replace `old_key` with `new_key`, dropping `new_key` elsewhere in the
--- list so it isn't cited twice.
---@param keys string[]
---@param old_key string
---@param new_key string
---@return string[]
function M.replace_key(keys, old_key, new_key)
  local out = {}
  for _, k in ipairs(keys) do
    if k == old_key then
      out[#out + 1] = new_key
    elseif k ~= new_key then
      out[#out + 1] = k
    end
  end
  return out
end

return M
