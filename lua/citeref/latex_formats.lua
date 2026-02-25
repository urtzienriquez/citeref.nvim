--- citeref.nvim – shared LaTeX citation format definitions
--- Backends import this so the list is defined in one place.

---@class CiterefLatexFormat
---@field cmd   string  e.g. "citep"
---@field label string  e.g. "\\citep{}"

---@type CiterefLatexFormat[]
local M = {
  { cmd = "cite", label = "\\cite{}" },
  { cmd = "citep", label = "\\citep{}" },
  { cmd = "citet", label = "\\citet{}" },
  { cmd = "citeauthor", label = "\\citeauthor{}" },
  { cmd = "citeyear", label = "\\citeyear{}" },
  { cmd = "citealt", label = "\\citealt{}" },
  { cmd = "textcite", label = "\\textcite{}" },
  { cmd = "parencite", label = "\\parencite{}" },
  { cmd = "footcite", label = "\\footcite{}" },
  { cmd = "autocite", label = "\\autocite{}" },
}

return M
