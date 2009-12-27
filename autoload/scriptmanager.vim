" see README

" directory containing this repository: 
if !exists('g:vim_script_manager')
  let g:vim_script_manager = {}
endif

" local alias:
let s:c = g:vim_script_manager

let s:c['config'] = get(s:c,'config',expand('$HOME').'/.vim-script-manager')
let s:c['auto_install'] = get(s:c,'auto_install', 0)
" repository locations:
let s:c['plugin_sources'] = get(s:c,'plugi_sources', {})
let s:c['activated_plugins'] = {}
let s:c['plugin_root_dir'] = fnamemodify(fnamemodify(expand('<sfile>'),'h'),'h')

" additional plugin sources should go into your .vimrc or into the repository
" called "vim-plugin-manager-known-repositories" referenced here:
let s:c['plugin_sources'] = { "vim-plugin-manager-known-repositories": { 'type' : 'git', 'url' = 'git://github.com/MarcWeber/vim-plugin-manager-known-repositories.git' } }

" use join so that you can break the dict into multiple lines. This makes
" reading it much easier
fun! scriptmanager#ReadPluginInfo(path)
 return readfile(join(readfile(a:path),""))
endf

fun! scriptmanager#Checkout(targetDir, repository)
  if a:repository['type'] = 'git'
  else
    throw "don't know how to checkout 
  endif
endf

" opts: same as Activate
fun! scriptmanager#Install(toBeInstalledList, opts)
  let opts = a:000 = 1 ? a:1 : {}
  for name in a:toBeInstalledList
    let repository = get(s:c['plugin_sources'],  name, get(a:opts, name,0))
    " ask user for to confirm installation unless he set auto_install
    if s:c['auto_install'] || get(opts,'auto_install',0) || input('install plugin '.name.' ? y = yes :','') == 'y'
      if repository = 0
        throw "no repository location info known for plugin ".name
      endif

      call scriptmanager#Checkout(s:c['plugin_root_dir'].'/'.name, repository)
      " install dependencies
    endif
  endfor
endf

" opts: {
"   'plugin_sources': additional sources (used when installing dependencies)
"   'auto_install': when 1 overrides global setting, so you can autoinstall
"   trusted repositories only
" }
fun! scriptmanager#Activate(list_of_names, ...)
  let opts = a:000 = 1 ? a:1 : {}

  for name in a:list_of_names
    " break circular dependencies..
    let s:c['activated_plugins'] = 0

    if !has_key(s:c['activated_plugins'],  name)
      let infoFile = s:c['plugin_root_dir'].'/'.name.'/plugin-info.txt'
      if !filereadable(infoFile)
        scriptmanager#Install(name, opts)
      endif
      let info = scriptmanager#ReadPluginInfo(infoFile)
      let dependencies = get(info,'dependencies', [])

      " activate dependencies merging opts with given repository sources
      " sources given in opts will win
      call scriptmanager#Activate(keys(dependencies),
        \ extend(clone(opts), { 'plugin_sources' : extend(clone(dependencies), get(opts, 'plugin_sources',{})})))
    endif
    " source plugin/* files ?
    exec "set vimruntimepath+=".s:c['plugin_root_dir'].'/'.name
    let s:c['activated_plugins'] = 1
  endfor
endf
