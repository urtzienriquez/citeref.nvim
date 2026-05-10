--- citeref.nvim – shared parsers (bib entries + R/Quarto chunks)
--- No side effects, no vim.notify – callers handle errors.

local M = {}

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function parse_myst_body(body)
  local prefix, suffix = "", ""

  if body:sub(1, 1) == "{" then
    local close = body:find("}", 2, true)
    if close then
      prefix = body:sub(2, close - 1)
      body = body:sub(close + 1)
    end
  end

  local core, maybe_suffix = body:match("^(.-)%{(.-)%}$")
  if core and maybe_suffix then
    body = core
    suffix = maybe_suffix
  end

  return prefix, body, suffix
end

-- ─────────────────────────────────────────────────────────────
-- Bib file resolution
-- ─────────────────────────────────────────────────────────────

--- Resolve the list of .bib files to use, merging configured paths with any
--- *.bib files found in the current working directory.
---@return string[]
function M.resolve_bib_files()
  local cfg = require("citeref.config").get()
  local seen = {}
  local files = {}

  local function add(path)
    local expanded = vim.fn.expand(path)
    if seen[expanded] then
      return
    end
    seen[expanded] = true
    if vim.fn.filereadable(expanded) == 1 then
      files[#files + 1] = expanded
    else
      vim.notify("citeref: bib file not found: " .. expanded, vim.log.levels.WARN)
    end
  end

  if cfg.bib_files then
    local configured = type(cfg.bib_files) == "function" and cfg.bib_files() or cfg.bib_files
    for _, f in ipairs(configured) do
      add(f)
    end
  end

  for _, f in ipairs(vim.fn.globpath(vim.fn.getcwd(), "*.bib", false, true)) do
    add(f)
  end

  if #files == 0 then
    vim.notify(
      "citeref: no .bib files found.\n" .. "  Put a .bib file in the current directory, or set bib_files in setup().",
      vim.log.levels.WARN
    )
  end

  return files
end

-- ─────────────────────────────────────────────────────────────
-- .bib parser
-- ─────────────────────────────────────────────────────────────

---@class CiterefEntry
---@field key          string
---@field title        string
---@field author       string
---@field year         string
---@field journaltitle string
---@field abstract     string

---@param file_paths string|string[]
---@return CiterefEntry[]
function M.parse_bib(file_paths)
  if type(file_paths) == "string" then
    file_paths = { file_paths }
  end

  local all = {}

  for _, path in ipairs(file_paths) do
    local file = io.open(path, "r")
    if not file then
      vim.notify("citeref: cannot open " .. path, vim.log.levels.WARN)
    else
      local current = {}
      local in_entry = false
      local cur_field = nil

      for line in file:lines() do
        local _, key = line:match("^%s*@(%w+)%s*{%s*([^,%s]+)")
        if key then
          if current.key then
            table.insert(all, current)
          end
          current = { key = key, title = "", author = "", year = "", journaltitle = "", abstract = "" }
          in_entry = true
          cur_field = nil
        elseif in_entry then
          local field, value = line:match('%s*(%w+)%s*=%s*[{"](.-)[}",]*$')
          if field and value then
            field = field:lower()
            value = value:gsub("[{}]", ""):gsub("^%s+", ""):gsub("%s+$", "")
            if field == "title" then
              current.title = value
              cur_field = "title"
            elseif field == "author" then
              current.author = value:gsub("%s+and%s+", "; ")
              cur_field = "author"
            elseif field == "year" then
              current.year = value
              cur_field = "year"
            elseif field == "date" and current.year == "" then
              current.year = value
              cur_field = "date"
            elseif field == "journaltitle" then
              current.journaltitle = value
              cur_field = "journaltitle"
            elseif field == "abstract" then
              current.abstract = value
              cur_field = "abstract"
            else
              cur_field = nil
            end
          else
            if cur_field and not line:match("^[^%s]+") then
              local cont = line:gsub("[{}]", ""):gsub("^%s+", ""):gsub("%s+$", "")
              if cur_field == "author" then
                cont = cont:gsub("%s+and%s+", "; ")
              end
              current[cur_field] = current[cur_field] .. " " .. cont
            end
          end

          if line:match("^%s*}%s*$") then
            in_entry = false
            cur_field = nil
          end
        end
      end

      if current.key then
        table.insert(all, current)
      end
      file:close()
    end
  end

  return all
end

--- Convenience: resolve + parse in one call.
---@return CiterefEntry[]
function M.load_entries()
  local files = M.resolve_bib_files()
  if #files == 0 then
    return {}
  end
  local entries = {}
  for _, f in ipairs(files) do
    vim.list_extend(entries, M.parse_bib(f))
  end
  if #entries == 0 then
    vim.notify("citeref: bib files found but no entries could be parsed", vim.log.levels.WARN)
  end
  return entries
end

-- ─────────────────────────────────────────────────────────────
-- Entry display helpers (shared by all picker backends)
-- ─────────────────────────────────────────────────────────────

---@param entry CiterefEntry
---@return string
function M.entry_display(entry)
  local parts = { entry.key }
  if entry.title ~= "" then
    parts[#parts + 1] = entry.title
  end
  if entry.author ~= "" then
    parts[#parts + 1] = entry.author
  end
  return table.concat(parts, " │ ")
end

---@param entry CiterefEntry
---@return string
function M.entry_preview(entry)
  local lines = {}
  local function add(label, val)
    if val and val ~= "" then
      lines[#lines + 1] = label .. val
      lines[#lines + 1] = ""
    end
  end
  add("Title:    ", entry.title)
  add("Author:   ", entry.author)
  add("Year:     ", entry.year)
  add("Journal:  ", entry.journaltitle)
  add("Abstract: ", entry.abstract)
  return table.concat(lines, "\n")
end

--- Build the markdown citation string from a list of keys → "@key1; @key2".
--- For LaTeX citations, backends use format_latex() with a specific cite command.
---@param keys string[]
---@return string
function M.format_citation(keys)
  local parts = {}
  for _, k in ipairs(keys) do
    parts[#parts + 1] = "@" .. k
  end
  return table.concat(parts, "; ")
end

-- ─────────────────────────────────────────────────────────────
-- Crossref format helper
-- ─────────────────────────────────────────────────────────────

--- Return the correct crossref insertion string for the current buffer's filetype.
--- Quarto uses native @label syntax; R Markdown uses \@ref(fig:label) / \@ref(tab:label);
--- LaTeX uses \ref{label} (label is echoed as-is, no prefix added).
---@param ref_type "fig"|"tab"
---@param label string
---@param bufnr? integer  defaults to current buffer
---@param source? string  "latex" for LaTeX \label sources (no ref_type prefix added in rmd)
---@return string
function M.format_crossref(ref_type, label, bufnr, source)
  local ft = vim.bo[bufnr or vim.api.nvim_get_current_buf()].filetype
  if ft == "quarto" then
    return "@" .. label
  end
  if ft == "tex" or ft == "latex" then
    return string.format("\\ref{%s}", label)
  end
  if source == "latex" then
    return string.format("\\@ref(%s)", label)
  end
  -- R Markdown / markdown: if label already has a type prefix (e.g. fig:), use it directly
  if label:match("^[a-z]+:") then
    return string.format("\\@ref(%s)", label)
  end
  return string.format("\\@ref(%s:%s)", ref_type, label)
end

-- ─────────────────────────────────────────────────────────────
-- Citation-under-cursor detection
-- ─────────────────────────────────────────────────────────────

---@return table|nil
function M.citation_under_cursor()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2]

  -- Markdown @key
  local pos = 1
  while true do
    local s, e = line:find("@[%w_:%-]+", pos)
    if not s then
      break
    end
    if s > 1 and line:sub(s - 1, s - 1) == "\\" then
      pos = e + 1
    elseif col >= s - 1 and col <= e - 1 then
      return { key = line:sub(s + 1, e), start_col = s - 1, end_col = e - 1, style = "markdown" }
    end
    pos = e + 1
  end

  -- MyST {cite:p}`key` / {cite:t}`key`
  local mp = 1
  while true do
    local s, e, role, body = line:find("(%{cite:[pt]%})`([^`]*)`", mp)
    if not s then
      break
    end
    if col >= s - 1 and col <= e - 1 then
      local prefix_raw, core, suffix_raw = parse_myst_body(body)
      local prefix = trim(prefix_raw)
      local suffix = trim(suffix_raw)
      local all_keys = {}
      local key_at_cursor = nil
      local body_start = s + #role + 1
      local core_start = body_start
      if prefix_raw ~= "" then
        core_start = core_start + #prefix_raw + 2
      end

      local kp = 1
      while true do
        local ks, ke = core:find("[^;%s]+", kp)
        if not ks then
          break
        end
        local key = core:sub(ks, ke)
        all_keys[#all_keys + 1] = key
        local abs_s = core_start + ks - 1
        local abs_e = core_start + ke - 1
        if col >= abs_s - 1 and col <= abs_e - 1 then
          key_at_cursor = key
        end
        kp = ke + 1
      end
      if #all_keys > 0 then
        return {
          key = key_at_cursor or all_keys[1],
          start_col = s - 1,
          end_col = e - 1,
          style = "myst",
          cmd = role:sub(2, -2),
          prefix = prefix,
          suffix = suffix,
          all_keys = all_keys,
        }
      end
    end
    mp = e + 1
  end

  -- LaTeX \cmd{...}
  local sp = 1
  while true do
    local s, e = line:find("\\%a+%s*{%s*[^{}]-%s*}", sp)
    if not s then
      break
    end
    local capture = line:sub(s, e)
    local cmd, inside = capture:match("\\(%a+)%s*{%s*([^{}]-)%s*}")
    if cmd and inside then
      local bo = line:find("{", s, true)
      local bc = line:find("}", bo, true)
      if bo and bc then
        local isp = 1
        while true do
          local ks, ke = inside:find("[^,%s]+", isp)
          if not ks then
            break
          end
          local abs_s = bo + ks
          local abs_e = bo + ke
          if col >= abs_s - 1 and col <= abs_e - 1 then
            local all_keys = {}
            for k in inside:gmatch("[^,%s]+") do
              all_keys[#all_keys + 1] = k
            end
            return {
              key = inside:sub(ks, ke),
              start_col = abs_s - 1,
              end_col = abs_e - 1,
              style = "latex",
              cmd = cmd,
              all_keys = all_keys,
              cmd_start = s - 1,
              cmd_end = e - 1,
              brace_open = bo - 1,
              brace_close = bc - 1,
            }
          end
          isp = ke + 1
        end
      end
    end
    sp = e + 1
  end

  return nil
end

-- ─────────────────────────────────────────────────────────────
-- Chunk parser
-- ─────────────────────────────────────────────────────────────

---@class CiterefChunk
---@field label      string
---@field display    string
---@field line       integer
---@field file       string
---@field is_current boolean
---@field header     string

local CHUNK_LANGS = { r = true, python = true, julia = true, ojs = true, observable = true }

--- Check if a line is a chunk fence opener (```{r ...} or ```{r}).
--- Returns true if so, along with any inline label found on that line.
---@param line string
---@return boolean is_fence
---@return string inline_label  empty string if none on this line
local function is_chunk_fence(line)
  local lang = line:match("^```{(%a+)")
  if not lang or not CHUNK_LANGS[lang:lower()] then
    return false, ""
  end
  -- R supports an optional inline label: ```{r label} or ```{r label, ...}
  -- All other languages (python, julia, …) use #| label: only.
  if lang:lower() == "r" then
    if line:match("^```{r%s*[,}]") then
      return true, ""
    end
    local label = line:match("^```{r%s+([^%s,}]+)")
    return true, label or ""
  end
  return true, ""
end

--- Scan lines after a fence opener for a `#| label: name` YAML option.
--- `all_lines` is a list; `start` is the 1-based index of the line *after* the fence.
---@param all_lines string[]
---@param start integer
---@return string  label (empty string if not found)
local function find_yaml_label(all_lines, start)
  for i = start, math.min(start + 20, #all_lines) do
    local l = all_lines[i]
    -- Stop at the closing fence or a non-option line (no leading #|)
    if l:match("^```") then
      break
    end
    local yaml_label = l:match("^#|%s*label:%s*([%w_%-%.]+)")
    if yaml_label then
      return yaml_label
    end
    -- A non-comment, non-blank line inside the chunk means no more YAML options
    if not l:match("^%s*$") and not l:match("^#|") then
      break
    end
  end
  return ""
end

---@param bufnr integer
---@return CiterefChunk[]
local function chunks_from_buf(bufnr)
  local chunks = {}
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local path = vim.api.nvim_buf_get_name(bufnr)
  local fname = vim.fn.fnamemodify(path, ":t")
  local unnamed_count = 0

  local i = 1
  while i <= #lines do
    local line = lines[i]
    local is_fence, inline_label = is_chunk_fence(line)
    if is_fence then
      local label = inline_label
      -- If no inline label, look for #| label: on subsequent lines
      if label == "" then
        label = find_yaml_label(lines, i + 1)
      end

      local display
      if label == "" then
        unnamed_count = unnamed_count + 1
        display = string.format("[unnamed #%d] line %d  (%s)", unnamed_count, i, fname)
      else
        display = string.format("%s  line %d  (%s)", label, i, fname)
      end
      chunks[#chunks + 1] = {
        label = label,
        display = display,
        line = i,
        file = path,
        is_current = true,
        header = line,
      }
    end
    i = i + 1
  end
  return chunks
end

---@param filepath string
---@return CiterefChunk[]
local function chunks_from_file(filepath)
  local chunks = {}
  local file = io.open(filepath, "r")
  if not file then
    return chunks
  end

  -- Read all lines so we can look ahead for #| label:
  local all_lines = {}
  for l in file:lines() do
    all_lines[#all_lines + 1] = l
  end
  file:close()

  local fname = vim.fn.fnamemodify(filepath, ":t")
  local unnamed_count = 0

  for i, line in ipairs(all_lines) do
    local is_fence, inline_label = is_chunk_fence(line)
    if is_fence then
      local label = inline_label
      if label == "" then
        label = find_yaml_label(all_lines, i + 1)
      end

      local display
      if label == "" then
        unnamed_count = unnamed_count + 1
        display = string.format("[unnamed #%d] line %d  (%s)", unnamed_count, i, fname)
      else
        display = string.format("%s  line %d  (%s)", label, i, fname)
      end
      chunks[#chunks + 1] = {
        label = label,
        display = display,
        line = i,
        file = filepath,
        is_current = false,
        header = line,
      }
    end
  end
  return chunks
end

--- Return all chunks from the current buffer + sibling rmd/qmd files.
---@return CiterefChunk[]
function M.load_chunks()
  local bufnr = vim.api.nvim_get_current_buf()
  local cur_file = vim.api.nvim_buf_get_name(bufnr)
  local cur_dir = vim.fn.fnamemodify(cur_file, ":h")

  local result = chunks_from_buf(bufnr)
  local rmd_files = vim.fn.globpath(cur_dir, "*.{rmd,Rmd,qmd,Qmd}", false, true)
  for _, f in ipairs(rmd_files) do
    if f ~= cur_file then
      vim.list_extend(result, chunks_from_file(f))
    end
  end
  return result
end

-- ─────────────────────────────────────────────────────────────
-- LaTeX label parser
-- ─────────────────────────────────────────────────────────────

--- Map of LaTeX environments to crossref types.
local ENV_TYPE_MAP = {
  figure = "fig",
  ["figure*"] = "fig",
  table = "tab",
  ["table*"] = "tab",
}

--- Scan a list of lines for \label{...} inside figure/table environments.
--- Labels that are not inside a recognised environment are skipped.
--- The label is stored as-is (any fig:/tab: prefix is preserved).
---@param lines string[]
---@param filepath string
---@param is_current boolean
---@param type_filter? "fig"|"tab"  if set, only return labels of this type
---@return CiterefChunk[]
local function labels_from_lines(lines, filepath, is_current, type_filter)
  local labels = {}
  local fname = filepath ~= "" and vim.fn.fnamemodify(filepath, ":t") or "[No Name]"

  local env_stack = {}

  for i, line in ipairs(lines) do
    -- Strip full-line comments (lines starting with % after optional whitespace)
    if line:match("^%s*%%") then
      goto continue
    end

    -- Process \begin{env} and \end{env} in text order on this line
    local pos = 1
    while pos <= #line do
      local bs = line:find("\\begin{", pos)
      local es = line:find("\\end{", pos)
      if not bs and not es then
        break
      end
      if bs and (not es or bs < es) then
        local _, be, env = line:find("\\begin{(%*?%a+%*?)}", bs)
        if env then
          env_stack[#env_stack + 1] = env
          pos = be + 1
        else
          pos = bs + 1
        end
      else
        local _, ee, env = line:find("\\end{(%*?%a+%*?)}", es)
        if env then
          for j = #env_stack, 1, -1 do
            if env_stack[j] == env then
              table.remove(env_stack, j)
              break
            end
          end
          pos = ee + 1
        else
          pos = es + 1
        end
      end
    end

    -- Determine current type from environment stack (innermost match)
    local cur_type = nil
    for j = #env_stack, 1, -1 do
      local t = ENV_TYPE_MAP[env_stack[j]]
      if t then
        cur_type = t
        break
      end
    end

    -- Find \label{...} on this line
    for raw_label in line:gmatch("\\label{([^}]+)}") do
      if cur_type and (type_filter == nil or cur_type == type_filter) then
        labels[#labels + 1] = {
          label = raw_label,
          display = string.format("%s  line %d  (%s)", raw_label, i, fname),
          line = i,
          file = filepath,
          is_current = is_current,
          header = line,
          source = "latex",
        }
      end
    end

    ::continue::
  end

  return labels
end

---@param filepath string
---@param type_filter? "fig"|"tab"
---@return CiterefChunk[]
local function labels_from_file(filepath, type_filter)
  local file = io.open(filepath, "r")
  if not file then
    return {}
  end
  local all_lines = {}
  for l in file:lines() do
    all_lines[#all_lines + 1] = l
  end
  file:close()
  return labels_from_lines(all_lines, filepath, false, type_filter)
end

--- Return all cross-reference targets (code chunks + LaTeX labels) for the
--- current buffer and sibling files, optionally filtered by type.
--- For tex/latex buffers only LaTeX labels are scanned; for other filetypes
--- code chunks are included as well (existing behaviour).
---@param ref_type? "fig"|"tab"  if set, only return labels of this type
---@return CiterefChunk[]
function M.load_labels(ref_type)
  local bufnr = vim.api.nvim_get_current_buf()
  local cur_file = vim.api.nvim_buf_get_name(bufnr)
  local cur_dir = vim.fn.fnamemodify(cur_file, ":h")
  local ft = vim.bo[bufnr].filetype
  local is_tex = ft == "tex" or ft == "latex"

  local result = {}

  if is_tex then
    -- LaTeX buffers: only scan for LaTeX labels, no code chunks
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    vim.list_extend(result, labels_from_lines(lines, cur_file, true, ref_type))

    local tex_files = vim.fn.globpath(cur_dir, "*.{tex,TEX}", false, true)
    for _, f in ipairs(tex_files) do
      if f ~= cur_file then
        vim.list_extend(result, labels_from_file(f, ref_type))
      end
    end
  else
    -- R Markdown / Quarto / Markdown: code chunks + LaTeX labels
    result = M.load_chunks()

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    vim.list_extend(result, labels_from_lines(lines, cur_file, true, ref_type))

    local rmd_files = vim.fn.globpath(cur_dir, "*.{rmd,Rmd,qmd,Qmd}", false, true)
    for _, f in ipairs(rmd_files) do
      if f ~= cur_file then
        vim.list_extend(result, labels_from_file(f, ref_type))
      end
    end
  end

  return result
end

return M
