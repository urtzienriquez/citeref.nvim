-- tests/config_spec.lua
-- Tests for lua/citeref/config.lua

local assert = require("luassert")

describe("config", function()
  local config

  before_each(function()
    -- Re-require a fresh copy each time so state doesn't leak between tests.
    package.loaded["citeref.config"] = nil
    config = require("citeref.config")
  end)

  it("returns defaults when set() is called with no options", function()
    config.set({})
    local opts = config.get()
    assert.is_nil(opts.backend) -- nil by design; user must set it
    assert.is_table(opts.filetypes)
    assert.is_table(opts.keymaps)
    assert.is_table(opts.picker)
    assert.equals("cite", opts.default_latex_format)
  end)

  it("merges user options over defaults", function()
    config.set({ backend = "fzf", default_latex_format = "citep" })
    local opts = config.get()
    assert.equals("fzf", opts.backend)
    assert.equals("citep", opts.default_latex_format)
  end)

  it("preserves default filetypes when none are supplied", function()
    config.set({ backend = "fzf" })
    local opts = config.get()
    assert.truthy(vim.tbl_contains(opts.filetypes, "markdown"))
    assert.truthy(vim.tbl_contains(opts.filetypes, "quarto"))
    assert.truthy(vim.tbl_contains(opts.filetypes, "rmd"))
  end)

  it("preserves default keymaps when none are overridden", function()
    config.set({ backend = "fzf" })
    local km = config.get().keymaps
    assert.equals("<C-a>m", km.cite_markdown_i)
    assert.equals("<leader>am", km.cite_markdown_n)
    assert.equals("<C-a>f", km.crossref_figure_i)
    assert.equals("<C-a>t", km.crossref_table_i)
  end)

  it("allows individual keymaps to be disabled with false", function()
    config.set({ backend = "fzf", keymaps = { cite_markdown_i = false } })
    local km = config.get().keymaps
    assert.equals(false, km.cite_markdown_i)
    -- other keymaps remain at their defaults
    assert.equals("<leader>am", km.cite_markdown_n)
  end)

  it("allows keymaps to be disabled entirely", function()
    config.set({ backend = "fzf", keymaps = { enabled = false } })
    assert.equals(false, config.get().keymaps.enabled)
  end)

  it("resets an invalid default_latex_format to 'cite'", function()
    -- Suppress the warning notification during this test
    local notified = false
    local orig_notify = vim.notify
    vim.notify = function(msg, level)
      if msg:match("default_latex_format") then
        notified = true
      end
    end

    config.set({ backend = "fzf", default_latex_format = "bogus_format" })
    assert.equals("cite", config.get().default_latex_format)
    assert.is_true(notified)

    vim.notify = orig_notify
  end)

  it("accepts all valid latex formats without resetting", function()
    local valid = {
      "cite",
      "citep",
      "citet",
      "citeauthor",
      "citeyear",
      "citealt",
      "textcite",
      "parencite",
      "footcite",
      "autocite",
    }
    for _, fmt in ipairs(valid) do
      package.loaded["citeref.config"] = nil
      config = require("citeref.config")
      config.set({ backend = "fzf", default_latex_format = fmt })
      assert.equals(fmt, config.get().default_latex_format, "failed for format: " .. fmt)
    end
  end)

  it("warns (but doesn't crash) for an unknown backend", function()
    local notified = false
    local orig_notify = vim.notify
    vim.notify = function(msg, level)
      if msg:match("backend") then
        notified = true
      end
    end

    config.set({ backend = "unknown_backend" })
    assert.is_true(notified)

    vim.notify = orig_notify
  end)

  it("merges picker options without losing defaults", function()
    config.set({ backend = "fzf", picker = { layout = "horizontal" } })
    local p = config.get().picker
    assert.equals("horizontal", p.layout)
    assert.equals("50%", p.preview_size) -- default survives
  end)
end)
