--- citeref.nvim – cross-reference picking and insertion
local util = require("citeref.util")

local M = {}

-- ─────────────────────────────────────────────────────────────
-- Chunk parsing
-- ─────────────────────────────────────────────────────────────

---@class CiterefChunk
---@field label      string        chunk label (for \@ref insertion), or "" if unnamed
---@field display    string        unique string shown in the picker
---@field line       integer       1-indexed line number of the ```{r...} header
---@field file       string        absolute path of the source file
---@field is_current boolean       true when the chunk is in the current buffer
---@field header     string        the raw header line (shown in preview)

--- Extract the label from a chunk opening line.
--- Handles all common forms:
---   ```{r}                   → unnamed ("")
---   ```{r,  echo=FALSE}      → unnamed ("")
---   ```{r label}             → "label"
---   ```{r label, echo=FALSE} → "label"
---   ```{r fig-label}         → "fig-label"   (Quarto style)
---@param line string
---@return string|nil label   nil = not a chunk header; "" = unnamed chunk
---@return string|nil header  the raw line (only when label is non-nil)
local function parse_chunk_header(line)
  if not line:match("^```{r") then return nil end

  -- ```{r}  or  ```{r }
  if line:match("^```{r%s*}") then
    return "", line
  end

  -- ```{r,  ...}  — options only, no label
  if line:match("^```{r%s*,") then
    return "", line
  end

  -- ```{r LABEL}  or  ```{r LABEL, ...}
  local label = line:match("^```{r%s+([^%s,}]+)")
  if label then
    return label, line
  end

  -- Any other ```{r...} variant → unnamed
  return "", line
end

---@param bufnr integer
---@return CiterefChunk[]
local function parse_chunks_from_buf(bufnr)
  local chunks        = {}
  local lines         = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local path          = vim.api.nvim_buf_get_name(bufnr)
  local fname         = vim.fn.fnamemodify(path, ":t")
  local unnamed_count = 0

  for i, line in ipairs(lines) do
    local label, header = parse_chunk_header(line)
    if label ~= nil then
      local display
      if label == "" then
        unnamed_count = unnamed_count + 1
        display = string.format("[unnamed #%d] line %d  (%s)", unnamed_count, i, fname)
      else
        display = string.format("%s  line %d  (%s)", label, i, fname)
      end
      chunks[#chunks+1] = {
        label      = label,
        display    = display,
        line       = i,
        file       = path,
        is_current = true,
        header     = header,
      }
    end
  end
  return chunks
end

---@param filepath string
---@return CiterefChunk[]
local function parse_chunks_from_file(filepath)
  local chunks        = {}
  local file          = io.open(filepath, "r")
  if not file then return chunks end

  local fname         = vim.fn.fnamemodify(filepath, ":t")
  local i             = 0
  local unnamed_count = 0

  for line in file:lines() do
    i = i + 1
    local label, header = parse_chunk_header(line)
    if label ~= nil then
      local display
      if label == "" then
        unnamed_count = unnamed_count + 1
        display = string.format("[unnamed #%d] line %d  (%s)", unnamed_count, i, fname)
      else
        display = string.format("%s  line %d  (%s)", label, i, fname)
      end
      chunks[#chunks+1] = {
        label      = label,
        display    = display,
        line       = i,
        file       = filepath,
        is_current = false,
        header     = header,
      }
    end
  end
  file:close()
  return chunks
end

---@return CiterefChunk[]
function M.all_chunks()
  local bufnr    = vim.api.nvim_get_current_buf()
  local cur_file = vim.api.nvim_buf_get_name(bufnr)
  local cur_dir  = vim.fn.fnamemodify(cur_file, ":h")

  local result    = parse_chunks_from_buf(bufnr)
  local rmd_files = vim.fn.globpath(cur_dir, "*.{rmd,Rmd,qmd,Qmd}", false, true)
  for _, f in ipairs(rmd_files) do
    if f ~= cur_file then
      vim.list_extend(result, parse_chunks_from_file(f))
    end
  end

  return result
end

-- ─────────────────────────────────────────────────────────────
-- fzf-lua previewer – scrolls the source file to the chunk line
-- ─────────────────────────────────────────────────────────────

---@param lookup table<string, CiterefChunk>
local function make_previewer(lookup)
  local Previewer = require("fzf-lua.previewer.builtin")
  local P         = Previewer.buffer_or_file:extend()

  function P:new(o, opts, fzf_win)
    P.super.new(self, o, opts, fzf_win)
    setmetatable(self, P)
    return self
  end

  function P:parse_entry(entry_str)
    local chunk = lookup[entry_str]
    if chunk and chunk.file and chunk.file ~= "" then
      return { path = chunk.file, line = chunk.line, col = 1 }
    end
    return { path = "" }
  end

  return P
end

-- ─────────────────────────────────────────────────────────────
-- Picker
-- ─────────────────────────────────────────────────────────────

---@param ref_type "fig"|"tab"
function M.pick(ref_type)
  local chunks = M.all_chunks()
  if #chunks == 0 then
    vim.notify("citeref: no code chunks found", vim.log.levels.WARN)
    return
  end

  local ctx          = util.save_context()
  local lookup       = {}
  local display_list = {}

  for _, c in ipairs(chunks) do
    lookup[c.display]              = c
    display_list[#display_list+1]  = c.display
  end

  local title = ref_type == "fig" and " Figure Crossref " or " Table Crossref "

  require("fzf-lua").fzf_exec(function(cb)
    for _, d in ipairs(display_list) do cb(d) end
    cb()
  end, {
    prompt    = "chunk> ",
    previewer = make_previewer(lookup),
    winopts   = {
      title   = title,
      preview = { layout = "vertical", vertical = "right:65%", wrap = "wrap" },
    },
    actions = {
      ["default"] = function(selected)
        if #selected == 0 then return end
        local chunk = lookup[selected[1]]
        if not chunk then return end

        if chunk.label == "" then
          vim.defer_fn(function()
            vim.notify(
              "citeref: chunk has no label – add a label to use it in a cross-reference",
              vim.log.levels.WARN
            )
          end, 100)
          return
        end

        local crossref = string.format("\\@ref(%s:%s)", ref_type, chunk.label)
        util.insert_at_context(ctx, crossref)
        vim.defer_fn(function()
          vim.notify("citeref: inserted " .. crossref, vim.log.levels.INFO)
        end, 100)
      end,
    },
  })
end

function M.pick_figure() M.pick("fig") end
function M.pick_table()  M.pick("tab") end

return M
