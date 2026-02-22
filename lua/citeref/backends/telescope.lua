--- citeref.nvim – telescope backend
local util  = require("citeref.util")
local parse = require("citeref.parse")

local M = {}

-- ─────────────────────────────────────────────────────────────
-- Shared previewer factories
-- ─────────────────────────────────────────────────────────────

local function entry_previewer()
  return require("telescope.previewers").new_buffer_previewer({
    title = "Entry",
    define_preview = function(self, entry)
      vim.api.nvim_buf_set_lines(
        self.state.bufnr, 0, -1, false,
        vim.split(parse.entry_preview(entry.value), "\n")
      )
    end,
  })
end

local function chunk_previewer()
  local conf = require("telescope.config").values
  return require("telescope.previewers").new_buffer_previewer({
    title = "Chunk",
    define_preview = function(self, entry)
      local chunk = entry.value
      if chunk.file and chunk.file ~= "" then
        conf.buffer_previewer_maker(chunk.file, self.state.bufnr, {
          bufname  = self.state.bufname,
          winid    = self.state.winid,
          callback = function(bufnr)
            pcall(vim.api.nvim_win_set_cursor, self.state.winid, { chunk.line, 0 })
            pcall(vim.api.nvim_buf_call, bufnr, function() vim.cmd("norm! zz") end)
          end,
        })
      else
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, { chunk.header or "" })
      end
    end,
  })
end

-- ─────────────────────────────────────────────────────────────
-- Citation picker
-- ─────────────────────────────────────────────────────────────

---@param format "markdown"|"latex"
---@param entries CiterefEntry[]
---@param ctx table
function M.pick_citation(format, entries, ctx)
  local pickers      = require("telescope.pickers")
  local finders      = require("telescope.finders")
  local conf         = require("telescope.config").values
  local actions      = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local title        = format == "latex" and "Citations [LaTeX]" or "Citations [Markdown]"

  pickers.new({}, {
    prompt_title = title,
    finder = finders.new_table({
      results = entries,
      entry_maker = function(e)
        local d = parse.entry_display(e)
        return { value = e, display = d, ordinal = d }
      end,
    }),
    previewer = entry_previewer(),
    sorter    = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        local picker   = action_state.get_current_picker(prompt_bufnr)
        local selected = picker:get_multi_selection()
        if #selected == 0 then selected = { action_state.get_selected_entry() } end
        actions.close(prompt_bufnr)
        if not selected or #selected == 0 then return end

        local keys = {}
        for _, sel in ipairs(selected) do
          if sel and sel.value then keys[#keys + 1] = sel.value.key end
        end
        if #keys == 0 then return end
        table.sort(keys)

        local text = parse.format_citation(keys, format)
        util.insert_at_context(ctx, text)
        vim.defer_fn(function()
          vim.notify("citeref: inserted " .. text, vim.log.levels.INFO)
        end, 100)
      end)
      return true
    end,
  }):find()
end

-- ─────────────────────────────────────────────────────────────
-- Replace citation under cursor
-- ─────────────────────────────────────────────────────────────

---@param entries CiterefEntry[]
---@param info table
function M.replace(entries, info)
  local pickers      = require("telescope.pickers")
  local finders      = require("telescope.finders")
  local conf         = require("telescope.config").values
  local actions      = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  local buf = vim.api.nvim_get_current_buf()
  local row = vim.api.nvim_win_get_cursor(0)[1]

  pickers.new({}, {
    prompt_title = "Replace @" .. info.key,
    finder = finders.new_table({
      results = entries,
      entry_maker = function(e)
        local d = parse.entry_display(e)
        if e.key == info.key then d = d .. " (current)" end
        return { value = e, display = d, ordinal = d }
      end,
    }),
    previewer = entry_previewer(),
    sorter    = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        local sel = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if not sel or sel.value.key == info.key then
          vim.defer_fn(function()
            vim.notify("citeref: same citation selected – no change", vim.log.levels.INFO)
          end, 100)
          return
        end
        local replacement = info.style == "latex" and sel.value.key or ("@" .. sel.value.key)
        local ok, err = pcall(
          vim.api.nvim_buf_set_text,
          buf, row - 1, info.start_col, row - 1, info.end_col + 1, { replacement }
        )
        vim.defer_fn(function()
          if ok then
            vim.notify(string.format("citeref: %s → %s", info.key, sel.value.key), vim.log.levels.INFO)
          else
            vim.notify("citeref: replacement failed – " .. tostring(err), vim.log.levels.ERROR)
          end
        end, 100)
      end)
      return true
    end,
  }):find()
end

-- ─────────────────────────────────────────────────────────────
-- Crossref picker
-- ─────────────────────────────────────────────────────────────

---@param ref_type "fig"|"tab"
---@param chunks CiterefChunk[]
---@param ctx table
function M.pick_crossref(ref_type, chunks, ctx)
  local pickers      = require("telescope.pickers")
  local finders      = require("telescope.finders")
  local conf         = require("telescope.config").values
  local actions      = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local title        = ref_type == "fig" and "Figure Crossref" or "Table Crossref"

  pickers.new({}, {
    prompt_title = title,
    finder = finders.new_table({
      results = chunks,
      entry_maker = function(c)
        return { value = c, display = c.display, ordinal = c.display }
      end,
    }),
    previewer = chunk_previewer(),
    sorter    = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        local sel = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if not sel then return end
        local chunk = sel.value
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
      end)
      return true
    end,
  }):find()
end

return M
