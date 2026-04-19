-- tests/myst_formats_spec.lua

local assert = require("luassert")

describe("myst_formats", function()
  local myst

  before_each(function()
    package.loaded["citeref.myst_formats"] = nil
    myst = require("citeref.myst_formats")
  end)

  it("cycles cite:p and cite:t", function()
    assert.equals("cite:t", myst.next("cite:p").cmd)
    assert.equals("cite:p", myst.next("cite:t").cmd)
  end)

  it("formats a plain MyST citation", function()
    assert.equals("{cite:p}`smith2020`", myst.format({ "smith2020" }, "cite:p"))
  end)

  it("formats a MyST citation with prefix and suffix", function()
    assert.equals(
      "{cite:p}`{see}smith2020{fig 1}`",
      myst.format({ "smith2020" }, "cite:p", "see", "fig 1")
    )
  end)

  it("replaces one key without dropping the rest", function()
    assert.same({ "alpha", "beta", "delta" }, myst.replace_key({ "alpha", "beta", "gamma" }, "gamma", "delta"))
  end)
end)
