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
end)
