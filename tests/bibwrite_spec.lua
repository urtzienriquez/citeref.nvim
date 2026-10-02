-- tests/bibwrite_spec.lua
-- Tests for lua/citeref/bibwrite.lua

local assert = require("luassert")
local bibwrite = require("citeref.bibwrite")

local function collect(fn, lines)
  local keys = {}
  fn(lines, function(k)
    keys[#keys + 1] = k
  end)
  table.sort(keys)
  return keys
end

local function write(path, text)
  local f = assert(io.open(path, "w"))
  f:write(text)
  f:close()
end

local function read(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local s = f:read("*a")
  f:close()
  return s
end

local LIBRARY = [[
@article{smith2020,
  title = {A {Great} Paper},
  author = {Smith, John},
  journaltitle = {J},
}

@inbook{chapter2021,
  title = {Chapter},
  crossref = {book2021},
}

@book{book2021,
  title = {The Book},
}

@comment{jabref-meta: x}

@article{unused2000,
  title = {Never cited},
}
]]

-- ─────────────────────────────────────────────────────────────
-- latex_keys
-- ─────────────────────────────────────────────────────────────

describe("latex_keys", function()
  it("finds keys in standard and custom cite commands", function()
    local keys = collect(bibwrite.latex_keys, {
      "as shown by \\textcite{a} and \\citep[see][p.~5]{b, c}.",
      "\\nptextcite{d} \\parencite*{e}",
    })
    assert.same({ "a", "b", "c", "d", "e" }, keys)
  end)

  it("reads every key group of multicite commands", function()
    local keys = collect(bibwrite.latex_keys, { "\\textcites(pre)(post)[p.~1]{a}[p.~2]{b,c} and text" })
    assert.same({ "a", "b", "c" }, keys)
  end)

  it("handles a key list split across lines", function()
    local keys = collect(bibwrite.latex_keys, { "\\cite{a,", "  b}" })
    assert.same({ "a", "b" }, keys)
  end)

  it("ignores comments but not escaped percent signs", function()
    local keys = collect(bibwrite.latex_keys, { "50\\% done \\cite{a} % \\cite{commented}" })
    assert.same({ "a" }, keys)
  end)

  it("skips Rnw code chunks", function()
    local keys = collect(bibwrite.latex_keys, {
      "<<setup>>=",
      'x <- "\\cite{inchunk}" # %in%',
      "@",
      "\\cite{a}",
    })
    assert.same({ "a" }, keys)
  end)

  it("reports \\nocite{*} as the key *", function()
    local keys = collect(bibwrite.latex_keys, { "\\nocite{*}" })
    assert.same({ "*" }, keys)
  end)
end)

-- ─────────────────────────────────────────────────────────────
-- markdown_keys
-- ─────────────────────────────────────────────────────────────

describe("markdown_keys", function()
  it("finds pandoc citations", function()
    local keys = collect(bibwrite.markdown_keys, {
      "See [@a, p. 3; -@b] and @c.",
      "Braced @{d.e} key.",
    })
    assert.same({ "a", "b", "c", "d.e" }, keys)
  end)

  it("ignores emails, escaped @ and code", function()
    local keys = collect(bibwrite.markdown_keys, {
      "mail me at me@example.org, see \\@ref(fig:x) and `@inline`",
      "```{julia}",
      "@time f(x)",
      "```",
      "@after",
    })
    assert.same({ "after" }, keys)
  end)

  it("finds MyST citations", function()
    local keys = collect(bibwrite.markdown_keys, { "As {cite:t}`a;b` showed." })
    assert.same({ "a", "b" }, keys)
  end)

  it("reports @* as the key *", function()
    local keys = collect(bibwrite.markdown_keys, { "nocite: '@*'" })
    assert.same({ "*" }, keys)
  end)
end)

-- ─────────────────────────────────────────────────────────────
-- read_bib_raw / linked_keys
-- ─────────────────────────────────────────────────────────────

describe("read_bib_raw", function()
  it("reads entries verbatim and skips comments", function()
    local path = vim.fn.tempname() .. ".bib"
    write(path, LIBRARY)
    local entries = bibwrite.read_bib_raw(path)
    assert.same({ "book2021", "chapter2021", "smith2020", "unused2000" }, vim.fn.sort(vim.tbl_keys(entries)))
    assert.equals(
      "@article{smith2020,\n  title = {A {Great} Paper},\n  author = {Smith, John},\n  journaltitle = {J},\n}",
      entries.smith2020
    )
  end)

  it("finds crossref targets", function()
    assert.same({ "book2021" }, bibwrite.linked_keys("@inbook{x,\n  Crossref = {book2021},\n}"))
  end)
end)

-- ─────────────────────────────────────────────────────────────
-- write_bib
-- ─────────────────────────────────────────────────────────────

describe("write_bib", function()
  local dir, lib

  before_each(function()
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    lib = vim.fn.tempname() .. ".bib"
    write(lib, LIBRARY)
    package.loaded["citeref.config"] = nil
    require("citeref.config").set({ backend = "fzf", bib_files = { lib } })
  end)

  it("writes only cited entries, their crossrefs, and reports missing keys", function()
    write(dir .. "/main.Rnw", "\\textcite{smith2020} \\cite{chapter2021,nope}")
    local res = bibwrite.write_bib({ dir = dir, silent = true })
    assert.equals(3, res.written)
    assert.same({ "nope" }, res.missing)
    local out = read(dir .. "/references.bib")
    assert.truthy(out:find("@book{book2021", 1, true))
    assert.truthy(out:find("@article{smith2020", 1, true))
    assert.falsy(out:find("unused2000", 1, true))
  end)

  it("skips the .tex knitted from an .Rnw and excluded files", function()
    write(dir .. "/main.Rnw", "\\cite{smith2020}")
    write(dir .. "/main.tex", "\\cite{unused2000}")
    write(dir .. "/main_diff.tex", "\\cite{book2021}")
    local res = bibwrite.write_bib({ dir = dir, exclude = { "_diff%.tex$" }, silent = true })
    assert.equals(1, res.written)
  end)

  it("does not report keys that are in a local .bib as missing", function()
    write(dir .. "/main.qmd", "R [@R-terra] and @smith2020")
    write(dir .. "/packages.bib", "@manual{R-terra,\n  title = {terra},\n}\n")
    local res = bibwrite.write_bib({ dir = dir, silent = true })
    assert.equals(1, res.written)
    assert.same({}, res.missing)
  end)

  it("refuses to write when the whole library is cited", function()
    write(dir .. "/main.tex", "\\nocite{*}")
    assert.is_nil(bibwrite.write_bib({ dir = dir, silent = true }))
    assert.is_nil(read(dir .. "/references.bib"))
  end)

  it("leaves the file untouched when nothing changed", function()
    write(dir .. "/main.tex", "\\cite{smith2020}")
    assert.is_true(bibwrite.write_bib({ dir = dir, silent = true }).changed)
    assert.is_false(bibwrite.write_bib({ dir = dir, silent = true }).changed)
  end)

  it("refuses to overwrite a file it did not write, unless forced", function()
    write(dir .. "/main.tex", "\\cite{smith2020}")
    local mine = "@book{mine,\n  title = {Mine},\n}\n"
    write(dir .. "/references.bib", mine)
    assert.is_nil(bibwrite.write_bib({ dir = dir, silent = true }))
    assert.equals(mine, read(dir .. "/references.bib"))
    assert.equals(1, bibwrite.write_bib({ dir = dir, silent = true, force = true }).written)
    assert.equals("ours", bibwrite.owner(dir .. "/references.bib"))
  end)
end)

-- ─────────────────────────────────────────────────────────────
-- ownership
-- ─────────────────────────────────────────────────────────────

describe("owner", function()
  it("tells absent, empty, citeref and other files apart", function()
    local f = vim.fn.tempname() .. ".bib"
    assert.equals("absent", bibwrite.owner(f))
    write(f, "")
    assert.equals("empty", bibwrite.owner(f))
    write(f, bibwrite.MARKER .. "\n\n@book{a,\n}\n")
    assert.equals("ours", bibwrite.owner(f))
    write(f, "@book{a,\n}\n")
    assert.equals("other", bibwrite.owner(f))
  end)
end)

-- ─────────────────────────────────────────────────────────────
-- sync
-- ─────────────────────────────────────────────────────────────

describe("sync", function()
  local dir, lib, buf

  before_each(function()
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    lib = vim.fn.tempname() .. ".bib"
    write(lib, LIBRARY)
    package.loaded["citeref.config"] = nil
    require("citeref.config").set({ backend = "fzf", bib_files = { lib } })
    write(dir .. "/main.tex", "\\addbibresource{references.bib}\n\\cite{smith2020}\n")
    vim.cmd.edit(dir .. "/main.tex")
    buf = vim.api.nvim_get_current_buf()
  end)

  after_each(function()
    vim.cmd("silent! bwipeout!")
  end)

  local function cite(key)
    vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "\\cite{" .. key .. "}" })
    vim.cmd("silent write")
  end

  -- create the file the way a user does, with :CiterefWriteBib
  local function create(output)
    return bibwrite.write_bib({ dir = dir, output = output, silent = true })
  end

  it("is on by default", function()
    assert.is_true(require("citeref.config").defaults.write_bib.sync)
  end)

  it("never creates a file, even one a document lists", function()
    cite("book2021")
    assert.is_nil(bibwrite.sync(buf))
    assert.is_nil(read(dir .. "/references.bib"))
  end)

  it("does not fill an empty file", function()
    write(dir .. "/references.bib", "")
    assert.is_nil(bibwrite.sync(buf))
    assert.equals("", read(dir .. "/references.bib"))
  end)

  it("never touches a references.bib that citeref did not write", function()
    local mine = "@book{mine,\n  title = {My own library},\n}\n"
    write(dir .. "/references.bib", mine)
    cite("book2021")
    assert.is_nil(bibwrite.sync(buf))
    assert.equals(mine, read(dir .. "/references.bib"))
  end)

  it("updates a file created with write_bib when a citation is added", function()
    assert.equals(1, create().written)
    cite("book2021")
    local res = bibwrite.sync(buf)
    assert.is_true(res.changed)
    assert.equals(2, res.written)
    assert.truthy(read(dir .. "/references.bib"):find("@book{book2021", 1, true))
  end)

  it("syncs a file created under another name", function()
    create("cited.bib")
    cite("book2021")
    local _, all = bibwrite.sync(buf)
    assert.truthy(all[vim.fn.fnamemodify(dir .. "/cited.bib", ":p")])
    assert.truthy(read(dir .. "/cited.bib"):find("@book{book2021", 1, true))
    assert.is_nil(read(dir .. "/references.bib"))
  end)

  it("skips the work when neither citations nor bib files changed", function()
    create()
    local reads = bibwrite.stats.bib_reads
    assert.is_true(bibwrite.sync(buf).skipped)
    vim.cmd("silent write") -- saving text without new citations
    assert.is_true(bibwrite.sync(buf).skipped)
    assert.equals(reads, bibwrite.stats.bib_reads)
  end)

  it("picks up an edited library entry", function()
    create()
    write(lib, (LIBRARY:gsub("A {Great} Paper", "A Corrected Title")))
    local res = bibwrite.sync(buf)
    assert.is_true(res.changed)
    assert.truthy(read(dir .. "/references.bib"):find("A Corrected Title", 1, true))
  end)

  it("re-scans only documents that changed", function()
    write(dir .. "/appendix.tex", "\\cite{unused2000}\n")
    create()
    local scans = bibwrite.stats.doc_scans
    write(dir .. "/appendix.tex", "\\cite{chapter2021}\n")
    local res = bibwrite.sync(buf)
    assert.equals(scans + 1, bibwrite.stats.doc_scans)
    assert.truthy(read(dir .. "/references.bib"):find("@book{book2021", 1, true))
    assert.equals(3, res.written)
  end)

  it("does not create a file when a document is opened", function()
    vim.cmd("silent edit!")
    require("citeref").attach()
    vim.wait(200)
    assert.is_nil(read(dir .. "/references.bib"))
  end)

  it("updates a citeref file when a document is opened", function()
    create()
    write(dir .. "/main.tex", "\\cite{smith2020}\n\\cite{book2021}\n")
    vim.cmd("silent edit!")
    require("citeref").attach()
    local ok = vim.wait(1000, function()
      return (read(dir .. "/references.bib") or ""):find("@book{book2021", 1, true) ~= nil
    end)
    assert.is_true(ok)
  end)

  it("runs on save in attached buffers", function()
    create()
    require("citeref").attach()
    cite("book2021")
    local ok = vim.wait(1000, function()
      local out = read(dir .. "/references.bib")
      return out ~= nil and out:find("@book{book2021", 1, true) ~= nil
    end)
    assert.is_true(ok)
  end)
end)

-- ─────────────────────────────────────────────────────────────
-- load_entries: duplicate keys
-- ─────────────────────────────────────────────────────────────

describe("load_entries", function()
  it("keeps the configured library's entry when a local .bib repeats a key", function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    local lib = vim.fn.tempname() .. ".bib"
    write(lib, "@article{dup,\n  title = {Global},\n}\n")
    write(dir .. "/references.bib", "@article{dup,\n  title = {Local},\n}\n")
    package.loaded["citeref.config"] = nil
    require("citeref.config").set({ backend = "fzf", bib_files = { lib } })
    local cwd = vim.fn.getcwd()
    vim.cmd.cd(dir)
    local entries = require("citeref.parse").load_entries()
    vim.cmd.cd(cwd)
    assert.equals(1, #entries)
    assert.equals("Global", entries[1].title)
  end)
end)
