--- citeref.nvim – write a .bib with only the entries cited in the documents
local M = {}

local LATEX_EXT = { tex = true, rnw = true, jnw = true }
local MD_EXT = { md = true, markdown = true, rmd = true, qmd = true }
-- documents that are knitted to a .tex of the same name
local KNIT_EXT = { rnw = true, jnw = true, rmd = true, qmd = true }
local DOC_GLOB = "*.{tex,rnw,Rnw,jnw,Jnw,md,markdown,rmd,Rmd,qmd,Qmd}"
-- fields that pull in other entries
local LINK_FIELDS = { "crossref", "xref", "xdata", "entryset" }

local function abspath(p)
  return vim.fn.fnamemodify(vim.fn.expand(p), ":p")
end

local function basename(p)
  return vim.fn.fnamemodify(p, ":t")
end

--- Lines of `path`, taken from its buffer when loaded (unsaved edits count).
---@param path string
---@param bufs table<string, integer>
---@return string[]
local function read_lines(path, bufs)
  local buf = bufs[path]
  if buf then
    return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  end
  local f = io.open(path, "r")
  if not f then
    return {}
  end
  local lines = {}
  for l in f:lines() do
    lines[#lines + 1] = l
  end
  f:close()
  return lines
end

local function loaded_buffers()
  local bufs = {}
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(b)
    if name ~= "" and vim.api.nvim_buf_is_loaded(b) then
      bufs[abspath(name)] = b
    end
  end
  return bufs
end

-- ─────────────────────────────────────────────────────────────
-- Cited keys
-- ─────────────────────────────────────────────────────────────

--- Drop a LaTeX comment (first unescaped %).
local function strip_latex_comment(line)
  local i = 1
  while true do
    local s = line:find("%", i, true)
    if not s then
      return line
    end
    local n, j = 0, s - 1
    while j > 0 and line:sub(j, j) == "\\" do
      n = n + 1
      j = j - 1
    end
    if n % 2 == 0 then
      return line:sub(1, s - 1)
    end
    i = s + 1
  end
end

--- Keys from \…cite…[..](..){a,b} commands; \…cites takes several {} groups.
---@param lines string[]
---@param add fun(key: string)
function M.latex_keys(lines, add)
  local kept = {}
  local in_chunk = false
  for _, line in ipairs(lines) do
    if in_chunk then
      if line:match("^@%s*$") or line:match("^@%s") then
        in_chunk = false
      end
    elseif line:match("^%s*<<.*>>=%s*$") then
      in_chunk = true
    else
      kept[#kept + 1] = strip_latex_comment(line)
    end
  end
  local text = table.concat(kept, "\n")

  local pos = 1
  while true do
    local s, e, cmd = text:find("\\(%a*[cC]ite%a*)", pos)
    if not s then
      return
    end
    local multi = cmd:lower():sub(-5) == "cites"
    local p = e + 1
    if text:sub(p, p) == "*" then
      p = p + 1
    end
    while true do
      local q = p + #text:match("^%s*", p)
      local c = text:sub(q, q)
      if c == "[" or c == "(" then
        local close = text:find(c == "[" and "]" or ")", q + 1, true)
        if not close then
          break
        end
        p = close + 1
      elseif c == "{" then
        local close = text:find("}", q + 1, true)
        if not close then
          break
        end
        for k in text:sub(q + 1, close - 1):gmatch("[^,]+") do
          add(vim.trim(k))
        end
        p = close + 1
        if not multi then
          break
        end
      else
        break
      end
    end
    pos = p > e and p or e + 1
  end
end

--- Keys from pandoc @key / @{key} and MyST {cite:p}`key` citations,
--- skipping fenced code blocks and inline code.
---@param lines string[]
---@param add fun(key: string)
function M.markdown_keys(lines, add)
  local fence
  for _, line in ipairs(lines) do
    local f = line:match("^%s*(```+)") or line:match("^%s*(~~~+)")
    if fence then
      if f and f:sub(1, 1) == fence:sub(1, 1) and #f >= #fence and line:match("^%s*[`~]+%s*$") then
        fence = nil
      end
    elseif f then
      fence = f
    else
      for body in line:gmatch("{cite[:%a]*}`([^`]*)`") do
        for k in body:gmatch("[^;,%s]+") do
          add(k)
        end
      end
      local l = line:gsub("`[^`]*`", "")
      for at, key in l:gmatch("()@(%b{})") do
        if at == 1 or not l:sub(at - 1, at - 1):match("[%w\\]") then
          add(key:sub(2, -2))
        end
      end
      for at, key in l:gmatch("()@([%w_%*][%w_:%.#%$%%&%-%+%?<>~/]*)") do
        if at == 1 or not l:sub(at - 1, at - 1):match("[%w\\]") then
          add((key:gsub("[:%.#%$%%&%-%+%?<>~/]+$", "")))
        end
      end
    end
  end
end

-- ─────────────────────────────────────────────────────────────
-- Caches: documents and .bib files are re-read only when they change
-- ─────────────────────────────────────────────────────────────

M.stats = { doc_scans = 0, bib_reads = 0 }
local doc_cache = {} -- path → { sig, keys, nocite_all }
local bib_cache = {} -- path → { sig, entries, extras }

---@param path string
---@return string|nil
local function file_sig(path)
  local st = vim.uv.fs_stat(path)
  if not st then
    return nil
  end
  return st.mtime.sec .. "." .. st.mtime.nsec .. "." .. st.size
end

--- Keys cited in one document, re-scanned only when it changed.
local function scan_doc(path, ext, bufs)
  local sig = bufs[path] and ("b" .. vim.api.nvim_buf_get_changedtick(bufs[path])) or file_sig(path)
  local hit = doc_cache[path]
  if hit and sig and hit.sig == sig then
    return hit
  end
  M.stats.doc_scans = M.stats.doc_scans + 1
  local doc = { sig = sig, keys = {}, nocite_all = false }
  local function add(k)
    if k == "*" then
      doc.nocite_all = true
    elseif k ~= "" then
      doc.keys[k] = true
    end
  end
  local lines = read_lines(path, bufs)
  if LATEX_EXT[ext] then
    M.latex_keys(lines, add)
  elseif MD_EXT[ext] then
    M.markdown_keys(lines, add)
  end
  doc_cache[path] = doc
  return doc
end

--- Drop all cached documents and .bib files.
function M.clear_cache()
  doc_cache, bib_cache = {}, {}
end

---@param name string
---@param exclude string[]
local function excluded(name, exclude)
  for _, pat in ipairs(exclude) do
    if name:match(pat) then
      return true
    end
  end
  return false
end

--- Cited keys in every document of `dir`.
--- A .tex is skipped when a .rnw/.rmd/... of the same name exists (it is knitted output).
---@param dir string
---@param exclude? string[]  Lua patterns matched against file names
---@return table<string, boolean> keys
---@return boolean nocite_all  true when \nocite{*} or @* is used
function M.cited_keys(dir, exclude)
  exclude = exclude or {}
  local files = vim.fn.globpath(dir, DOC_GLOB, false, true)
  local knitted = {}
  for _, f in ipairs(files) do
    if KNIT_EXT[vim.fn.fnamemodify(f, ":e"):lower()] then
      knitted[vim.fn.fnamemodify(f, ":t:r")] = true
    end
  end

  local keys, nocite_all = {}, false
  local bufs = loaded_buffers()
  for _, f in ipairs(files) do
    local ext = vim.fn.fnamemodify(f, ":e"):lower()
    local skip = excluded(basename(f), exclude) or (ext == "tex" and knitted[vim.fn.fnamemodify(f, ":t:r")])
    if not skip then
      local doc = scan_doc(abspath(f), ext, bufs)
      for k in pairs(doc.keys) do
        keys[k] = true
      end
      nocite_all = nocite_all or doc.nocite_all
    end
  end
  return keys, nocite_all
end

-- ─────────────────────────────────────────────────────────────
-- Raw .bib reading
-- ─────────────────────────────────────────────────────────────

local function ci(s)
  return (s:gsub("%a", function(c)
    return "[" .. c:lower() .. c:upper() .. "]"
  end))
end

local LINK_PATTERNS = {}
for _, field in ipairs(LINK_FIELDS) do
  LINK_PATTERNS[#LINK_PATTERNS + 1] = "[,%s]" .. ci(field) .. "%s*=%s*[{\"]([^}\"]*)"
end

--- Keys referenced by crossref/xref/xdata/entryset in a raw entry.
---@param raw string
---@return string[]
function M.linked_keys(raw)
  local out = {}
  for _, pat in ipairs(LINK_PATTERNS) do
    for value in raw:gmatch(pat) do
      for k in value:gmatch("[^,%s]+") do
        out[#out + 1] = k
      end
    end
  end
  return out
end

--- Read a .bib file verbatim, entry by entry.
---@param path string
---@return table<string, string>|nil entries  key → raw entry text
---@return string[] extras  @string / @preamble blocks
function M.read_bib_raw(path)
  local f = io.open(path, "r")
  if not f then
    return nil, {}
  end
  local text = f:read("*a")
  f:close()

  local entries, extras = {}, {}
  local pos = 1
  while true do
    local s, e, typ, open = text:find("@%s*(%a+)%s*([{(])", pos)
    if not s then
      break
    end
    local depth = open == "{" and 1 or 0
    local i, stop = e + 1, nil
    while true do
      local j = text:find("[{}()]", i)
      if not j then
        break
      end
      local c = text:sub(j, j)
      if c == "{" then
        depth = depth + 1
      elseif c == "}" then
        depth = depth - 1
        if open == "{" and depth == 0 then
          stop = j
          break
        end
      elseif c == ")" and open == "(" and depth == 0 then
        stop = j
        break
      end
      i = j + 1
    end
    if not stop then
      break
    end
    local raw = text:sub(s, stop)
    typ = typ:lower()
    if typ == "string" or typ == "preamble" then
      extras[#extras + 1] = raw
    elseif typ ~= "comment" then
      local key = text:match("^%s*([^,%s]+)", e + 1)
      if key and not entries[key] then
        entries[key] = raw
      end
    end
    pos = stop + 1
  end
  return entries, extras
end

-- ─────────────────────────────────────────────────────────────
-- write_bib
-- ─────────────────────────────────────────────────────────────

--- read_bib_raw() with a cache keyed on the file's mtime and size.
---@param path string
local function cached_bib(path)
  local sig = file_sig(path)
  local hit = bib_cache[path]
  if hit and sig and hit.sig == sig then
    return hit.entries, hit.extras
  end
  M.stats.bib_reads = M.stats.bib_reads + 1
  local entries, extras = M.read_bib_raw(path)
  bib_cache[path] = { sig = sig, entries = entries or {}, extras = extras }
  return entries or {}, extras
end

-- out_path → { keys, sources, missing, nocite } of the last run
local last = {}

local function default_dir()
  local name = vim.api.nvim_buf_get_name(0)
  if name ~= "" then
    return vim.fn.fnamemodify(name, ":p:h")
  end
  return vim.fn.getcwd()
end

---@class CiterefWriteBibOpts
---@field dir?     string    folder with the documents (default: current buffer's folder)
---@field output?  string    file name or path (default: config write_bib.output)
---@field sources? string[]  bib files to copy entries from (default: configured bib_files)
---@field exclude? string[]  Lua patterns for document names to skip
---@field silent?  boolean   no notifications

---@class CiterefWriteBibResult
---@field path    string
---@field written integer   number of entries in the file
---@field missing string[]  cited keys found in no .bib file
---@field changed boolean   false when the file already had this content

--- Folder, output path, exclude patterns and bib files for a run.
---@param opts CiterefWriteBibOpts
local function resolve(opts)
  local cfg = require("citeref.config").get()
  local wcfg = cfg.write_bib or {}
  local dir = abspath(opts.dir or default_dir()):gsub("/$", "")
  local output = opts.output or wcfg.output or "references.bib"
  local out_path = abspath(output:sub(1, 1) == "/" and output or (dir .. "/" .. output))

  local local_bibs = {}
  for _, f in ipairs(vim.fn.globpath(dir, "*.bib", false, true)) do
    if abspath(f) ~= out_path then
      local_bibs[#local_bibs + 1] = abspath(f)
    end
  end

  local sources = opts.sources
  if not sources then
    sources = cfg.bib_files or {}
    if type(sources) == "function" then
      sources = sources()
    end
  end
  local source_paths = {}
  for _, f in ipairs(sources) do
    local p = abspath(f)
    if p ~= out_path and vim.fn.filereadable(p) == 1 then
      source_paths[#source_paths + 1] = p
    end
  end
  if #source_paths == 0 then
    source_paths = local_bibs
  end

  return {
    dir = dir,
    out_path = out_path,
    exclude = opts.exclude or wcfg.exclude or {},
    sources = source_paths,
    local_bibs = local_bibs,
  }
end

local function keys_sig(cited)
  local ks = vim.tbl_keys(cited)
  table.sort(ks)
  return table.concat(ks, ",")
end

local function sources_sig(r)
  local parts = {}
  for _, list in ipairs({ r.sources, r.local_bibs }) do
    for _, p in ipairs(list) do
      parts[#parts + 1] = p .. "=" .. (file_sig(p) or "")
    end
  end
  return table.concat(parts, "|")
end

--- Select the cited entries and write the file (only if its content changed).
---@return CiterefWriteBibResult|nil
---@return string|nil err
local function build(r, cited)
  -- entries to copy (first source wins), and keys known anywhere
  local pool, extras, seen_extra = {}, {}, {}
  for _, p in ipairs(r.sources) do
    local entries, ex = cached_bib(p)
    for k, raw in pairs(entries) do
      if not pool[k] then
        pool[k] = raw
      end
    end
    for _, x in ipairs(ex) do
      if not seen_extra[x] then
        seen_extra[x] = true
        extras[#extras + 1] = x
      end
    end
  end
  local known = {}
  for _, p in ipairs(r.local_bibs) do
    for k in pairs((cached_bib(p))) do
      known[k] = true
    end
  end

  -- cited entries plus the entries they link to
  local selected, missing = {}, {}
  local queue = vim.tbl_keys(cited)
  while #queue > 0 do
    local k = table.remove(queue)
    if not selected[k] then
      if pool[k] then
        selected[k] = true
        vim.list_extend(queue, M.linked_keys(pool[k]))
      elseif cited[k] and not known[k] then
        missing[#missing + 1] = k
      end
    end
  end

  local keys = vim.tbl_keys(selected)
  table.sort(keys)
  table.sort(missing)
  local parts = { "% generated by citeref.nvim" }
  for _, x in ipairs(extras) do
    parts[#parts + 1] = x
  end
  for _, k in ipairs(keys) do
    parts[#parts + 1] = pool[k]
  end
  local content = table.concat(parts, "\n\n") .. "\n"

  local old
  local fr = io.open(r.out_path, "r")
  if fr then
    old = fr:read("*a")
    fr:close()
  end
  local changed = old ~= content
  if changed then
    local fw, err = io.open(r.out_path, "w")
    if not fw then
      return nil, "cannot write " .. r.out_path .. ": " .. tostring(err)
    end
    fw:write(content)
    fw:close()
  end
  return { path = r.out_path, written = #keys, missing = missing, changed = changed }
end

local function remember(r, cited, res)
  last[r.out_path] = {
    keys = keys_sig(cited),
    sources = sources_sig(r),
    missing = table.concat(res.missing, ","),
  }
end

--- Write a .bib file with only the entries cited in the documents of `dir`.
---@param opts? CiterefWriteBibOpts
---@return CiterefWriteBibResult|nil
function M.write_bib(opts)
  opts = opts or {}
  local function notify(msg, level)
    if not opts.silent then
      vim.notify("citeref: " .. msg, level or vim.log.levels.INFO)
    end
  end

  local r = resolve(opts)
  local cited, nocite_all = M.cited_keys(r.dir, r.exclude)
  if nocite_all then
    notify("\\nocite{*} or @* cites the whole library; not writing " .. basename(r.out_path), vim.log.levels.ERROR)
    return nil
  end

  local res, err = build(r, cited)
  if not res then
    notify(err, vim.log.levels.ERROR)
    return nil
  end
  remember(r, cited, res)

  notify(string.format("%d entries → %s%s", res.written, basename(r.out_path), res.changed and "" or " (unchanged)"))
  if #res.missing > 0 then
    notify("cited but not in any .bib: " .. table.concat(res.missing, ", "), vim.log.levels.WARN)
  end
  return res
end

--- Update the .bib after `buf` is saved, if its folder already has one.
--- Returns nil when there is nothing to sync; `skipped = true` when neither
--- the cited keys nor the bib files changed since the last run.
---@param buf integer
---@return (CiterefWriteBibResult|{ skipped: boolean })|nil
function M.sync(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" then
    return nil
  end
  local r = resolve({ dir = vim.fn.fnamemodify(name, ":p:h") })
  if not vim.uv.fs_stat(r.out_path) then
    return nil
  end

  local cited, nocite_all = M.cited_keys(r.dir, r.exclude)
  local prev = last[r.out_path]
  if nocite_all then
    if not (prev and prev.nocite) then
      vim.notify("citeref: \\nocite{*} or @* cites the whole library; not syncing " .. basename(r.out_path), vim.log.levels.WARN)
    end
    last[r.out_path] = { nocite = true }
    return nil
  end
  if prev and prev.keys == keys_sig(cited) and prev.sources == sources_sig(r) then
    return { skipped = true }
  end

  local res, err = build(r, cited)
  if not res then
    vim.notify("citeref: " .. err, vim.log.levels.ERROR)
    return nil
  end
  if res.changed then
    vim.notify(string.format("citeref: %d entries → %s", res.written, basename(r.out_path)), vim.log.levels.INFO)
  end
  local missing = table.concat(res.missing, ",")
  if missing ~= "" and not (prev and prev.missing == missing) then
    vim.notify("citeref: cited but not in any .bib: " .. table.concat(res.missing, ", "), vim.log.levels.WARN)
  end
  remember(r, cited, res)
  return res
end

return M
