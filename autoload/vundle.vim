exec vam#DefineAndBind('s:c','g:vim_addon_manager','{}')

" VAM's bundle emulation: usage like vundle:
"
"   set rtp+=~/.vim/bundle/vim-addon-manager
"   " let g:vim_addon_manager = {}
"   " let g:vim_addon_manager.option = ...
"   call vundle#rc()
"   Bundle ABC/FOO
"   Bundle Z

func! vundle#rc(...) abort
  let g:bundle_dir = len(a:000) > 0 ? expand(a:1, 1) : expand('$HOME/.vim/bundle', 1)

  " TODO take care about these options ?
  " let g:updated_bundles = []
  " let g:vundle_log = []
  " let g:vundle_changelog = ['Updated Bundles:']

  let s:c.plugin_root_dir = g:bundle_dir

  " adopt to vundles directory naming
  let s:c.plugin_dir_by_name = 'vundle#PluginDirFromName'

  command! -nargs=* Bundle call vundle#Bundle(<f-args>)
  " Some commands and options are missing, could be implemented trivially
  " If you hit such a case create an issue and we'll fix it.
endf

fun! vundle#BundleToVamName(name)
  " TODO file:// syntax and the like ?
  " TODO gh: syntax

  if a:name =~ '/'
    " assume github
    return 'github:'.a:name
  elseif a:name =~ '^gh:'
    return substitute(a:name, '^gh:','github:','')
  else
    " asume directory in bundle
    return a:name
  endif
endfun

fun! vundle#Bundle(...)
  let args = a:000
  if a:0 != 1
    throw "VAM's bundle emulation only supports simple arguments - create a github account at github.com/MarcWeber/vim-addon-manager/issues/new"
  endif
  let stripped  = substitute(a:1, "['\"]", "", 'g')
  if stripped =~ '\<vundle$'
    " don't activate vundle
    return
  endif
  call vam#ActivateAddons([vundle#BundleToVamName(stripped)], {})
endfun

" vundle has a different naming scheme, turn VAM names into bundle locations
fun! vundle#PluginDirFromName(name)
  if a:name =~ '/'
    " VAM uses github-name-repo to avoid collisions, bundle only uses
    " repository name
    let name = fnamemodify(a:name, ':t')
  else
    " asume directory in bundle directory, use as is
    let name = a:name
  endif

  let dirs = [s:c.plugin_root_dir] + s:c.additional_addon_dirs
  let existing = filter(copy(dirs), "isdirectory(v:val.'/'.".string(name).')')
  return (empty(existing) ? dirs[0] : existing[0]).'/'.name
endfun
