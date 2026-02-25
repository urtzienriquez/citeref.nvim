-- tests/parse_spec.lua
-- Tests for lua/citeref/parse.lua

local assert = require("luassert")
local parse = require("citeref.parse")

local FIXTURES = "tests/fixtures/"

-- ─────────────────────────────────────────────────────────────
-- parse_bib
-- ─────────────────────────────────────────────────────────────

describe("parse_bib", function()
  local entries

  before_each(function()
    entries = parse.parse_bib(FIXTURES .. "sample.bib")
  end)

  it("returns the correct number of entries", function()
    assert.equals(5, #entries)
  end)

  it("parses the citation key", function()
    assert.equals("smith2020", entries[1].key)
    assert.equals("jones2019", entries[2].key)
    assert.equals("wang2021", entries[3].key)
  end)

  it("parses the title field", function()
    assert.equals("A Great Paper About Things", entries[1].title)
    assert.equals("The Big Book", entries[2].title)
  end)

  it("converts 'and' separators in author to semicolons", function()
    -- "Smith, John and Doe, Jane and Brown, Alice" → "Smith, John; Doe, Jane; Brown, Alice"
    assert.equals("Smith, John; Doe, Jane; Brown, Alice", entries[1].author)
  end)

  it("parses single author without mangling", function()
    assert.equals("Jones, Bob", entries[2].author)
  end)

  it("parses the year field", function()
    assert.equals("2020", entries[1].year)
    assert.equals("2019", entries[2].year)
  end)

  it("falls back to the date field when year is absent", function()
    -- wang2021 has date = {2021-06-15}, no year
    assert.equals("2021-06-15", entries[3].year)
  end)

  it("parses journaltitle", function()
    assert.equals("Journal of Great Things", entries[1].journaltitle)
  end)

  it("stores empty string for missing optional fields", function()
    -- jones2019 has no journaltitle
    assert.equals("", entries[2].journaltitle)
    -- noauthor has no author
    assert.equals("", entries[4].author)
  end)

  it("parses abstract (may span multiple lines in the bib source)", function()
    -- Value parser captures up to the end of the first line;
    -- continuation is then appended. Just verify we got something.
    assert.is_true(entries[1].abstract ~= "")
    assert.matches("great things", entries[1].abstract)
  end)

  it("handles entries with only a title and key (minimal)", function()
    local minimal = entries[5]
    assert.equals("minimal", minimal.key)
    assert.equals("Minimal Entry", minimal.title)
    assert.equals("", minimal.author)
    assert.equals("", minimal.year)
  end)

  it("accepts a single path string (not a table)", function()
    local result = parse.parse_bib(FIXTURES .. "sample.bib")
    assert.is_true(#result > 0)
  end)

  it("returns an empty table for a nonexistent file (with a warning)", function()
    local result = parse.parse_bib("/nonexistent/path/to/file.bib")
    assert.equals(0, #result)
  end)
end)

-- ─────────────────────────────────────────────────────────────
-- entry_display
-- ─────────────────────────────────────────────────────────────

describe("entry_display", function()
  it("joins key, title, and author with │", function()
    local e = {
      key = "smith2020",
      title = "Great Paper",
      author = "Smith, John",
      year = "",
      journaltitle = "",
      abstract = "",
    }
    local d = parse.entry_display(e)
    assert.equals("smith2020 │ Great Paper │ Smith, John", d)
  end)

  it("omits title when empty", function()
    local e = { key = "k", title = "", author = "A", year = "", journaltitle = "", abstract = "" }
    local d = parse.entry_display(e)
    assert.equals("k │ A", d)
  end)

  it("omits author when empty", function()
    local e = { key = "k", title = "T", author = "", year = "", journaltitle = "", abstract = "" }
    local d = parse.entry_display(e)
    assert.equals("k │ T", d)
  end)

  it("returns just the key when title and author are both empty", function()
    local e = { key = "k", title = "", author = "", year = "", journaltitle = "", abstract = "" }
    local d = parse.entry_display(e)
    assert.equals("k", d)
  end)
end)

-- ─────────────────────────────────────────────────────────────
-- entry_preview
-- ─────────────────────────────────────────────────────────────

describe("entry_preview", function()
  it("includes non-empty fields in the preview string", function()
    local e = {
      key = "k",
      title = "My Title",
      author = "Me",
      year = "2022",
      journaltitle = "JoX",
      abstract = "Short abstract.",
    }
    local preview = parse.entry_preview(e)
    assert.matches("My Title", preview)
    assert.matches("Me", preview)
    assert.matches("2022", preview)
    assert.matches("JoX", preview)
    assert.matches("Short abstract.", preview)
  end)

  it("omits sections whose value is empty", function()
    local e = { key = "k", title = "T", author = "", year = "", journaltitle = "", abstract = "" }
    local preview = parse.entry_preview(e)
    assert.matches("Title:", preview)
    assert.is_false(preview:find("Author:") ~= nil)
  end)
end)

-- ─────────────────────────────────────────────────────────────
-- format_citation
-- ─────────────────────────────────────────────────────────────

describe("format_citation", function()
  it("formats a single key as @key", function()
    assert.equals("@smith2020", parse.format_citation({ "smith2020" }))
  end)

  it("joins multiple keys with '; '", function()
    assert.equals("@a; @b; @c", parse.format_citation({ "a", "b", "c" }))
  end)
end)

-- ─────────────────────────────────────────────────────────────
-- format_crossref
-- ─────────────────────────────────────────────────────────────

describe("format_crossref", function()
  local qmd_buf, rmd_buf, md_buf

  before_each(function()
    qmd_buf = vim.api.nvim_create_buf(false, true)
    rmd_buf = vim.api.nvim_create_buf(false, true)
    md_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[qmd_buf].filetype = "quarto"
    vim.bo[rmd_buf].filetype = "rmd"
    vim.bo[md_buf].filetype = "markdown"
  end)

  after_each(function()
    vim.api.nvim_buf_delete(qmd_buf, { force = true })
    vim.api.nvim_buf_delete(rmd_buf, { force = true })
    vim.api.nvim_buf_delete(md_buf, { force = true })
  end)

  it("returns @label for quarto buffers (fig)", function()
    assert.equals("@myfig", parse.format_crossref("fig", "myfig", qmd_buf))
  end)

  it("returns @label for quarto buffers (tab)", function()
    assert.equals("@mytab", parse.format_crossref("tab", "mytab", qmd_buf))
  end)

  it("returns \\@ref(fig:label) for rmd buffers", function()
    assert.equals("\\@ref(fig:myfig)", parse.format_crossref("fig", "myfig", rmd_buf))
  end)

  it("returns \\@ref(tab:label) for rmd buffers", function()
    assert.equals("\\@ref(tab:mytab)", parse.format_crossref("tab", "mytab", rmd_buf))
  end)

  it("returns \\@ref() syntax for plain markdown buffers", function()
    assert.equals("\\@ref(fig:myfig)", parse.format_crossref("fig", "myfig", md_buf))
  end)
end)

-- ─────────────────────────────────────────────────────────────
-- citation_under_cursor
-- ─────────────────────────────────────────────────────────────

describe("citation_under_cursor", function()
  local buf

  before_each(function()
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
  end)

  after_each(function()
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  local function set_cursor_on(line_text, col)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { line_text })
    vim.api.nvim_win_set_cursor(0, { 1, col })
  end

  it("detects a markdown @key citation when cursor is on the key", function()
    set_cursor_on("See @smith2020 for details.", 5)
    local info = parse.citation_under_cursor()
    assert.is_not_nil(info)
    assert.equals("smith2020", info.key)
    assert.equals("markdown", info.style)
  end)

  it("detects a markdown citation when cursor is on the @ symbol", function()
    set_cursor_on("See @smith2020.", 4)
    local info = parse.citation_under_cursor()
    assert.is_not_nil(info)
    assert.equals("smith2020", info.key)
  end)

  it("returns nil when cursor is not on any citation", function()
    set_cursor_on("No citation here.", 0)
    local info = parse.citation_under_cursor()
    assert.is_nil(info)
  end)

  it("detects a LaTeX \\cite{key} citation", function()
    set_cursor_on("As shown in \\cite{smith2020}.", 19)
    local info = parse.citation_under_cursor()
    assert.is_not_nil(info)
    assert.equals("smith2020", info.key)
    assert.equals("latex", info.style)
    assert.equals("cite", info.cmd)
  end)

  it("detects a LaTeX \\citep{key} variant", function()
    set_cursor_on("\\citep{jones2019}", 8)
    local info = parse.citation_under_cursor()
    assert.is_not_nil(info)
    assert.equals("jones2019", info.key)
    assert.equals("citep", info.cmd)
  end)

  it("does not match \\@ crossref syntax as a citation", function()
    -- \\@ref(fig:label) should NOT be detected as a citation key
    set_cursor_on("See \\@ref(fig:myplot).", 6)
    local info = parse.citation_under_cursor()
    assert.is_nil(info)
  end)
end)

-- ─────────────────────────────────────────────────────────────
-- chunk parsing (via load_chunks / chunks_from_file internals)
-- ─────────────────────────────────────────────────────────────

describe("chunk parsing from rmd file", function()
  local chunks

  before_each(function()
    -- Use a real buffer so we can test chunks_from_buf indirectly
    -- by loading the fixture into a temp buffer.
    local path = FIXTURES .. "sample.rmd"
    local buf = vim.api.nvim_create_buf(false, true)
    local lines = vim.fn.readfile(path)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].filetype = "rmd"
    vim.api.nvim_buf_set_name(buf, path)
    vim.api.nvim_set_current_buf(buf)

    chunks = {}
    -- load_chunks also scans siblings; to keep it isolated, call parse_bib analog manually.
    -- We use load_chunks() and filter to is_current only.
    local all = require("citeref.parse").load_chunks()
    for _, c in ipairs(all) do
      if c.is_current then
        chunks[#chunks + 1] = c
      end
    end
  end)

  after_each(function()
    local buf = vim.fn.bufnr(vim.fn.fnamemodify("tests/fixtures/sample.rmd", ":p"))
    if buf ~= -1 then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end)

  it("finds the correct total number of chunks", function()
    -- setup, myplot, mytable, unnamed, second-figure = 5 chunks
    assert.equals(5, #chunks)
  end)

  it("parses inline chunk labels correctly", function()
    local labels = {}
    for _, c in ipairs(chunks) do
      labels[#labels + 1] = c.label
    end
    assert.truthy(vim.tbl_contains(labels, "setup"))
    assert.truthy(vim.tbl_contains(labels, "myplot"))
    assert.truthy(vim.tbl_contains(labels, "mytable"))
    assert.truthy(vim.tbl_contains(labels, "second-figure"))
  end)

  it("marks unnamed chunks with an empty label", function()
    local unnamed = vim.tbl_filter(function(c)
      return c.label == ""
    end, chunks)
    assert.equals(1, #unnamed)
  end)

  it("stores the correct file path", function()
    assert.matches("sample%.rmd", chunks[1].file)
  end)

  it("stores a positive line number", function()
    for _, c in ipairs(chunks) do
      assert.is_true(c.line > 0)
    end
  end)
end)

describe("chunk parsing from qmd file (YAML labels)", function()
  local chunks

  before_each(function()
    local path = FIXTURES .. "sample.qmd"
    local buf = vim.api.nvim_create_buf(false, true)
    local lines = vim.fn.readfile(path)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].filetype = "quarto"
    vim.api.nvim_buf_set_name(buf, path)
    vim.api.nvim_set_current_buf(buf)

    local all = require("citeref.parse").load_chunks()
    chunks = {}
    for _, c in ipairs(all) do
      if c.is_current then
        chunks[#chunks + 1] = c
      end
    end
  end)

  after_each(function()
    local buf = vim.fn.bufnr(vim.fn.fnamemodify("tests/fixtures/sample.qmd", ":p"))
    if buf ~= -1 then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end)

  it("finds all chunks in the qmd file", function()
    -- fig-scatter, tbl-summary, unnamed, fig-hist = 4
    assert.equals(4, #chunks)
  end)

  it("reads YAML #| label: labels", function()
    local labels = {}
    for _, c in ipairs(chunks) do
      labels[#labels + 1] = c.label
    end
    assert.truthy(vim.tbl_contains(labels, "fig-scatter"))
    assert.truthy(vim.tbl_contains(labels, "tbl-summary"))
    assert.truthy(vim.tbl_contains(labels, "fig-hist"))
  end)

  it("marks the unlabelled chunk as unnamed", function()
    local unnamed = vim.tbl_filter(function(c)
      return c.label == ""
    end, chunks)
    assert.equals(1, #unnamed)
  end)
end)
