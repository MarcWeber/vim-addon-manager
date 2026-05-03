REASONING
=========
I think Vim is dead.
Neovim is using Lua.
Lazy.nvim seems to be most popular manager for Neovim.

lazy.nvim is using configuration blocks (init, config, opts, etc.)

So to easy transitioning to lazy.nvim while coexisting with vim-addon-manager
maybe turning your script file for vam#Scripts into a lua dictionary is the
best step because it allows to have configurations at plugin level.

```viml
lua vim.fn["vam#Scripts"](require("vim-marcweber/vim-scripts").scripts, {tag_regex = ".*"} )
```

COEXISTENCE APPROACH
====================

## Overview

VAM now supports an `init` field in script entries that executes Lua code when
a plugin is activated. This works for both immediate and lazy-loaded plugins.

For lazy.nvim compatibility, a `lua/vam/compat_lazy_nvim.lua` module converts
VAM script entries to lazy.nvim specs.

## VAM `init_lua` and `init_viml` fields

VAM now supports two initialization fields:

### `init_lua` (for Neovim)

Executes Lua code when the plugin is activated. Works for both immediate and lazy-loaded plugins.

```lua
{name = "vim-addon-other",
 init_lua = [[vim.keymap.set('n', '<leader>o', function()
   print("vim-addon-other loaded")
 end, {desc = 'Test mapping'})]],
 lazy_nvim_ok = 1},
```

Or require a setup module:

```lua
{name = "nvim-setup-cmp",
 init_lua = [[require("nvim-setup-cmp").setup()]],
 lazy_nvim_ok = 1},
```

### `init_viml` (for Vim/Neovim)

Executes Vimscript code when the plugin is activated:

```lua
{name = "vim-addon-other",
 init_viml = "nnoremap <leader>o :echo 'vim-addon-other loaded'<CR>"},
```

### How it works

When VAM activates a plugin (in `vam#ActivateRecursively`), it checks for
`init_lua` (Neovim only, runs via `nvim_exec_lua()`) and `init_viml` (runs via `execute`).
This works for:
- Plugins activated at startup
- Lazy-loaded plugins (activated by ft_regex, filename_regex, etc.)

The init code runs when the plugin is activated, not when Neovim/Vim starts.

## `lua/vam/compat_lazy_nvim.lua` module

Reusable module that converts VAM script entries to lazy.nvim specs:

```lua
local compat = require("vam.compat_lazy_nvim")
local vim_scripts = require("vim-marcweber.vim-scripts")
local specs = compat.to_lazy_specs(vim_scripts.scripts)
```

Supported fields automatically converted:
- `init`, `config`, `opts` - Lua code/callbacks
- `ft`, `cmd`, `keys`, `event` - lazy-loading triggers
- `dependencies` - plugin dependencies
- `lazy` - lazy loading flag
- `expr` - converted to `cond` function

## `init-lazy-nvim.lua` (refactored)

Now uses the `compat_lazy_nvim` module:

```lua
function plugin_dir(name)
-- optionally return the path of the plugin directory mimicing VAM's implementation
end
local compat = require("vam.compat_lazy_nvim")
local vim_scripts = require("vim-marcweber.vim-scripts")
local specs = compat.to_lazy_specs(vim_scripts.scripts, { plugin_dir = plugin_dir })
require("lazy").setup({spec = specs, checker = { enabled = true }})
```

## Migration Path

1. Add `init` fields to `vim-scripts.lua` entries as needed
2. Add `lazy_nvim_ok = 1` to plugins you want in lazy.nvim
3. Use `init-lazy-nvim.lua` for lazy.nvim, `vam#Scripts()` for VAM
4. Both use the same `vim-scripts.lua` as input

## Example `vim-scripts.lua` entry

```lua
{name = "nvim-setup-colorscheme",
 init_lua = [[
   vim.cmd.colorscheme("nightfox")
   vim.keymap.set('n', '<leader>c', function()
     vim.cmd.colorscheme("gruvbox")
   end, {desc = 'Switch colorscheme'})
 ]],
 lazy_nvim_ok = 1},
```

This single entry works with both:
- VAM: `init_lua` runs when plugin activates (including lazy-loaded)
- lazy.nvim: `init` (mapped from `init_lua`) runs at startup (lazy.nvim semantics)
