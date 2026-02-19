# citeref.nvim

A Neovim plugin for inserting **citations** (from `.bib` files) and **cross-references** (to R/Quarto code chunks) using [fzf-lua](https://github.com/ibhagwan/fzf-lua).

---

## Design

`citeref.nvim` lazy-loads itself through Neovim's native `FileType` autocommand machinery.  
**You do not need to call `setup()`** — just install the plugin and it activates automatically for the right filetypes. `setup()` exists only to override defaults.

---

## Requirements

- [fzf-lua](https://github.com/ibhagwan/fzf-lua)
- A `.bib` file (default: `~/Documents/zotero.bib` and/or `*.bib` in cwd)

---

## Installation

### lazy.nvim

```lua
{
  "urtzienriquez/citeref.nvim",
  ft  = { "markdown", "rmd", "quarto", "rnoweb", "pandoc", "tex", "latex" },
  dependencies = { "ibhagwan/fzf-lua" },
}
```

The `ft` trigger tells lazy.nvim to load the plugin (add `lua/` to rtp and fire
the first FileType event) only when you open a matching file. The `plugin/`
entry point is sourced at startup but is intentionally near-empty — no modules
are required, no keymaps are set — so there is no cost until you actually open a
relevant file.

If you use `setup()` to customise options, call it before any matching file is
opened (e.g. in your lazy `config` callback):

```lua
{
  "urtzienriquez/citeref.nvim",
  ft   = { "markdown", "rmd", "quarto", "rnoweb", "pandoc", "tex", "latex" },
  dependencies = { "ibhagwan/fzf-lua" },
  config = function()
    require("citeref").setup({
      bib_files = { "~/Documents/zotero.bib" },
    })
  end,
}
```

---

## Configuration (optional)

Call `setup()` anywhere in your config **before** opening a relevant buffer — or not at all.

```lua
require("citeref").setup({
  -- Filetypes where citeref activates. Default shown below.
  filetypes = {
    "markdown", "rmd", "quarto", "jmd", "pandoc", "tex", "latex",
  },

  -- Bib file(s) to search for citations.
  -- Accepts:
  --   nil            → scan cwd for *.bib files; warns if none found  (default)
  --   string[]       → explicit list of paths (~ expanded, warns on missing files)
  --   fun():string[] → called each time a picker opens (dynamic resolution)
  --
  -- Recommended: point this at your main library:
  bib_files = { "~/Documents/zotero.bib" },

  keymaps = {
    -- Set to false to disable ALL default keymaps.
    enabled = true,

    -- Each action has a separate insert-mode (_i) and normal-mode (_n) key.
    -- Set either to false to disable just that one mapping.
    cite_markdown_i   = "<C-a>m",      -- insert @key        (insert mode)
    cite_markdown_n   = "<leader>am",  -- insert @key        (normal mode)
    cite_latex_i      = "<C-a>l",      -- insert \cite{key}  (insert mode)
    cite_latex_n      = "<leader>al",  -- insert \cite{key}  (normal mode)
    cite_replace_n    = "<leader>ar",  -- replace key under cursor (normal only)
    crossref_figure_i = "<C-a>f",      -- \@ref(fig:X)       (insert mode)
    crossref_figure_n = "<leader>af",  -- \@ref(fig:X)       (normal mode)
    crossref_table_i  = "<C-a>t",      -- \@ref(tab:X)       (insert mode)
    crossref_table_n  = "<leader>at",  -- \@ref(tab:X)       (normal mode)
  },

  picker = {
    layout       = "vertical",
    preview_size = "50%",
  },
})
```

### Overriding a single keymap

Because keymaps are **buffer-local** and set only when a buffer with a matching
filetype is opened, you can override them either:

**Before the plugin sets them** (in your own `FileType` autocommand):

```lua
vim.api.nvim_create_autocmd("FileType", {
  pattern  = { "markdown", "quarto" },
  priority = 1000,          -- higher than citeref's default
  callback = function()
    vim.keymap.set("i", "<C-a>m", require("citeref").cite_markdown, { buffer = true })
  end,
})
```

**Or simply disable defaults and map freely:**

```lua
require("citeref").setup({
  keymaps = { enabled = false },
})

-- Then set your own wherever you like:
vim.keymap.set("i", "<M-c>", require("citeref").cite_markdown)
```

---

## Default Keymaps

| Mode   | Key              | Action                              |
|--------|------------------|-------------------------------------|
| insert | `<C-a>m`         | Insert citation (markdown `@key`)   |
| normal | `<leader>am`     | Insert citation (markdown `@key`)   |
| insert | `<C-a>l`         | Insert citation (LaTeX `\cite{}`)   |
| normal | `<leader>al`     | Insert citation (LaTeX `\cite{}`)   |
| normal | `<leader>ar`     | Replace citation under cursor       |
| insert | `<C-a>f`         | Insert figure crossref `\@ref(fig:X)` |
| normal | `<leader>af`     | Insert figure crossref `\@ref(fig:X)` |
| insert | `<C-a>t`         | Insert table crossref `\@ref(tab:X)`  |
| normal | `<leader>at`     | Insert table crossref `\@ref(tab:X)`  |

All keymaps are **buffer-local** (only active in matching filetypes) and each has
its own config key (`cite_markdown_i`, `cite_markdown_n`, etc.) so you can
remap or disable them individually.

---

## API

All functions are also accessible programmatically:

```lua
local citeref = require("citeref")

citeref.cite_markdown()   -- open picker → insert @key
citeref.cite_latex()      -- open picker → insert \cite{key}
citeref.cite_replace()    -- open picker → replace key under cursor
citeref.crossref_figure() -- open picker → insert \@ref(fig:label)
citeref.crossref_table()  -- open picker → insert \@ref(tab:label)
```

---

## Bib file auto-detection

By default, citeref looks for:

1. `~/Documents/zotero.bib` (if it exists)
2. Any `*.bib` file in the current working directory

You can supply an explicit list or a function:

```lua
-- Static list
require("citeref").setup({
  bib_files = {
    "~/papers/refs.bib",
    "~/Documents/zotero.bib",
  },
})

-- Dynamic: re-evaluated every time a picker opens
require("citeref").setup({
  bib_files = function()
    return vim.fn.globpath(vim.fn.getcwd(), "**/*.bib", false, true)
  end,
})
```

---

## Cross-references

The cross-reference picker (`crossref_figure`, `crossref_table`) scans R/Quarto
code chunks labelled as:

```markdown
```{r fig-myplot, fig.cap="..."}
```

It searches the **current buffer** first, then all `*.{rmd,Rmd,qmd,Qmd}` files
in the same directory.  Non-current-file results are shown with their filename.

---

## License

GNU General Public License v3.0
