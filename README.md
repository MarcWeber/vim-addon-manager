## VAM - maximizing overall Vim experience
[VAM] is short name for vim-addon-manager

## FEATURES
- declarative: The behaviour of Vim is determined by your .vimrc only [1]
- automatic runtimepath handling:
  install/ update/ use manually installed plugin on startup or load them lazily
  as needed when you feel that way [3]
- dependency management builtin [2]
- based on a "pool" of plugin which is maintained by the community.
  This allows warning you if you're going to install autdated packages.
  [known plugins](http://mawercer.de/~marc/vam/index.php).
  Of course you can opt-out and use your own pool easily.
- sources from www.vim.org, git, mercurial, svn, darcs, cvs, bazaar, [...]
- plugin name completion in .vim files and :(Update|Activate)Addons commands
- short syntax for github repos: "github:name/repo"
- optionally writes update logs
- cares about [windows users](http://mawercer.de/~marc/vam/index.php)
- plugin info by name or script id (:AddonInfo)
- tries to preserve user modifications by using diff/patch tools on unix like
  environments
- 100% VimL (is this really that good ? ..)

[1]: assuming you always use latest versions
[2]: this serves the community by making it easy to reuse other's code.
     Implemented by a addon-info.json file
[3]: Yes - there are some special cases where it does not work correctly
     because some au commands don't get triggered

## SUPPORT
VAM is well supported by at least 2 maintainers. Try github tickets or Vim irc
channel on freenode.

## MINIMAL setup (2 lines)

    set runtimepath+=/path/to/vam
    call vam#ActivateAddons([list of plugin names])

However the "self install" alternative is recommended, see 
[section 2 of GETTING STARTED](https://raw.github.com/MarcWeber/vim-addon-manager/master/doc/vim-addon-manager-getting-started.txt)

## Let me see all docs!
Here you go:

- [GETTING STARTED](doc/vim-addon-manager-getting-started.txt)
- [additional docs](doc/vim-addon-manager-additional-documentation.txt)

## CONTACT / HELP
See contact information in GETTING STARTED documentation.

## BUGS
It'll never have nice install progress bars - because the "progress" is not
very well known because plugins can be installed at any time - and additionall
depnedncies may be encountered.

If you want to be able to rollback you have to use git submodules yourself or
find a different solution - because VAM also supports other VCS and installing
by .zip,.tar.gz etc

## related work
Also very famous:

- [vundle](https://github.com/gmarik/vundle)
- [pathogen](https://github.com/tpope/vim-pathogen)
- [vim-scripts](http://vim-scripts.org)

[debian's vim plugin manager](http://packages.debian.org/sid/vim-addon-manager)
The author (Jamessan) is fine with this project sharing the same name.
