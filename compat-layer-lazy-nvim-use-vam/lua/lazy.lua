local M = {}

-- The mock load function
M.load = function(opts)
  if opts and opts.plugins then
    local plugins = type(opts.plugins) == "table" and opts.plugins or { opts.plugins }
    vim.cmd("VAMActivate " .. table.concat(plugins, " "))
  end
end

-- Optional: Mock other common lazy.nvim functions to prevent errors
M.setup = function() end
M.plugins = function() return {} end

return M
