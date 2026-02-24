<div align="center">

![citeref-logo-compact](https://github.com/user-attachments/assets/fb3b28e2-b9e9-4907-84a6-299930fc9183)

> A Neovim plugin for inserting **citations** (from `.bib` files) and **cross-references** (to R/Quarto code chunks).

</div>

Contributions are very welcomed! See [Contributing](#contributing)

---

## Requirements

- **One picker or completion backend** (required — no auto-detection):
  - [fzf-lua](https://github.com/ibhagwan/fzf-lua) — full fuzzy picker with preview
  - [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) — full fuzzy picker with preview
  - [snacks.nvim](https://github.com/folke/snacks.nvim) — full fuzzy picker with preview
  - [blink.cmp](https://github.com/Saghen/blink.cmp) — completion menu
  - [nvim-cmp](https://github.com/hrsh7th/nvim-cmp) — completion menu

The `backend` option is **required**. citeref will warn on startup if it is not set.

---

## How it works

citeref self-activates via a `FileType` autocommand — **`setup()` is optional for attachment, but required to set a backend**. When you open a supported filetype, the plugin attaches to that buffer and sets buffer-local keymaps. No external modules are loaded at this point.

The backend is loaded lazily on your **first keypress**, not at startup. Picker backends (`fzf`, `telescope`, `snacks`) work in both insert and normal mode. Completion backends (`blink`, `cmp`) provide a menu and work in insert mode only — normal-mode keymaps will warn if a picker backend is not active.

Without `setup()`, only `*.bib` files in the **current working directory** are used for citations. Set `bib_files` in `setup()` to include a global library.

---

## Installation

### lazy.nvim

```lua
{
  "urtzienriquez/citeref.nvim",
  ft = { "markdown", "rmd", "quarto", "rnoweb", "pandoc", "tex", "latex" },
  config = function()
    require("citeref").setup({
      backend   = "fzf",   -- required: "fzf" | "telescope" | "snacks" | "blink" | "cmp"
      bib_files = { "/path/to/your/library.bib" },
    })
  end,
}
```

### blink.cmp source

Register citeref as a blink.cmp provider. Note the module path points to the blink backend:

```lua
-- in your blink.cmp config:
sources = {
  default = { "lsp", "path", "snippets", "buffer" },
  providers = {
    citeref = {
      name   = "citeref",
      module = "citeref.backends.blink",
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

### nvim-cmp source

```lua
-- in your nvim-cmp config:
-- Register the source before cmp.setup() so nvim-cmp knows about it:
require("citeref.backends.cmp").register()

sources = cmp.config.sources({
  { name = "nvim_lsp" },
  { name = "citeref" },
})
```

Both completion backends only show citeref items when you type `@`.

---

## Configuration (optional)

All options have defaults. Call `setup()` to set a backend and override anything else.

```lua
require("citeref").setup({

  -- REQUIRED. No auto-detection — set one explicitly:
  --   "fzf"       → fzf-lua: full picker with preview, insert + normal mode
  --   "telescope" → telescope.nvim: full picker with preview, insert + normal mode
  --   "snacks"    → snacks.nvim: full picker with preview, insert + normal mode
  --   "blink"     → blink.cmp: completion menu, insert mode only
  --   "cmp"       → nvim-cmp: completion menu, insert mode only
  backend = "fzf",

  -- Filetypes where citeref activates.
  filetypes = {
    "markdown", "rmd", "quarto", "rnoweb", "pandoc", "tex", "latex",
  },

  -- .bib files for citations.
  -- cwd *.bib files are always included. This adds more sources on top.
  -- Accepts:
  --   string[]       → explicit paths (~ expanded; missing files warned once)
  --   fun():string[] → function called each time a picker opens (dynamic)
  bib_files = { "/path/to/your/library.bib" },

  -- Default LaTeX citation command used when the LaTeX picker opens.
  -- Press <C-l> inside the picker to cycle through all available formats.
  -- Valid values: "cite" | "citep" | "citet" | "citeauthor" | "citeyear" | "citealt"
  default_latex_format = "cite",

  keymaps = {
    -- Set to false to disable all default keymaps.
    enabled = true,

    -- Each action has an insert-mode (_i) and normal-mode (_n) variant.
    -- Set any to false to disable that individual mapping.
    -- Normal-mode keymaps require a picker backend; they warn otherwise.
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

  -- Picker appearance.
  -- `layout` meaning depends on the backend:
  --   fzf / telescope → "vertical" | "horizontal"
  --   snacks          → any snacks preset name:
  --                     "default" | "vertical" | "horizontal" | "telescope" |
  --                     "ivy" | "ivy_split" | "select" | "sidebar" | "vscode"
  -- `preview_size` is used by fzf and telescope only.
  picker = {
    layout       = "vertical",
    preview_size = "50%",
  },
})
```

### Overriding individual keymaps

```lua
require("citeref").setup({
  backend  = "fzf",
  keymaps  = { enabled = false },
})

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

| Mode   | Key           | Action                                | Requires       |
|--------|---------------|---------------------------------------|----------------|
| insert | `<C-a>m`      | Insert citation `@key`                | any backend    |
| normal | `<leader>am`  | Insert citation `@key`                | picker backend |
| insert | `<C-a>l`      | Insert citation `\cite{key}`          | any backend    |
| normal | `<leader>al`  | Insert citation `\cite{key}`          | picker backend |
| normal | `<leader>ar`  | Replace citation under cursor         | picker backend |
| insert | `<C-a>f`      | Insert figure crossref `\@ref(fig:X)` | any backend    |
| normal | `<leader>af`  | Insert figure crossref `\@ref(fig:X)` | picker backend |
| insert | `<C-a>t`      | Insert table crossref `\@ref(tab:X)`  | any backend    |
| normal | `<leader>at`  | Insert table crossref `\@ref(tab:X)`  | picker backend |

Normal-mode keymaps with a completion backend show a warning — there is no picker equivalent for normal mode without fzf-lua, telescope, or snacks.

---

## LaTeX citation formats

When using a picker backend, the LaTeX citation picker (`<C-a>l` / `<leader>al`) opens with your `default_latex_format` active (defaults to `\cite{}`). Press **`<C-l>`** inside the picker to cycle through all available formats:

| Command          | Output                    |
|------------------|---------------------------|
| `\cite{}`        | `\cite{key}`              |
| `\citep{}`       | `\citep{key}`             |
| `\citet{}`       | `\citet{key}`             |
| `\citeauthor{}`  | `\citeauthor{key}`        |
| `\citeyear{}`    | `\citeyear{key}`          |
| `\citealt{}`     | `\citealt{key}`           |
| `\textcite{}`    | `\textcite{key}`          |
| `\parencite{}`   | `\parencite{key}`         |
| `\footcite{}`    | `\footcite{key}`          |
| `\autocite{}`    | `\autocite{key}`          |

The current format is shown in the picker title. A notification confirms each cycle.

To always open on a specific format:

```lua
require("citeref").setup({
  backend              = "fzf",
  default_latex_format = "citep",
})
```

Completion backends (`blink`, `cmp`) trigger on `@` for markdown and `\cite{` for LaTeX. They do not support format cycling — the format is determined by what you type.

---

## Bib file resolution

Without `setup()`, citeref scans only `*.bib` files in the current working directory. If none are found it warns once when you trigger a citation.

With `setup({ bib_files = { ... } })`, the configured files are merged with any cwd `*.bib` files (duplicates removed). Missing configured files produce a one-time warning.

```lua
-- Static global library + any project-local .bib automatically included
require("citeref").setup({
  backend   = "fzf",
  bib_files = { "/path/to/your/library.bib" },
})

-- Dynamic: re-evaluated on every picker open
require("citeref").setup({
  backend   = "fzf",
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

Named chunks can be inserted as `\@ref(fig:label)` or `\@ref(tab:label)`. Unnamed chunks appear in the list with a warning label; selecting one produces a notification telling you to add a label first.

````markdown
```{r myplot, fig.cap="My caption"}
# referenced as \@ref(fig:myplot) or \@ref(tab:myplot)
```

```{r}
# unnamed — add a label to use this chunk in a cross-reference
```
````

---

## Extending citeref with a custom backend

citeref uses a backend registry. You can register any table as a backend — from your own config, from a separate plugin, or to override a built-in.

```lua
require("citeref").register_backend("my_picker", {
  -- Called for citation insertion (picker backends)
  pick_citation = function(format, entries, ctx)
    -- format:  "markdown" | "latex"
    -- entries: CiterefEntry[]  (key, title, author, year, journaltitle, abstract)
    -- ctx:     saved cursor context from util.save_context()
  end,

  -- Called for crossref insertion (picker backends)
  pick_crossref = function(ref_type, chunks, ctx)
    -- ref_type: "fig" | "tab"
    -- chunks:   CiterefChunk[]  (label, display, line, file, is_current, header)
  end,

  -- Called for replacing a citation key under the cursor (picker backends)
  replace = function(entries, info)
    -- info: { key, start_col, end_col, style ("markdown"|"latex"), ... }
  end,

  -- Completion backends only: register your source with the engine once
  register = function() end,

  -- Completion backends only: open the menu in a specific mode
  show = function(mode, format)
    -- mode:   "citation" | "crossref_fig" | "crossref_tab" | "all"
    -- format: "markdown" | "latex"
  end,
})
```

Only implement the functions your backend supports. citeref checks for nil before calling and warns if a required function is missing. Built-in backends live in `lua/citeref/backends/` and are a good reference for implementation.

The shared parsers are available for reuse:

```lua
local parse = require("citeref.parse")

parse.load_entries()          -- resolve bib files + parse → CiterefEntry[]
parse.load_chunks()           -- scan current buf + siblings → CiterefChunk[]
parse.entry_display(entry)    -- "key │ title │ author"
parse.entry_preview(entry)    -- multi-line preview string
parse.format_citation(keys)   -- "@key1; @key2" (markdown only)
parse.citation_under_cursor() -- detect citation at cursor → info table or nil
```

Note: for LaTeX citations, use `"\\cite{" .. cmd .. "}{" .. table.concat(keys, ", ") .. "}"` directly — `format_citation` is markdown-only. The available commands are defined in `lua/citeref/latex_formats.lua`.

---

## Architecture

```
lua/citeref/
  init.lua              Public API, keymap setup, buffer attach, register_backend()
  config.lua            Options, defaults, validation
  parse.lua             Bib parser, chunk parser, shared display helpers
  util.lua              Cursor context save/restore, text insertion
  latex_formats.lua     LaTeX citation command definitions (single source of truth)
  backends/
    init.lua            Backend registry and lazy loader
    fzf.lua             fzf-lua picker (citations, crossrefs, replace)
    telescope.lua       telescope.nvim picker (citations, crossrefs, replace)
    snacks.lua          snacks.nvim picker (citations, crossrefs, replace)
    blink.lua           blink.cmp completion source
    cmp.lua             nvim-cmp completion source
plugin/
  citeref.lua           FileType autocommand (startup entry point)
```

---

## Startup cost

citeref is designed to have zero startup impact:

- `plugin/citeref.lua` only registers a `FileType` autocmd — no modules load.
- On buffer attach, only `citeref.config` and `citeref.init` load (tiny pure-Lua, no external dependencies).
- The backend module (`citeref.backends.fzf` etc.) loads on your **first keypress** only.

---

## Programmatic API

```lua
local citeref = require("citeref")

citeref.cite_markdown()      -- insert @key
citeref.cite_latex()         -- insert \cite{key}
citeref.cite_replace()       -- replace citation key under cursor (picker backends only)
citeref.crossref_figure()    -- insert \@ref(fig:label)
citeref.crossref_table()     -- insert \@ref(tab:label)

citeref.register_backend(name, backend)  -- register a custom backend

citeref.debug()              -- print backend, attachment status, and active keymaps
```

---

## Contributing

Contributions of any kind are very welcome — bug reports, feature suggestions, documentation improvements, and especially code. If you have an idea for a new backend, a fix, or a quality-of-life improvement, please open an issue or pull request. This plugin is small and the codebase is meant to be easy to navigate, so diving in should be straightforward.

If you want to contribute code, the [Architecture](#architecture) section at the bottom of this README is a good starting point for orientation. Custom backends are particularly easy to add without touching core files — see [Extending citeref with a custom backend](#extending-citeref-with-a-custom-backend).

---

## Similar projects

- **[zotcite](https://github.com/jalvesaq/zotcite)** — the most feature-rich option if you use Zotero. Queries the Zotero database directly (no `.bib` export needed), provides omnicompletion, opens PDF attachments, and can extract annotations and notes. Requires Python 3, `sqlite3`, and `nvim-treesitter`. Supports Markdown, Quarto, RMarkdown, LaTeX, Rnoweb, Typst, and vimwiki.

- **[telescope-zotero.nvim](https://github.com/jmbuhr/telescope-zotero.nvim)** — a Telescope extension that browses your Zotero library and inserts the selected reference into a `.bib` file. Requires Zotero, Better BibTeX, and `sqlite.lua`. The intended workflow keeps citation insertion (via this plugin) separate from in-document completion (handled by a companion cmp source).

- **[zotex.nvim](https://github.com/tiagovla/zotex.nvim)** — an nvim-cmp completion source that imports references directly from the Zotero SQLite database. Lightweight and focused: configure it as a cmp source for your filetypes and it will surface Zotero entries as you type. Requires `sqlite.lua`.

---

## License

GNU General Public License v3.0 — see [LICENSE](LICENSE).
