# citeref.nvim

A Neovim plugin for inserting **citations** (from `.bib` files) and **cross-references** (to R/Quarto code chunks).

Supports [fzf-lua](https://github.com/ibhagwan/fzf-lua) (preferred picker), [blink.cmp](https://github.com/Saghen/blink.cmp), and [nvim-cmp](https://github.com/hrsh7th/nvim-cmp) as backends. At least one of these must be installed.

---

## Requirements

- At least one of:
  - [fzf-lua](https://github.com/ibhagwan/fzf-lua) — full picker with preview (preferred)
  - [blink.cmp](https://github.com/Saghen/blink.cmp) — completion menu fallback
  - [nvim-cmp](https://github.com/hrsh7th/nvim-cmp) — completion menu fallback

If none of the above are installed the plugin will warn once and stay inactive.

---

## How it works

citeref self-activates via a `FileType` autocommand — **you do not need to call `setup()`**. When you open a supported filetype, the plugin attaches to that buffer and sets buffer-local keymaps.

Without `setup()`, only `*.bib` files in the **current working directory** are used for citations. To include a global library (e.g. Zotero), call `setup()` with `bib_files`.

Backend priority at runtime:

1. **fzf-lua** — full fuzzy picker with preview, works in both insert and normal mode
2. **blink.cmp** — completion menu, insert mode only
3. **nvim-cmp** — completion menu, insert mode only

---

## Installation

### lazy.nvim

```lua
{
  "urtzienriquez/citeref.nvim",
  ft           = { "markdown", "rmd", "quarto", "rnoweb", "pandoc", "tex", "latex" },
  dependencies = { "ibhagwan/fzf-lua" },  -- remove if not using fzf-lua
  config = function() -- config / setup() is optional; call it only if you need to override defaults.
    require("citeref").setup({
      bib_files = { "/path/to/you/library.bib" },
    })
  end,
}
```

If you use blink.cmp or nvim-cmp as your backend, drop `fzf-lua` from `dependencies` and add the appropriate completion source config below.

### blink.cmp source

Register the source in your blink.cmp config so citations appear when you type `@`, in addition to being available via the keymaps:

```lua
-- Recommended: per-filetype so citations only appear in relevant files
sources = {
  default = { "lsp", "path", "snippets", "buffer" },
  providers = {
    citeref = {
      name   = "citeref",
      module = "citeref.completion",
    },
  },
  per_filetype = {
    markdown = { inherit_defaults = true, "citeref" },
    rmd      = { inherit_defaults = true, "citeref" },
    quarto   = { inherit_defaults = true, "citeref" },
    tex      = { inherit_defaults = true, "citeref" },
    latex    = { inherit_defaults = true, "citeref" },
  },
},
```

Note: `per_filetype` controls where `@` auto-triggers citations. The keymaps (`<C-a>m` etc.) are independent and always active in supported filetypes regardless of this setting.

### nvim-cmp source (experimental)

```lua
sources = cmp.config.sources({
  { name = "nvim_lsp" },
  { name = "citeref" },
  -- ...
})
```

The source is registered automatically when citeref attaches to a buffer.

---

## Configuration (optional)

All options have sane defaults. Call `setup()` only to override them.

```lua
require("citeref").setup({

  -- Filetypes where citeref activates.
  filetypes = {
    "markdown", "rmd", "quarto", "rnoweb", "pandoc", "tex", "latex",
  },

  -- .bib files to search for citations.
  --
  -- Without setup(), only *.bib files in the current working directory
  -- are used. Call setup() with bib_files to add a global library.
  --
  -- Accepts:
  --   string[]       → explicit paths (~ expanded; missing files warned)
  --   fun():string[] → function called each time a picker opens
  --
  -- Configured files are ADDITIVE with cwd *.bib — both are always used.
  bib_files = { "/path/to/you/library.bib" },

  keymaps = {
    -- Set to false to disable ALL default keymaps.
    enabled = true,

    -- Each action has a separate insert-mode (_i) and normal-mode (_n) key.
    -- Set any key to false to disable just that mapping.
    -- Normal-mode keymaps require fzf-lua; they warn if it is absent.
    cite_markdown_i   = "<C-a>m",      -- insert @key            (insert mode)
    cite_markdown_n   = "<leader>am",  -- insert @key            (normal mode)
    cite_latex_i      = "<C-a>l",      -- insert \cite{key}      (insert mode)
    cite_latex_n      = "<leader>al",  -- insert \cite{key}      (normal mode)
    cite_replace_n    = "<leader>ar",  -- replace key under cursor (normal only)
    crossref_figure_i = "<C-a>f",      -- \@ref(fig:X)           (insert mode)
    crossref_figure_n = "<leader>af",  -- \@ref(fig:X)           (normal mode)
    crossref_table_i  = "<C-a>t",      -- \@ref(tab:X)           (insert mode)
    crossref_table_n  = "<leader>at",  -- \@ref(tab:X)           (normal mode)
  },

  -- fzf-lua picker appearance (ignored when using completion engine fallback)
  picker = {
    layout       = "vertical",
    preview_size = "50%",
  },
})
```

### Overriding a single keymap

Keymaps are buffer-local and set when the buffer is first attached. Override them by setting your own before citeref runs (higher-priority `FileType` autocmd), or by disabling defaults and mapping freely:

```lua
-- Disable all defaults and map your own
require("citeref").setup({ keymaps = { enabled = false } })

vim.api.nvim_create_autocmd("FileType", {
  pattern  = { "markdown", "quarto", "rmd" },
  callback = function()
    local cr = require("citeref")
    vim.keymap.set("i", "<M-c>", cr.cite_markdown, { buffer = true })
    vim.keymap.set("i", "<M-r>", cr.crossref_figure, { buffer = true })
  end,
})
```

---

## Default keymaps

| Mode   | Key           | Action                                | Requires       |
|--------|---------------|---------------------------------------|----------------|
| insert | `<C-a>m`      | Insert citation (`@key`)              | any backend    |
| normal | `<leader>am`  | Insert citation (`@key`)              | fzf-lua        |
| insert | `<C-a>l`      | Insert citation (`\cite{key}`)        | any backend    |
| normal | `<leader>al`  | Insert citation (`\cite{key}`)        | fzf-lua        |
| normal | `<leader>ar`  | Replace citation under cursor         | fzf-lua        |
| insert | `<C-a>f`      | Insert figure crossref `\@ref(fig:X)` | any backend    |
| normal | `<leader>af`  | Insert figure crossref `\@ref(fig:X)` | fzf-lua        |
| insert | `<C-a>t`      | Insert table crossref `\@ref(tab:X)`  | any backend    |
| normal | `<leader>at`  | Insert table crossref `\@ref(tab:X)`  | fzf-lua        |

Normal-mode keymaps without fzf-lua will show a warning instead of opening a picker — there is no completion-menu equivalent for normal mode.

---

## Bib file resolution

Without `setup()`, citeref scans `*.bib` files in the current working directory only. If none are found, it warns once when you try to insert a citation.

With `setup({ bib_files = { ... } })`, the configured files are combined with any cwd `*.bib` files (both are always used, duplicates removed).

```lua
-- Always include your main *.bib (e.g. Zotero) library plus any project-local .bib
require("citeref").setup({
  bib_files = { "/path/to/you/library.bib" },
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

The crossref pickers (`crossref_figure`, `crossref_table`) scan R/Quarto code chunks in:

1. The **current buffer**
2. All `*.{rmd,Rmd,qmd,Qmd}` files in the same directory

Named chunks are available for insertion as `\@ref(fig:label)` or `\@ref(tab:label)`. Unnamed chunks are shown in the list but cannot be cross-referenced — add a label to use them. Note that all chunks are available to insert as `fig` or `tab` - is up to you to decide which one is the appropriate.

````markdown
```{r myplot, fig.cap="My caption"}
# this chunk can be referenced as \@ref(fig:myplot)

```{r}
# unnamed – cannot be cross-referenced
````

---

## Programmatic API

```lua
local citeref = require("citeref")

citeref.cite_markdown()   -- insert @key
citeref.cite_latex()      -- insert \cite{key}
citeref.cite_replace()    -- replace citation key under cursor (fzf-lua only)
citeref.crossref_figure() -- insert \@ref(fig:label)
citeref.crossref_table()  -- insert \@ref(tab:label)

citeref.debug()           -- print attachment and keymap status for current buffer
```

---

## License

GNU General Public License v3.0 — see [LICENSE](LICENSE).
