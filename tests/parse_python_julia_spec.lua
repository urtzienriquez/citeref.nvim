-- tests/parse_python_julia_spec.lua
-- Tests for Python and Julia code chunk parsing in Quarto documents.
-- Mirrors the structure of the existing qmd describe block in parse_spec.lua.

local assert = require("luassert")
local parse = require("citeref.parse")

local FIXTURES = "tests/fixtures/"

-- ─────────────────────────────────────────────────────────────
-- Python chunks
-- ─────────────────────────────────────────────────────────────

describe("chunk parsing from qmd file (Python chunks)", function()
  local chunks

  before_each(function()
    local path = FIXTURES .. "sample_python.qmd"
    local buf = vim.api.nvim_create_buf(false, true)
    local lines = vim.fn.readfile(path)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].filetype = "quarto"
    vim.api.nvim_buf_set_name(buf, path)
    vim.api.nvim_set_current_buf(buf)

    local all = parse.load_chunks()
    chunks = {}
    for _, c in ipairs(all) do
      if c.is_current then
        chunks[#chunks + 1] = c
      end
    end
  end)

  after_each(function()
    local buf = vim.fn.bufnr(vim.fn.fnamemodify(FIXTURES .. "sample_python.qmd", ":p"))
    if buf ~= -1 then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end)

  it("finds all chunks in the python qmd file", function()
    -- fig-scatter, tbl-summary, unnamed, fig-hist = 4
    assert.equals(4, #chunks)
  end)

  it("reads #| label: labels from python chunks", function()
    local labels = {}
    for _, c in ipairs(chunks) do
      labels[#labels + 1] = c.label
    end
    assert.truthy(vim.tbl_contains(labels, "fig-scatter"))
    assert.truthy(vim.tbl_contains(labels, "tbl-summary"))
    assert.truthy(vim.tbl_contains(labels, "fig-hist"))
  end)

  it("marks the unlabelled python chunk as unnamed", function()
    local unnamed = vim.tbl_filter(function(c)
      return c.label == ""
    end, chunks)
    assert.equals(1, #unnamed)
  end)

  it("stores the correct file path for python chunks", function()
    assert.matches("sample_python%.qmd", chunks[1].file)
  end)

  it("stores a positive line number for each python chunk", function()
    for _, c in ipairs(chunks) do
      assert.is_true(c.line > 0)
    end
  end)

  it("stores the chunk fence header line", function()
    for _, c in ipairs(chunks) do
      assert.matches("^```{python}", c.header)
    end
  end)

  it("formats crossrefs as @label for quarto python buffers", function()
    local bufnr = vim.api.nvim_get_current_buf()
    assert.equals("@fig-scatter", parse.format_crossref("fig", "fig-scatter", bufnr))
    assert.equals("@tbl-summary", parse.format_crossref("tab", "tbl-summary", bufnr))
  end)
end)

-- ─────────────────────────────────────────────────────────────
-- Julia chunks
-- ─────────────────────────────────────────────────────────────

describe("chunk parsing from qmd file (Julia chunks)", function()
  local chunks

  before_each(function()
    local path = FIXTURES .. "sample_julia.qmd"
    local buf = vim.api.nvim_create_buf(false, true)
    local lines = vim.fn.readfile(path)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].filetype = "quarto"
    vim.api.nvim_buf_set_name(buf, path)
    vim.api.nvim_set_current_buf(buf)

    local all = parse.load_chunks()
    chunks = {}
    for _, c in ipairs(all) do
      if c.is_current then
        chunks[#chunks + 1] = c
      end
    end
  end)

  after_each(function()
    local buf = vim.fn.bufnr(vim.fn.fnamemodify(FIXTURES .. "sample_julia.qmd", ":p"))
    if buf ~= -1 then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end)

  it("finds all chunks in the julia qmd file", function()
    -- fig-lineplot, tbl-data, unnamed, fig-histogram = 4
    assert.equals(4, #chunks)
  end)

  it("reads #| label: labels from julia chunks", function()
    local labels = {}
    for _, c in ipairs(chunks) do
      labels[#labels + 1] = c.label
    end
    assert.truthy(vim.tbl_contains(labels, "fig-lineplot"))
    assert.truthy(vim.tbl_contains(labels, "tbl-data"))
    assert.truthy(vim.tbl_contains(labels, "fig-histogram"))
  end)

  it("marks the unlabelled julia chunk as unnamed", function()
    local unnamed = vim.tbl_filter(function(c)
      return c.label == ""
    end, chunks)
    assert.equals(1, #unnamed)
  end)

  it("stores the correct file path for julia chunks", function()
    assert.matches("sample_julia%.qmd", chunks[1].file)
  end)

  it("stores a positive line number for each julia chunk", function()
    for _, c in ipairs(chunks) do
      assert.is_true(c.line > 0)
    end
  end)

  it("stores the chunk fence header line", function()
    for _, c in ipairs(chunks) do
      assert.matches("^```{julia}", c.header)
    end
  end)

  it("formats crossrefs as @label for quarto julia buffers", function()
    local bufnr = vim.api.nvim_get_current_buf()
    assert.equals("@fig-lineplot", parse.format_crossref("fig", "fig-lineplot", bufnr))
    assert.equals("@tbl-data", parse.format_crossref("tab", "tbl-data", bufnr))
  end)
end)

-- ─────────────────────────────────────────────────────────────
-- Mixed-language document (R + Python + Julia in one file)
-- ─────────────────────────────────────────────────────────────

describe("chunk parsing from mixed-language qmd buffer", function()
  local chunks

  before_each(function()
    -- Build an in-memory buffer with R, Python, and Julia chunks
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "---",
      'title: "Mixed"',
      "---",
      "",
      "```{r}",
      "#| label: fig-r-plot",
      "plot(1:10)",
      "```",
      "",
      "```{python}",
      "#| label: fig-py-plot",
      "import matplotlib.pyplot as plt",
      "plt.plot([1,2,3])",
      "plt.show()",
      "```",
      "",
      "```{julia}",
      "#| label: fig-jl-plot",
      "using Plots; plot([1,2,3])",
      "```",
      "",
      "```{python}",
      "# unnamed python chunk",
      "x = 1",
      "```",
    })
    vim.bo[buf].filetype = "quarto"
    -- Give it a temporary name so load_chunks works without sibling scanning
    vim.api.nvim_buf_set_name(buf, "/tmp/citeref_mixed_test.qmd")
    vim.api.nvim_set_current_buf(buf)

    local all = parse.load_chunks()
    chunks = {}
    for _, c in ipairs(all) do
      if c.is_current then
        chunks[#chunks + 1] = c
      end
    end
  end)

  after_each(function()
    local buf = vim.fn.bufnr("/tmp/citeref_mixed_test.qmd")
    if buf ~= -1 then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end)

  it("finds all chunks across R, Python, and Julia", function()
    -- fig-r-plot, fig-py-plot, fig-jl-plot, unnamed python = 4
    assert.equals(4, #chunks)
  end)

  it("collects labels from all three languages", function()
    local labels = {}
    for _, c in ipairs(chunks) do
      labels[#labels + 1] = c.label
    end
    assert.truthy(vim.tbl_contains(labels, "fig-r-plot"))
    assert.truthy(vim.tbl_contains(labels, "fig-py-plot"))
    assert.truthy(vim.tbl_contains(labels, "fig-jl-plot"))
  end)

  it("marks only the unnamed chunk as having an empty label", function()
    local unnamed = vim.tbl_filter(function(c)
      return c.label == ""
    end, chunks)
    assert.equals(1, #unnamed)
  end)
end)
