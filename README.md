# VAM — maximizing overall Vim experience
“VAM” is short name for vim-addon-manager.
You declare a set of plugins. VAM will fetch & activate them at startup or
runtime depending on your needs. Activating means handling runtimepath and
making sure all .vim file get sourced.

![VAM](http://vam.mawercer.de/screenshot.png)

This screenshot shows:
- The log buffer
- The plugin name completion
- That vim-pi knows about plugins which are neither known by vim-scripts.org
  nor by vim.sf.net (marked by NA)

## If you believe in VAM's collaborative properties
then you may also want to have a look at [vim-git-wiki](http://vim-wiki.mawercer.de).

## SUPPORT / HELP
VAM is well supported by at least 2 maintainers. Try github tickets or Vim irc
channel on freenode.

## finding plugin names

    Simply use <c-x><c-p> in .vim files (buffer completion)
    (or use VAMActivate, VAMPluginInfo command completion ..)

## MINIMAL setup (3 lines)

```vim
set runtimepath+=/path/to/vam
call vam#ActivateAddons([])
VAMActivate tlib matchit.zip
```

## Recommended setup (checking out VAM ..):

```vim
" put this line first in ~/.vimrc
set nocompatible | filetype indent plugin on | syn on

fun! SetupVAM()
  let c = get(g:, 'vim_addon_manager', {})
  let g:vim_addon_manager = c
  let c.plugin_root_dir = expand('$HOME', 1) . '/.vim/vim-addons'
  " most used options you may want to use:
  " let c.log_to_buf = 1
  " let c.auto_install = 0
  let &rtp.=(empty(&rtp)?'':',').c.plugin_root_dir.'/vim-addon-manager'
  if !isdirectory(c.plugin_root_dir.'/vim-addon-manager/autoload')
    execute '!git clone --depth=1 git://github.com/MarcWeber/vim-addon-manager '
        \       shellescape(c.plugin_root_dir.'/vim-addon-manager', 1)
  endif
  call vam#ActivateAddons([], {'auto_install' : 0})
endfun

call SetupVAM()
VAMActivate matchit.zip vim-addon-commenting
" use <c-x><c-p> to complete plugin names
```

## easy setup windows users:
Give the [downloader](http://vam.mawercer.de/) a try if you're too lazy to install supporting tools. In
the doc/ directory you'll find additional information. https (self signed certificate) can be used, too.

## all commands

```vim
" Note: All commands support completion (<c-d> or <tab>)

" install [UE] without activating for reviewing
VAMInstall P1 P2 github:user/repo git://path...

" install [UE], then activate
VAMActivate P1 P2 ...
VAMActivateInstalled (same, but completion is limited to installed plugins)

" find plugins by name github url or script id and display all information
VAMPluginInfo script_id or characters to match any description against

" update plugins (by name or all you're using right now) - you should restart Vim afterwards:
VAMUpdate vim-pi P1 P2
VAMUpdateActivated

VAMListActivated
VAMUninstallNotLoadedPlugins P1 P2

" [UE]: unless the directory exists
" P1 P2 represents arbitrary plugin names, use <c-x><c-p> to complete in .vim files

" If you need a plugin to be activated immediately. Example: You require a command in your .vimrc:
call vam#ActivateAddons(['P1', P2'], {'force_loading_plugins_now': 1})
" (should we create a special command for this?)
```
Also: Of course VAM allows using subdirectories of repositories as runtimepath.
Eg See vim-pi-patching.

## lazily loading plugins / tag plugins by topic
You can tag plugins and load them lazily

```vim
let scripts = []
call add(scripts, {'name': 'plugin_c', 'tag': 'c-dev'})
call add(scripts, {'name': 'plugin_ruby', 'tag': 'ruby-dev'})
" must activate by filename because .pov filetype is known after the script
" script-povray got activated
call add(scripts, {'name': 'script-povray', 'filename_regex':'\.pov$'})
" for others ft_regex can be used:
call add(scripts, {'name': 'script-php', 'ft_regex':'^\.php$'})

" tell VAM about all scripts, and immediately activate plugins having the c-dev tag:
call vam#Scripts(scripts, {'tag_regex': 'c-dev'})

" activate all tagged scripts immediately
call vam#Scripts([], {'tag_regex': '.*'})

```

## How does VAM know about dependencies?
Plugins ship with addon-info.json files listing the dependencies as names
(eventually with source location). Those who don't get patched by vim-pi.

Only mandatory dependencies should be forced this way. Optional dependencies
should still be installed/activated by you.


## emulating vundle
NOTE: VAM is declarative. Thus Bundle behavel like VAMActivate:
1) checkout plugin unless directory exists
2) activate it
Thus there is no reason to run BundleInstall or such (what for anyway?)

```vim
set rtp+=~/.vim/bundle/vim-addon-manager/
call vundle#rc()
Bundle fugitive
VAMActivate by-name-and-pull-depenedencies
```

Emulation is not complete yet. If you want us to complete it (eg implement the
second {rtp: ..} create a github issue. Its obsolete, because vim-pi is very
likely to know about it if you install by name.

## learn more
- by skimming this README.md file
- by looking at headlines at [doc/\*getting-started.txt](https://raw.github.com/MarcWeber/vim-addon-manager/master/doc/vim-addon-manager-getting-started.txt).
  (Note: this is best read in Vim with :set ft=help)

## FEATURES
- Declarative: The behaviour of Vim is determined by your .vimrc only. [1]
- Automatic runtimepath handling: install/ update/ use manually installed addons 
  on startup or load them lazily as needed when you feel that way. [3]
- Builtin dependency management. [2]
- Based on a [pool](http://vam.mawercer.de) of addons which is 
  maintained by the community. This allows warning you if you’re going to 
  install outdated packages. Of course you can opt-out and use your own pool 
  easily.
- Sources from www.vim.org, git, mercurial, subversion, bazaar, darcs, [...]
- Addon name completion in .vim files and :(Update|Activate)Addons commands.
- Short syntax for github repos: `github:name/repo`.
- Optionally writes update logs.
- Cares about [windows users](http://mawercer.de/~marc/vam/index.php).
- Addon info by name or script id (:AddonInfo).
- Tries to preserve user modifications by using diff/patch tools on unix like
  environments (for non-version-controlled sources).
- 100 % VimL (is this really that good?..)
- The VimL code which gets started each time is contained in one file: vam.vim
  (700 loc). Everything else has carefully been put into additional supporting
  files.

[1]: assuming you always use latest versions

[2]: this serves the community by making it easy to reuse other’s code. 
     Implemented by a addon-info.json file and patchinfo database for addons 
     without VAM support.

[3]: Yes — there are some special cases where it does not work correctly because 
     some autocommands don’t get triggered

[4]: Plugin authors should use addon-info file instead. patchinfo.vim is for 
     addons not supporting VAM.

## Let me see all docs!
Here you go:

- [GETTING STARTED](https://raw.github.com/MarcWeber/vim-addon-manager/master/doc/vim-addon-manager-getting-started.txt)
- [additional docs](https://raw.github.com/MarcWeber/vim-addon-manager/master/doc/vim-addon-manager-additional-documentation.txt)

## BUGS
It’ll never have nice install progress bars — because the “progress” is not very 
well known because addons can be installed at any time — and additional 
dependencies may be encountered.

If you want to be able to rollback you have to use git submodules yourself or 
find a different solution — because VAM also supports other VCS and installing 
from archives. We have implemented experiemntal setup, but because VAM may add
additional files such as addon-info.json in some cases repositories look dirty
usually.

VAM does not support parallel installation yet (Like NeoBundle) - we think
dependencies are more important. If you feel strongly about this create a issue.
This would require rewriting quite a lot of code.

Each call of VAMActivate takes about 1ms - if that's too much pass many plugin
names at once.

## Related work

[vim-wiki's list of alternatives](http://vim-wiki.mawercer.de/wiki/topic/vim%20plugin%20managment.html)

[debian’s vim plugin manager](http://packages.debian.org/sid/vim-addon-manager)
The author (Jamessan) is fine with this project sharing the same name.

[vundle](http://github.com/gmarik/Vundle.vim) Referencing it here because
gmarik taught us how important it is to have both: A simple nice user interface
and a short descriptive, complete README.md - Other managers see link above.
