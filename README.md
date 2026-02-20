# citeref.nvim

A Neovim plugin for inserting **citations** (from `.bib` files) and **cross-references** (to R/Quarto code chunks).

---

## Requirements

- At least one of:
  - [fzf-lua](https://github.com/ibhagwan/fzf-lua) — full fuzzy picker with preview (preferred)
  - [blink.cmp](https://github.com/Saghen/blink.cmp) — completion menu
  - [nvim-cmp](https://github.com/hrsh7th/nvim-cmp) — completion menu

If none are installed the plugin warns and does nothing.

---

## How it works

citeref self-activates via a `FileType` autocommand — **`setup()` is optional**. When you open a supported filetype, the plugin attaches to that buffer and sets buffer-local keymaps. No external modules are loaded at this point.

The backend is resolved lazily on your **first keypress**, not at startup:

1. If you set `backend` in `setup()`, that value is used unconditionally.
2. Otherwise, citeref auto-detects by trying `fzf-lua` → `blink.cmp` → `nvim-cmp` in that order, stopping at the first one found. fzf-lua does not need to be loaded at startup — just installed — to be picked up.

**fzf-lua** gives you a full fuzzy picker with preview, working in both insert and normal mode. **blink.cmp** and **nvim-cmp** provide a completion menu and work in insert mode only — normal-mode keymaps will warn if fzf-lua is not the active backend.

Without `setup()`, only `*.bib` files in the **current working directory** are used for citations. Set `bib_files` in `setup()` to include a global library.

---

## Installation

### lazy.nvim

```lua
{
  "urtzienriquez/citeref.nvim",
  ft = { "markdown", "rmd", "quarto", "rnoweb", "pandoc", "tex", "latex" },
  -- No dependencies declaration needed. The backend is auto-detected at first
  -- use from whatever is installed, even if lazy-loaded.
  -- setup() is optional — only needed to override defaults.
  config = function()
    require("citeref").setup({
      bib_files = { "/path/to/your/library.bib" },
    })
  end,
}
```

If you do **not** use fzf-lua at all, set the backend explicitly to avoid the auto-detection trying (and loading) fzf-lua first:

```lua
require("citeref").setup({
  backend   = "blink",   -- or "cmp" or "fzf"
  bib_files = { "/path/to/your/library.bib" },
})
```

### blink.cmp source

To get citations appearing automatically when you type `@`, register citeref as a blink.cmp provider. Using `per_filetype` is recommended so the source only activates in relevant files:

```lua
-- in your blink.cmp config:
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

`per_filetype` only controls where `@` auto-triggers the completion menu. The keymaps (`<C-a>m` etc.) are independent and always active in supported filetypes regardless of this setting.

### nvim-cmp source

```lua
-- in your nvim-cmp config:
sources = cmp.config.sources({
  { name = "nvim_lsp" },
  { name = "citeref" },
})
```

The source registers itself on first use — no extra setup needed beyond adding it to your sources list.

---

## Configuration (optional)

All options have defaults. Call `setup()` only to override them.

```lua
require("citeref").setup({

  -- Backend to use for picking and inserting.
  -- "fzf"   → fzf-lua: full picker with preview, insert + normal mode
  -- "blink" → blink.cmp: completion menu, insert mode only
  -- "cmp"   → nvim-cmp: completion menu, insert mode only
  -- nil     → auto-detect at first keypress: fzf-lua > blink.cmp > nvim-cmp
  backend = nil,

  -- Filetypes where citeref activates.
  filetypes = {
    "markdown", "rmd", "quarto", "rnoweb", "pandoc", "tex", "latex",
  },

  -- .bib files for citations.
  --
  -- Without setup(), only *.bib files in the current working directory are used.
  -- Configured files are ADDITIVE — cwd *.bib files are always included too.
  --
  -- Accepts:
  --   string[]       → explicit paths (~ expanded; missing files warned once)
  --   fun():string[] → function called each time a picker opens (dynamic)
  bib_files = { "/path/to/your/library.bib" },

  keymaps = {
    -- Set to false to disable all default keymaps.
    enabled = true,

    -- Each action has an insert-mode (_i) and normal-mode (_n) variant.
    -- Set any to false to disable that individual mapping.
    -- Normal-mode keymaps require fzf-lua; they warn if not available.
    cite_markdown_i   = "<C-a>m",      -- insert @key              (insert mode)
    cite_markdown_n   = "<leader>am",  -- insert @key              (normal mode)
    cite_latex_i      = "<C-a>l",      -- insert \cite{key}        (insert mode)
    cite_latex_n      = "<leader>al",  -- insert \cite{key}        (normal mode)
    cite_replace_n    = "<leader>ar",  -- replace key under cursor (normal only)
    crossref_figure_i = "<C-a>f",      -- \@ref(fig:X)             (insert mode)
    crossref_figure_n = "<leader>af",  -- \@ref(fig:X)             (normal mode)
    crossref_table_i  = "<C-a>t",      -- \@ref(tab:X)             (insert mode)
    crossref_table_n  = "<leader>at",  -- \@ref(tab:X)             (normal mode)
  },

  -- fzf-lua picker appearance (ignored when using blink/cmp)
  picker = {
    layout       = "vertical",
    preview_size = "50%",
  },
})
```

### Overriding individual keymaps

Keymaps are buffer-local and set on first attach. To override them, disable defaults and define your own:

```lua
require("citeref").setup({ keymaps = { enabled = false } })

vim.api.nvim_create_autocmd("FileType", {
  pattern  = { "markdown", "quarto", "rmd" },
  callback = function()
    local cr = require("citeref")
    vim.keymap.set("i", "<M-c>", cr.cite_markdown,   { buffer = true })
    vim.keymap.set("i", "<M-r>", cr.crossref_figure, { buffer = true })
  end,
})
```

---

## Default keymaps

| Mode   | Key           | Action                                | Requires    |
|--------|---------------|---------------------------------------|-------------|
| insert | `<C-a>m`      | Insert citation `@key`                | any backend |
| normal | `<leader>am`  | Insert citation `@key`                | fzf-lua     |
| insert | `<C-a>l`      | Insert citation `\cite{key}`          | any backend |
| normal | `<leader>al`  | Insert citation `\cite{key}`          | fzf-lua     |
| normal | `<leader>ar`  | Replace citation under cursor         | fzf-lua     |
| insert | `<C-a>f`      | Insert figure crossref `\@ref(fig:X)` | any backend |
| normal | `<leader>af`  | Insert figure crossref `\@ref(fig:X)` | fzf-lua     |
| insert | `<C-a>t`      | Insert table crossref `\@ref(tab:X)`  | any backend |
| normal | `<leader>at`  | Insert table crossref `\@ref(tab:X)`  | fzf-lua     |

Normal-mode keymaps with a completion backend show a warning — there is no picker equivalent for normal mode without fzf-lua.

---

## Bib file resolution

Without `setup()`, citeref scans only `*.bib` files in the current working directory. If none are found it warns once when you trigger a citation.

With `setup({ bib_files = { ... } })`, the configured files are merged with any cwd `*.bib` files (duplicates removed). Missing configured files produce a one-time warning.

```lua
-- Static global library + any project-local .bib automatically included
require("citeref").setup({
  bib_files = { "/path/to/your/library.bib" },
})

-- Dynamic: re-evaluated on every picker open
require("citeref").setup({
  bib_files = function()
    return vim.fn.globpath(vim.fn.getcwd(), "**/*.bib", false, true)
  end,
})
```

---

## Cross-references

The crossref pickers scan R/Quarto code chunks in:

1. The **current buffer**
2. All `*.{rmd,Rmd,qmd,Qmd}` files in the same directory

Named chunks can be inserted as `\@ref(fig:label)` or `\@ref(tab:label)`. The `fig` vs `tab` prefix is your choice — citeref inserts whichever keymap you trigger. Unnamed chunks appear in the list with a warning label; selecting one produces a notification telling you to add a label first.

````markdown
```{r myplot, fig.cap="My caption"}
# referenced as \@ref(fig:myplot) or \@ref(tab:myplot)
```

```{r}
# unnamed — add a label to use this chunk in a cross-reference
```
````

---

## Startup cost

citeref is designed to have zero startup impact:

- `plugin/citeref.lua` only registers a `FileType` autocmd — no modules load.
- On buffer attach, only `citeref.config` and `citeref.init` load (tiny pure-Lua, no external dependencies).
- The backend loads on your **first keypress**. With explicit `backend` config only that plugin is touched; with auto-detection each candidate is tried once in order and the result is cached for the rest of the session.

---

## Programmatic API

```lua
local citeref = require("citeref")

citeref.cite_markdown()   -- insert @key
citeref.cite_latex()      -- insert \cite{key}
citeref.cite_replace()    -- replace citation key under cursor (fzf-lua only)
citeref.crossref_figure() -- insert \@ref(fig:label)
citeref.crossref_table()  -- insert \@ref(tab:label)

citeref.debug()           -- print backend, attachment status, and active keymaps
```

---

## License

GNU General Public License v3.0 — see [LICENSE](LICENSE).
