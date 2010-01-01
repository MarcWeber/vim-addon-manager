" see README

fun! scriptmanager#DefineAndBind(local,global,default)
  return 'if !exists('.string(a:global).') | let '.a:global.' = '.a:default.' | endif | let '.a:local.' = '.a:global
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

fun! scriptmanager#Checkout(targetDir, repository)
  if a:repository['type'] == 'git'
    let parent = fnamemodify(a:targetDir,':h')
    exec '!cd '.shellescape(parent).'; git clone '.shellescape(a:repository['url']).' 'shellescape(a:targetDir)
    if !isdirectory(a:targetDir)
      throw "failed checking out ".a:targetDir." \n".str
    endif
  " can $VIMRUNTIME/autoload/getscript.vim be reused ? don't think so.. one
  " big function
  elseif has_key(a:repository, 'archive_name') && a:repository['archive_name'] =~ '.zip$'
    call mkdir(a:targetDir)
    let aname = shellescape(a:repository['archive_name'])
    exec '!cd '.shellescape(a:targetDir).' &&'
       \ .'curl -o '.aname.' '.shellescape(a:repository['url']).' &&'
       \ .'unzip '.aname
  else
    throw "don't know how to checkout source location: ".string(a:repository)
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

    " ask user for to confirm installation unless he set auto_install
    if s:c['auto_install'] || get(opts,'auto_install',0) || input('install plugin '.name.' ? [y/n]:','') == 'y'

      let known = 'vim-plugin-manager-known-repositories'
      if 0 == get(s:c['activated_plugins'], known, 0) && name != known && input('activate plugin '.known.' to get more plugin sources ? [y/n]:','') == 'y'
	call scriptmanager#Activate([known])
	" this should be done by Activate!
	exec 'source '.scriptmanager#PluginDirByName(known).'/plugin/vim-plugin-manager-known-repositories.vim'
      endif

      let repository = get(s:c['plugin_sources'], name, get(opts, name,0))

      if type(repository) == type(0) && repository == 0
        throw "no repository location info known for plugin ".name
      endif
      let pluginDir = scriptmanager#PluginDirByName(name)
      call scriptmanager#Checkout(pluginDir, repository)
      " install dependencies
     
      let infoFile = pluginDir.'/plugin-info.txt'
      let info = filereadable(infoFile)
        \ ? scriptmanager#ReadPluginInfo(infoFile)
        \ : {}

      let dependencies = get(info,'dependencies', {})

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
fun! scriptmanager#ActivateRecursively(list_of_names, ...)
  let opts = a:0 == 0 ? {} : a:1

  for name in a:list_of_names
    if !has_key(s:c['activated_plugins'],  name)
      " break circular dependencies..
      let s:c['activated_plugins'][name] = 0

      let infoFile = scriptmanager#PluginDirByName(name).'/plugin-info.txt'
      if !filereadable(infoFile)
        call scriptmanager#Install([name], opts)
      endif
      let info = filereadable(infoFile)
        \ ? scriptmanager#ReadPluginInfo(infoFile)
        \ : {}
      let dependencies = get(info,'dependencies', {})

      " activate dependencies merging opts with given repository sources
      " sources given in opts will win
      call scriptmanager#Activate(keys(dependencies),
        \ extend(copy(opts), { 'plugin_sources' : extend(copy(dependencies), get(opts, 'plugin_sources',{}))}))
    endif
    " source plugin/* files ?
    exec "set runtimepath+=".s:c['plugin_root_dir'].'/'.name

    if has_key(s:c, 'started_up')
      call scriptmanager#GlobThenSource(scriptmanager#PluginDirByName(name).'/plugin/**/*.vim')
    endif

      let s:c['activated_plugins'][name] = 1
  endfor
endf

" see also ActivateRecursively
" Activate activates the plugins and their dependencies recursively.
" I sources both: plugin/*.vim and after/plugin/*.vim files when called after
" .vimrc has been sourced which happens when you activate plugins manually.
fun! scriptmanager#Activate(...)
  let active = copy(s:c['activated_plugins'])
  call call('scriptmanager#ActivateRecursively', a:000)

  if has_key(s:c, 'started_up')
    " now source after/plugin/**/*.vim files explicitely. Vim doesn't do it (hack!)
    for k in keys(s:c['activated_plugins'])
      if !has_key(active, k)
        call scriptmanager#GlobThenSource(scriptmanager#PluginDirByName(k).'/after/plugin/**/*.vim')
      endif
    endfor
  endif
endfun

fun! scriptmanager#Update()
  throw "to be implemented"
endf

fun! scriptmanager#GlobThenSource(glob)
  for file in split(glob(a:glob),"\n")
    exec 'source '.file
  endfor
endf

augroup VIM_PLUGIN_MANAGER
  autocmd VimEnter * call  scriptmanager#Hack()
augroup end

" hack: Vim sources plugin files after sourcing .vimrc
"       Vim dosen't source the after/plugin/*.vim files in other runtime
"       paths. So do this *after* plugin/* files have been sourced
fun! scriptmanager#Hack()
  let s:c['started_up'] = 1

  " now source after/plugin/**/*.vim files explicitely. Vim doesn't do it (hack!)
  for p in keys(s:c['activated_plugins'])
      call scriptmanager#GlobThenSource(scriptmanager#PluginDirByName(p).'/after/plugin/**/*.vim')
  endfor
endf
