local M = {}

--- Convert VAM script entries to lazy.nvim specs
---@param scripts table List of VAM script entries
---@param opts.plugin_dir function(name) => returning plugin path or nil
---@return table List of lazy.nvim plugin specs
function M.to_lazy_specs(scripts, opts)
  local specs = {}
  for _, script in ipairs(scripts) do
    if not script.lazy_nvim_ok then goto continue end
    M._convert_add(specs, script, opts)
    ::continue::
  end
  return specs
end

--- Convert a single VAM script entry to lazy.nvim spec
---@param script table VAM script entry
---@return table|nil lazy.nvim plugin spec
function M._convert_add(specs, script, opts)
  if script.names then
    for _, name in ipairs(script.names) do
      local s = vim.deepcopy(script)
      s[1] = name:gsub("^github:", "")
      s.names, s.name = nil, nil
      M._convert_add(specs, s, opts)
    end
    return
  end

  local spec = {}
  local name = script.name:gsub("^github:", "")
  spec[1] = name

  local dir = opts.plugin_dir and opts.plugin_dir(name)
  if dir then
    spec.dir = dir
  end

  -- Copy lazy.nvim supported fields (init_lua maps to init for lazy.nvim)
  for _, k in ipairs({ "config", "opts", "ft", "cmd", "keys", "event", "dependencies", "lazy" }) do
    if script[k] ~= nil then
      spec[k] = script[k]
    end
  end
  -- Map init_lua and init_viml to lazy.nvim's init
  if script.init_lua ~= nil and script.init_viml ~= nil then
    -- Both set: run both (init_lua first, then init_viml)
    local lua_code = script.init_lua
    local viml_code = script.init_viml
    spec.init = function()
      vim.api.nvim_exec_lua(lua_code, {})
      vim.cmd(viml_code)
    end
  elseif script.init_lua ~= nil then
    spec.init = script.init_lua
  elseif script.init_viml ~= nil then
    local viml_code = script.init_viml
    spec.init = function()
      vim.cmd(viml_code)
    end
  end

  -- Handle VAM's expr as lazy.nvim cond
  if script.expr then
    spec.cond = function()
      return vim.fn.eval(script.expr) == 1
    end
  end

  table.insert(specs, spec)
end

return M
