--- citeref.nvim – citation picking and insertion
local util   = require("citeref.util")
local config = require("citeref.config")

local M = {}

-- ─────────────────────────────────────────────────────────────
-- Bib file resolution
-- ─────────────────────────────────────────────────────────────

---@return string[]
local function resolve_bib_files()
  local cfg = config.get()

  if cfg.bib_files then
    if type(cfg.bib_files) == "function" then
      return cfg.bib_files()
    end
    return cfg.bib_files
  end

  -- Default: zotero.bib in ~/Documents + any *.bib in cwd
  local zotero   = vim.fn.expand("~/Documents/zotero.bib")
  local cwd_bibs = vim.fn.globpath(vim.fn.getcwd(), "*.bib", false, true)

  local files = {}
  if vim.fn.filereadable(zotero) == 1 then
    table.insert(files, zotero)
  end
  for _, b in ipairs(cwd_bibs) do
    if b ~= zotero then
      table.insert(files, b)
    end
  end
  return files
end

-- ─────────────────────────────────────────────────────────────
-- .bib parser
-- ─────────────────────────────────────────────────────────────

---@class CiterefEntry
---@field key string
---@field title string
---@field author string
---@field year string
---@field journaltitle string
---@field abstract string

---@param file_paths string|string[]
---@return CiterefEntry[]
function M.parse_bib(file_paths)
  if type(file_paths) == "string" then file_paths = { file_paths } end

  local all = {}

  for _, path in ipairs(file_paths) do
    local file = io.open(path, "r")
    if not file then
      vim.notify("citeref: cannot open " .. path, vim.log.levels.WARN)
    else
      local current    = {}
      local in_entry   = false
      local cur_field  = nil

      for line in file:lines() do
        local entry_type, key = line:match("^%s*@(%w+)%s*{%s*([^,%s]+)")
        if entry_type and key then
          if current.key then table.insert(all, current) end
          current   = { key = key, title = "", author = "", year = "", journaltitle = "", abstract = "" }
          in_entry  = true
          cur_field = nil

        elseif in_entry then
          local field, value = line:match('%s*(%w+)%s*=%s*[{"](.-)[}",]*$')
          if field and value then
            field = field:lower()
            value = value:gsub("[{}]", ""):gsub("^%s+", ""):gsub("%s+$", "")
            if     field == "title"        then current.title        = value ; cur_field = "title"
            elseif field == "author"       then current.author       = value:gsub("%s+and%s+", "; ") ; cur_field = "author"
            elseif field == "year"         then current.year         = value ; cur_field = "year"
            elseif field == "date" and current.year == "" then current.year = value ; cur_field = "date"
            elseif field == "journaltitle" then current.journaltitle = value ; cur_field = "journaltitle"
            elseif field == "abstract"     then current.abstract     = value ; cur_field = "abstract"
            else                                                               cur_field = nil
            end
          else
            -- continuation line
            if cur_field and not line:match("^[^%s]+") then
              local cont = line:gsub("[{}]", ""):gsub("^%s+", ""):gsub("%s+$", "")
              if cur_field == "author" then cont = cont:gsub("%s+and%s+", "; ") end
              current[cur_field] = current[cur_field] .. " " .. cont
            end
          end

          if line:match("^%s*}%s*$") then in_entry = false ; cur_field = nil end
        end
      end

      if current.key then table.insert(all, current) end
      file:close()
    end
  end

  return all
end

-- ─────────────────────────────────────────────────────────────
-- Display / preview helpers
-- ─────────────────────────────────────────────────────────────

---@param entry CiterefEntry
---@return string
local function display_line(entry)
  local parts = { entry.key }
  if entry.title  ~= "" then parts[#parts+1] = entry.title  end
  if entry.author ~= "" then parts[#parts+1] = entry.author end
  return table.concat(parts, " │ ")
end

---@param entry CiterefEntry
---@return string
local function preview_text(entry)
  local lines = {}
  local function add(label, val) if val and val ~= "" then lines[#lines+1] = label .. val ; lines[#lines+1] = "" end end
  add("Title:    ",   entry.title)
  add("Author:   ",   entry.author)
  add("Year:     ",   entry.year)
  add("Journal:  ",   entry.journaltitle)
  add("Abstract: ",   entry.abstract)
  return table.concat(lines, "\n")
end

-- ─────────────────────────────────────────────────────────────
-- fzf-lua custom previewer
-- ─────────────────────────────────────────────────────────────

---@param entries CiterefEntry[]
local function make_previewer(entries)
  local Previewer = require("fzf-lua.previewer.builtin")
  local P         = Previewer.buffer_or_file:extend()

  function P:new(o, opts, fzf_win)
    P.super.new(self, o, opts, fzf_win)
    setmetatable(self, P)
    return self
  end

  function P:parse_entry(entry_str)
    return { path = entry_str:match("^([^%s│]+)") }
  end

  function P:populate_preview_buf(entry_str)
    local key    = entry_str:match("^([^%s│]+)"):gsub(" %(current%)$", "")
    local found  = nil
    for _, e in ipairs(entries) do
      if e.key == key then found = e ; break end
    end
    if not found then return false end

    if not self.preview_bufnr or not vim.api.nvim_buf_is_valid(self.preview_bufnr) then
      self.preview_bufnr = vim.api.nvim_create_buf(false, true)
      vim.bo[self.preview_bufnr].bufhidden = "wipe"
    end

    local text_lines = vim.split(preview_text(found), "\n")
    vim.api.nvim_buf_set_lines(self.preview_bufnr, 0, -1, false, text_lines)
    self:set_preview_buf(self.preview_bufnr)
    self.preview_bufloaded = true
    return true
  end

  return P
end

-- ─────────────────────────────────────────────────────────────
-- Citation under cursor detection
-- ─────────────────────────────────────────────────────────────

---@return table|nil
function M.get_citation_under_cursor()
  local line = vim.api.nvim_get_current_line()
  local col  = vim.api.nvim_win_get_cursor(0)[2]

  -- Markdown @key
  local pos = 1
  while true do
    local s, e = line:find("@[%w_%-:%.]+", pos)
    if not s then break end
    if col >= s - 1 and col <= e - 1 then
      return { key = line:sub(s+1, e), start_col = s-1, end_col = e-1, style = "markdown" }
    end
    pos = e + 1
  end

  -- LaTeX \cmd{...}
  local sp = 1
  while true do
    local s, e = line:find("\\%a+%s*{%s*[^{}]-%s*}", sp)
    if not s then break end
    local capture = line:sub(s, e)
    local cmd, inside = capture:match("\\(%a+)%s*{%s*([^{}]-)%s*}")
    if cmd and inside then
      local bo = line:find("{", s, true)
      local bc = line:find("}", bo,  true)
      if bo and bc then
        local isp = 1
        while true do
          local ks, ke = inside:find("[^,%s]+", isp)
          if not ks then break end
          local abs_s = bo + ks - 1
          local abs_e = bo + ke - 1
          if col >= abs_s - 1 and col <= abs_e - 1 then
            local all_keys = {}
            for k in inside:gmatch("[^,%s]+") do all_keys[#all_keys+1] = k end
            return {
              key        = inside:sub(ks, ke),
              start_col  = abs_s - 1,
              end_col    = abs_e - 1,
              style      = "latex",
              cmd        = cmd,
              all_keys   = all_keys,
              cmd_start  = s  - 1,
              cmd_end    = e  - 1,
              brace_open  = bo - 1,
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
-- Pickers
-- ─────────────────────────────────────────────────────────────

---@param format "markdown"|"latex"
function M.pick(format)
  format = format or "markdown"

  local bib_files = resolve_bib_files()
  local entries   = {}
  for _, path in ipairs(bib_files) do
    vim.list_extend(entries, M.parse_bib(path))
  end

  if #entries == 0 then
    vim.notify("citeref: no citations found in bib files", vim.log.levels.WARN)
    return
  end

  local ctx      = util.save_context()
  local cfg      = config.get()
  local preview_pos = cfg.picker.layout == "horizontal"
    and ("down:" .. cfg.picker.preview_size)
    or  ("down:" .. cfg.picker.preview_size)  -- both use down for vertical layout
  local title    = format == "latex" and " Citations [LaTeX] " or " Citations [Markdown] "

  -- Build display → entry lookup
  local lookup = {}
  local lines  = {}
  for _, e in ipairs(entries) do
    local d = display_line(e)
    lookup[d] = e
    lines[#lines+1] = d
  end

  require("fzf-lua").fzf_exec(function(cb)
    for _, l in ipairs(lines) do cb(l) end
    cb()
  end, {
    prompt    = "> ",
    previewer = make_previewer(entries),
    winopts   = {
      title   = title,
      preview = { layout = "vertical", vertical = preview_pos, wrap = "wrap", scrollbar = "border" },
    },
    actions = {
      ["default"] = function(selected)
        if #selected == 0 then return end
        local keys = {}
        for _, l in ipairs(selected) do
          local e = lookup[l]
          if e then keys[#keys+1] = e.key end
        end
        if #keys == 0 then return end
        table.sort(keys)

        local text
        if format == "latex" then
          text = "\\cite{" .. table.concat(keys, ", ") .. "}"
        else
          local parts = {}
          for _, k in ipairs(keys) do parts[#parts+1] = "@" .. k end
          text = table.concat(parts, "; ")
        end

        util.insert_at_context(ctx, text)
        vim.defer_fn(function()
          vim.notify("citeref: inserted " .. text, vim.log.levels.INFO)
        end, 100)
      end,
    },
  })
end

function M.pick_markdown() M.pick("markdown") end
function M.pick_latex()    M.pick("latex")    end

--- Replace the citation key under the cursor with a new one chosen from the picker.
function M.replace()
  local info = M.get_citation_under_cursor()
  if not info then
    vim.notify("citeref: cursor is not on a citation", vim.log.levels.WARN)
    return
  end

  local bib_files = resolve_bib_files()
  local entries   = {}
  for _, path in ipairs(bib_files) do
    vim.list_extend(entries, M.parse_bib(path))
  end
  if #entries == 0 then
    vim.notify("citeref: no citations found in bib files", vim.log.levels.WARN)
    return
  end

  local ctx    = util.save_context()
  local lookup = {}

  require("fzf-lua").fzf_exec(function(cb)
    for _, e in ipairs(entries) do
      local d = display_line(e)
      if e.key == info.key then d = d .. " (current)" end
      lookup[d] = e
      cb(d)
    end
    cb()
  end, {
    prompt    = "replace with> ",
    previewer = make_previewer(entries),
    winopts   = { title = " Replace @" .. info.key .. " " },
    actions   = {
      ["default"] = function(selected)
        if #selected == 0 then return end
        local e = lookup[selected[1]]
        if not e or e.key == info.key then
          vim.defer_fn(function()
            vim.notify("citeref: same citation selected – no change", vim.log.levels.INFO)
          end, 100)
          return
        end

        if not vim.api.nvim_buf_is_valid(ctx.buf) then return end
        if ctx.win and vim.api.nvim_win_is_valid(ctx.win) then
          pcall(vim.api.nvim_set_current_win, ctx.win)
        end
        pcall(vim.api.nvim_set_current_buf, ctx.buf)

        local replacement = info.style == "latex" and e.key or ("@" .. e.key)
        local ok = pcall(function()
          vim.api.nvim_buf_set_text(
            ctx.buf, ctx.row - 1,
            info.start_col, info.end_col + 1,
            { replacement }
          )
        end)
        if ok then
          util.set_cursor_after(ctx.buf, ctx.win, ctx.row, info.start_col, replacement)
          if ctx.was_insert_mode then
            util.reenter_insert(ctx.buf, ctx.win, ctx.row, info.start_col, #replacement)
          end
          vim.defer_fn(function()
            vim.notify(string.format("citeref: %s → %s", info.key, e.key), vim.log.levels.INFO)
          end, 100)
        else
          vim.defer_fn(function()
            vim.notify("citeref: replacement failed", vim.log.levels.ERROR)
          end, 100)
        end
      end,
    },
  })
end

return M
