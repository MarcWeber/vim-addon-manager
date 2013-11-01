exec vam#DefineAndBind('s:c','g:vim_addon_manager','{}')

" VAM's bundle emulation: usage:
"
" let manager = "VAM"
" if manager == "vundle"
"   set rtp+=~/.vim/bundle/vundle/
"   call vundle#rc()
" else
"
"   fun SetupVAM()
"     let c = get(g:, 'vim_addon_manager', {})
"     let g:vim_addon_manager = c
"     let c.plugin_root_dir = expand('$HOME', 1) . '/.vim/bundle'
"     let &rtp.=(empty(&rtp)?'':',').c.plugin_root_dir.'/vim-addon-manager'
"     " let g:vim_addon_manager = { your config here see "commented version" example and help
"     if !isdirectory(c.plugin_root_dir.'/vim-addon-manager/autoload')
"       execute '!git clone --depth=1 git://github.com/MarcWeber/vim-addon-manager '
"                   \       shellescape(c.plugin_root_dir.'/vim-addon-manager', 1)
"     endif
"     call vam#ActivateAddons([], {'auto_install' : 0})
"   endfun
"   call SetupVAM()
"   call vam#bundle_emulation#ProvideVundlesBundleCommand({'info': 1})
"
" endif
"
" Bundle ABC/FOO
" Bundle Z

fun! vam#bundle_emulation#BundleToVamName(name)
  if a:name =~ '/'
    " assume github
    return 'github:'.a:name
  else
    " asume directory in bundle
    return a:name
  endif
endfun

fun! vam#bundle_emulation#Bundle(...)
  let args = a:000
  if a:0 != 1
    throw "VAM's bundle emulation only supports simple arguments
  endif
  let stripped  = substitute(a:1, "['\"]", "", 'g')
  if stripped =~ 'vundle$'
    " don't activate vundle
    return
  endif
  call vam#ActivateAddons([vam#bundle_emulation#BundleToVamName(stripped)], {'auto_install': 0})
endfun

fun! vam#bundle_emulation#PluginDirFromName(name)
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

fun vam#bundle_emulation#ProvideVundlesBundleCommand(opts)
  command! -nargs=* Bundle call vam#bundle_emulation#Bundle(<f-args>)

  if get(a:opts, 'info', 1)
    sp
    put="You're using VAM"s bundle emulation."
    put="Consider reading VAM's documentation, because VAM offers many additional features"
    put=""
    put="Some keywords: -known-repositories, activating plugins at runtime, plugin names"
    put="simple dependency management, recommended auto install setup by making .vimrc checkout VAM"
    put=""
    put="get rid of this message by passing ProvideVundlesBundleCommand({'info': 0})"
  endif

  if get(a:opts, 'default-bundle-locations', 1)
    " VAM by default gives different names .. change this
    let s:c.plugin_dir_by_name = 'vam#bundle_emulation#PluginDirFromName'
  endif
endfun
