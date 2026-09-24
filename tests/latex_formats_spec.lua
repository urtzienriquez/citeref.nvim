-- tests/latex_formats_spec.lua
-- Tests for lua/citeref/latex_formats.lua

local assert = require("luassert")

describe("latex_formats", function()
  local formats = require("citeref.latex_formats")

  it("is a non-empty list", function()
    assert.is_table(formats)
    assert.is_true(#formats > 0)
  end)

  it("every entry has a 'cmd' string", function()
    for _, f in ipairs(formats) do
      assert.is_string(f.cmd)
      assert.is_true(#f.cmd > 0)
    end
  end)

  it("every entry has a 'label' string", function()
    for _, f in ipairs(formats) do
      assert.is_string(f.label)
      assert.is_true(#f.label > 0)
    end
  end)

  it("label matches the pattern \\cmd{}", function()
    for _, f in ipairs(formats) do
      local expected = "\\" .. f.cmd .. "{}"
      assert.equals(expected, f.label, "mismatch for cmd: " .. f.cmd)
    end
  end)

  it("contains the standard set of commands", function()
    local cmds = {}
    for _, f in ipairs(formats) do
      cmds[f.cmd] = true
    end
    local expected = {
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
    for _, c in ipairs(expected) do
      assert.truthy(cmds[c], "missing command: " .. c)
    end
  end)

  it("has no duplicate cmd values", function()
    local seen = {}
    for _, f in ipairs(formats) do
      assert.is_nil(seen[f.cmd], "duplicate cmd: " .. f.cmd)
      seen[f.cmd] = true
    end
  end)

  describe("format", function()
    it("joins keys with ',' and no spaces", function()
      assert.equals("\\citep{a,b}", formats.format({ "a", "b" }, "citep"))
    end)
  end)

  describe("join", function()
    it("joins keys with ',' and no spaces", function()
      assert.equals("a,b,c", formats.join({ "a", "b", "c" }))
      assert.equals("", formats.join({}))
    end)
  end)

  describe("enclosing_cite", function()
    local line = "See \\citep{a, b} and \\ref{x} or \\textcite{c}."
    --            0123 4567890123456789

    it("finds the cite when the cursor is inside the keys", function()
      local c = formats.enclosing_cite(line, 12)
      assert.equals("citep", c.cmd)
      assert.same({ "a", "b" }, c.keys)
      assert.equals(4, c.start_col)
      assert.equals(10, c.open_col)
      assert.equals(15, c.close_col)
    end)

    it("matches on the backslash and on the closing brace in normal mode", function()
      assert.equals("citep", formats.enclosing_cite(line, 4).cmd)
      assert.equals("citep", formats.enclosing_cite(line, 15).cmd)
    end)

    it("does not match before the backslash in insert mode", function()
      assert.is_nil(formats.enclosing_cite(line, 4, true))
      assert.equals("citep", formats.enclosing_cite(line, 15, true).cmd)
    end)

    it("returns nil outside any cite and for non-cite commands", function()
      assert.is_nil(formats.enclosing_cite(line, 1))
      assert.is_nil(formats.enclosing_cite(line, 17))
      assert.is_nil(formats.enclosing_cite(line, 25))
    end)

    it("picks the right cite when there are several on a line", function()
      local c = formats.enclosing_cite(line, #line - 3)
      assert.equals("textcite", c.cmd)
      assert.same({ "c" }, c.keys)
    end)

    it("skips optional [...] arguments", function()
      local c = formats.enclosing_cite("\\parencite[see][p.~5]{a}", 22)
      assert.equals("parencite", c.cmd)
      assert.same({ "a" }, c.keys)
    end)

    it("handles empty braces", function()
      local c = formats.enclosing_cite("\\cite{}", 6)
      assert.same({}, c.keys)
      assert.equals(6, c.close_col)
    end)

    it("handles an unclosed brace", function()
      local c = formats.enclosing_cite("text \\cite{a, ", 14, true)
      assert.equals("cite", c.cmd)
      assert.is_nil(c.close_col)
      assert.same({ "a" }, c.keys)
    end)
  end)

  describe("merge_keys", function()
    it("appends new keys after the existing ones", function()
      assert.same({ "a", "b", "c", "d" }, formats.merge_keys({ "a", "b" }, { "c", "d" }))
      assert.same({ "c" }, formats.merge_keys({}, { "c" }))
    end)

    it("skips keys already present", function()
      assert.same({ "a", "b", "c" }, formats.merge_keys({ "a", "b" }, { "b", "c" }))
    end)

    it("returns nil when every key is already cited", function()
      assert.is_nil(formats.merge_keys({ "a", "b" }, { "a" }))
    end)
  end)

  describe("replace_key", function()
    it("swaps the key in place", function()
      assert.same({ "a", "d", "c" }, formats.replace_key({ "a", "b", "c" }, "b", "d"))
    end)

    it("does not duplicate a key already in the list", function()
      assert.same({ "c", "b" }, formats.replace_key({ "a", "b", "c" }, "a", "c"))
    end)
  end)
end)
