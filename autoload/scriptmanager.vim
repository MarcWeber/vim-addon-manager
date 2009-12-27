" see README

fun! scriptmanager#DefineAndBind(local,global,default)
  return 'if !exists('.string(a:global).') | let g:vim_script_manager = '.a:default.' | endif | let '.a:local.' = '.a:global
endf
exec scriptmanager#DefineAndBind('s:c','g:vim_script_manager','{}')

let s:c['config'] = get(s:c,'config',expand('$HOME').'/.vim-script-manager')
let s:c['auto_install'] = get(s:c,'auto_install', 0)
" repository locations:
let s:c['plugin_sources'] = get(s:c,'plugin_sources', {})
let s:c['activated_plugins'] = {}
let s:c['plugin_root_dir'] = fnamemodify(expand('<sfile>'),':h:h:h')

" additional plugin sources should go into your .vimrc or into the repository
" called "vim-plugin-manager-known-repositories" referenced here:
let s:c['plugin_sources']["vim-plugin-manager-known-repositories"] = { 'type' : 'git', 'url': 'git://github.com/MarcWeber/vim-plugin-manager-known-repositories.git' }

" use join so that you can break the dict into multiple lines. This makes
" reading it much easier
fun! scriptmanager#ReadPluginInfo(path)
 " using eval is evil!
 return eval(join(readfile(a:path),""))
endf

fun! scriptmanager#ShellEscape(a)
  return shellescape(a:a, ' \')
endf

fun! scriptmanager#Checkout(targetDir, repository)
  if a:repository['type'] == 'git'
    let parent = fnamemodify(a:targetDir,':h')
    exec '!cd '.scriptmanager#ShellEscape(parent).'; git clone 'scriptmanager#ShellEscape(a:repository['url'])
    if !isdirectory(a:targetDir)
      throw "failed checking out ".a:targetDir." \n".str
    endif
  else
    throw "don't know how to checkout 
  endif
endf

fun! scriptmanager#PluginDirByName(name)
  return s:c['plugin_root_dir'].'/'.a:name
endf

" doesn't check dependencies!
fun! scriptmanager#IsPluginInstalled(name)
  return isdirectory(scriptmanager#PluginDirByName(a:name))
endf

" opts: same as Activate
fun! scriptmanager#Install(toBeInstalledList, ...)
  let opts = a:0 == 0 ? {} : a:1
  for name in a:toBeInstalledList
    if scriptmanager#IsPluginInstalled(name)
      continue
    endif

    let repository = get(s:c['plugin_sources'], name, get(opts, name,0))
    " ask user for to confirm installation unless he set auto_install
    if s:c['auto_install'] || get(opts,'auto_install',0) || input('install plugin '.name.' ? [y/n]:','') == 'y'
      if type(repository) == type(0) && repository == 0
        throw "no repository location info known for plugin ".name
      endif
      let pluginDir = scriptmanager#PluginDirByName(name)
      call scriptmanager#Checkout(pluginDir, repository)
      " install dependencies
      
      let infoFile = pluginDir.'/'.name.'/plugin-info.txt'
      let info = scriptmanager#ReadPluginInfo(infoFile)
      let dependencies = get(info,'dependencies', [])

      " install dependencies merging opts with given repository sources
      " sources given in opts will win
      call scriptmanager#Install(keys(dependencies),
        \ extend(copy(opts), { 'plugin_sources' : extend(copy(dependencies), get(opts, 'plugin_sources',{}))}))
    endif
  endfor
endf

" opts: {
"   'plugin_sources': additional sources (used when installing dependencies)
"   'auto_install': when 1 overrides global setting, so you can autoinstall
"   trusted repositories only
" }
fun! scriptmanager#Activate(list_of_names, ...)
  let opts = a:0 == 0 ? {} : a:1

  for name in a:list_of_names
    if !has_key(s:c['activated_plugins'],  name)
      " break circular dependencies..
      let s:c['activated_plugins'][name] = 0

      let infoFile = s:c['plugin_root_dir'].'/'.name.'/plugin-info.txt'
      if !filereadable(infoFile)
        call scriptmanager#Install([name], opts)
      endif
      let info = scriptmanager#ReadPluginInfo(infoFile)
      let dependencies = get(info,'dependencies', [])

      " activate dependencies merging opts with given repository sources
      " sources given in opts will win
      call scriptmanager#Activate(keys(dependencies),
        \ extend(copy(opts), { 'plugin_sources' : extend(copy(dependencies), get(opts, 'plugin_sources',{}))}))
    endif
    " source plugin/* files ?
    exec "set runtimepath+=".s:c['plugin_root_dir'].'/'.name
    let s:c['activated_plugins'][name] = 1
  endfor
endf
