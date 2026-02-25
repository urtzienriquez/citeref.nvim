--- citeref.nvim – backend registry
---
--- Built-in backends are registered lazily on first load. Third-party or user
--- backends can be registered at any time via citeref.register_backend().
---
--- A backend is a table with any combination of these functions:
---
---   pick_citation(format, entries, ctx)   "markdown"|"latex", CiterefEntry[], ctx
---   pick_crossref(ref_type, chunks, ctx)  "fig"|"tab", CiterefChunk[], ctx
---   replace(entries, info)                CiterefEntry[], cursor-info table
---   -- completion backends only:
---   register()                            called once to register with the engine
---   show(mode, format)                    open the completion menu
---
--- Only implement the functions your backend supports. Citeref checks for nil
--- before calling, and warns the user if a required function is missing.

local M = {}

-- ─────────────────────────────────────────────────────────────
-- Registry
-- ─────────────────────────────────────────────────────────────

---@type table<string, table>
local _registry = {}

--- Register a backend by name. Can be called before or after setup().
--- Built-in backends are pre-registered; calling this with an existing name
--- overwrites it, so users can replace built-ins too.
---@param name string
---@param backend table
function M.register(name, backend)
  _registry[name] = backend
end

--- Return the active backend table, loading it if not yet registered.
---@return table|nil
function M.get()
  local name = require("citeref.config").get().backend
  if not name then
    return nil
  end

  -- Lazy-load built-ins on first access
  if not _registry[name] then
    local ok, mod = pcall(require, "citeref.backends." .. name)
    if ok then
      _registry[name] = mod
    else
      vim.notify("citeref: backend '" .. name .. "' could not be loaded.\n" .. tostring(mod), vim.log.levels.ERROR)
      return nil
    end
  end

  return _registry[name]
end

--- Call a named function on the active backend, with a clear error if missing.
---@param fn_name string
---@param ... any
function M.call(fn_name, ...)
  local b = M.get()
  if not b then
    vim.notify("citeref: no backend configured. Add backend = '...' to your setup() call.", vim.log.levels.WARN)
    return
  end
  if type(b[fn_name]) ~= "function" then
    vim.notify(
      "citeref: backend '"
        .. tostring(require("citeref.config").get().backend)
        .. "' does not support '"
        .. fn_name
        .. "'.",
      vim.log.levels.WARN
    )
    return
  end
  b[fn_name](...)
end

return M
