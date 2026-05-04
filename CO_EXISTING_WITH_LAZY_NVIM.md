REASONING
=========
I think Vim is dead.
Neovim is using Lua.
Lazy.nvim seems to be most popular manager for Neovim.

If you want to use VAM but transition to lazy.nvim:

  exec 'set runtimepath+='.vam_install_path.'/vim-addon-manager'
  exec 'set runtimepath+='.vam_install_path.'/vim-addon-manager/compat-layer-lazy-nvim-use-vam'

  Then you can use require("lazy").load({ plugins = { "telescope.nvim" } })

USING nvim.lazy
===============

If you want to use nvim.lazy but still depend on VAMActivate in some
plugins try this thin layer mocking VAMActivate and turning vim-addon-manager
like plugin lists into a config nvim.lazy understands:



```lua
    -- vim_scripts files like this:
    local vim_scipts = {
        {name = "vim-addon-other",
         init_vim = [[
            let g:setup_plugin = ...
            command ABC ..
            map ...
         ]],
         init_lua = [[vim.keymap.set('n', '<leader>o', function()
           print("vim-addon-other loaded")
         end, {desc = 'Test mapping'})]],
         lazy_nvim_ok = 1}
    }
    return vim_scripts

    local plugins_install_path = "/your/path/here" -- Ensure this variable is defined
    -- see https://github.com/MarcWeber/nvim.lazy-vam-compat-layer.git
    vim.opt.rtp:append(plugins_install_path .. "/nvim.lazy-vam-compat-layer"
    local compat = require("nvim-lazy-vam-compat-layer/scripts-to-lazy")
    function plugin_dir(name)
    -- optionally return the path of the plugin directory mimicing VAM's implementation
    end
    require("nvim-lazy-vam-compat-layer/mock-vam")
    -- vim_scripts for vam#Scripts() but now lua file so that multi line init
    -- codes can be defined as in lazy.nvim
    local vim_scripts = require("vim-marcweber.vim-scripts")
    local specs = compat.to_lazy_specs(vim_scripts.scripts, { plugin_dir = plugin_dir })
    require("lazy").setup({spec = specs, checker = { enabled = true }})
```


STILL USING VAM mock nvim.lazy's load()
=======================================

```viml
  exec 'set runtimepath+='.vam_install_path.'/vim-addon-manager'
  " this mocks require("lazy").load({ plugins = { "telescope.nvim" } })
  " so that you can transition VAMActivate calls to nvim.lazy
  exec 'set runtimepath+='.vam_install_path.'/vim-addon-manager/compat-layer-lazy-nvim-use-vam'

  lua vim.fn["vam#Scripts"](require("vim-marcweber/vim-scripts").scripts, {tag_regex = ".*"} )
```


TODO
====
- lazy mappings ? should this be ported to VAM?
  Same about commands etc?
  Should it be the >user< having to do this if you git pull
  it should still work !?
  - YES -> if 2 plugins have same command you can control
  - NO -> if 2 plugins have same command what should be done ?
    Ask user ?
    -> something like addon-info.json sill makes sense -
    well use yaml ? Well prefer addon-info.lua now ? :-/
- ft_regex
- filename_regex
- make sure lazy = true opts etc can be passed
- When lazy loading a plugin with plugin/*.vim files
  after startup must those files be sourced like
  vam#Activate does ?
-> https://github.com/MarcWeber/nvim.lazy-vam-compat-layer
