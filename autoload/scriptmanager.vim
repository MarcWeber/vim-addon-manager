" see README

" this file contains code which is always used
" code which is used for installing / updating etc should go into scriptmanager2.vim


" don't need a plugin. If you want to use this plugin you call Activate once
" anyway
augroup SCRIPT_MANAGER
  autocmd BufRead,BufNewFile *-addon-info.txt
    \ setlocal ft=addon-info
    \ | setlocal syntax=json
    \ | syn match Error "^\s*'"
  autocmd BufWritePost *-addon-info.txt call scriptmanager#ReadAddonInfo(expand('%'))
augroup end

fun! scriptmanager#DefineAndBind(local,global,default)
  return 'if !exists('.string(a:global).') | let '.a:global.' = '.a:default.' | endif | let '.a:local.' = '.a:global
endf


exec scriptmanager#DefineAndBind('s:c','g:vim_script_manager','{}')
let s:c['config'] = get(s:c,'config',expand('$HOME').'/.vim-script-manager')
let s:c['auto_install'] = get(s:c,'auto_install', 0)
" repository locations:
let s:c['plugin_sources'] = get(s:c,'plugin_sources', {})
" if a plugin has an item here the dict value contents will be written as plugin info file
let s:c['missing_addon_infos'] = get(s:c,'missing_addon_infos', {})
" addon_infos cache, {} if file dosen't exist
let s:c['addon_infos'] = get(s:c,'addon_infos', {})
let s:c['activated_plugins'] = get(s:c,'activaded_plugins', {})
let s:c['plugin_root_dir'] = fnamemodify(expand('<sfile>'),':h:h:h')
let s:c['known'] = get(s:c,'known','vim-addon-manager-known-repositories')

" additional plugin sources should go into your .vimrc or into the repository
" called "vim-addon-manager-known-repositories" referenced here:
let s:c['plugin_sources']["vim-addon-manager-known-repositories"] = { 'type' : 'git', 'url': 'git://github.com/MarcWeber/vim-addon-manager-known-repositories.git' }

fun! scriptmanager#VerifyIsJSON(s)
  let stringless_body = substitute(a:s,'"\%(\\.\|[^"\\]\)*"','','g')
  return stringless_body !~# "[^,:{}\\[\\]0-9.\\-+Eaeflnr-u \t]"
endf

" use join so that you can break the dict into multiple lines. This makes
" reading it much easier
fun! scriptmanager#ReadAddonInfo(path)
  if a:path =~ 'tlib/plugin-info.txt$'
    " I'll ask Tom Link to change this when vim-addon-manager is more stable
    return eval(join(readfile(a:path, "b"),""))
  endif

  " using eval is evil!
  let body = join(readfile(a:path, "b"),"")

  if scriptmanager#VerifyIsJSON(body)
      " using eval is now safe!
      return eval(body)
  else
      throw "Invalid JSON in ".a:path."!"
  endif

endf

fun! scriptmanager#PluginDirByName(name)
  return s:c['plugin_root_dir'].'/'.a:name
endf
fun! scriptmanager#PluginRuntimePath(name)
  let info = scriptmanager#AddonInfo(a:name)
  return s:c['plugin_root_dir'].'/'.a:name.(has_key(info, 'runtimepath') ? '/'.info['runtimepath'] : '')
endf

" doesn't check dependencies!
fun! scriptmanager#IsPluginInstalled(name)
  return isdirectory(scriptmanager#PluginDirByName(a:name))
endf

" {} if file dosen't exist
fun! scriptmanager#AddonInfo(name)
  let infoFile = scriptmanager#AddonInfoFile(a:name)
  let s:c['addon_infos'][a:name] = filereadable(infoFile)
    \ ? scriptmanager#ReadAddonInfo(infoFile)
    \ : {}
 return get(s:c['addon_infos'],a:name, {})
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

      let infoFile = scriptmanager#AddonInfoFile(name)
      if !filereadable(infoFile) && !scriptmanager#IsPluginInstalled(name)
        call scriptmanager2#Install([name], opts)
      endif
      let info = scriptmanager#AddonInfo(name)
      let dependencies = get(info,'dependencies', {})

      " activate dependencies merging opts with given repository sources
      " sources given in opts will win
      call scriptmanager#Activate(keys(dependencies),
        \ extend(copy(opts), { 'plugin_sources' : extend(copy(dependencies), get(opts, 'plugin_sources',{}))}))
    endif
    " source plugin/* files ?
    let rtp = scriptmanager#PluginRuntimePath(name)
    call add(s:new_runtime_paths, rtp)

    let s:c['activated_plugins'][name] = 1
  endfor
endf

" see also ActivateRecursively
" Activate activates the plugins and their dependencies recursively.
" I sources both: plugin/*.vim and after/plugin/*.vim files when called after
" .vimrc has been sourced which happens when you activate plugins manually.
fun! scriptmanager#Activate(...)
  let args = copy(a:000)
  let opts = get(args,1,{})
  if len(args) <= 1
    call add(args, opts)
  endif
  let topLevel = get(opts,'topLevel',1)
  let opts['topLevel'] = 0
  let active = copy(s:c['activated_plugins'])
  if topLevel | let s:new_runtime_paths = [] | endif
  call call('scriptmanager#ActivateRecursively', args)

  if topLevel
    " deferred tasks:
    " - add addons to runtimepath
    " - add source plugin/**/*.vim files in case Activate was called long
    "   after .vimrc has been sourced

    " add paths after ~/.vim but before $VIMRUNTIME
    " don't miss the after directories if they exist and
    " put them last! (Thanks to Oliver Teuliere)
    let rtp = split(&runtimepath,',')
    let &runtimepath=join(rtp[:0] + s:new_runtime_paths + rtp[1:]
                                  \ + filter(map(copy(s:new_runtime_paths),'v:val."/after"'), 'isdirectory(v:val)') ,",")
    unlet rtp

    if has_key(s:c, 'started_up')
      for rtp in s:new_runtime_paths
        call scriptmanager#GlobThenSource(rtp.'/plugin/**/*.vim')
        call scriptmanager#GlobThenSource(rtp.'/after/plugin/**/*.vim')
      endfor
    endif
  endif

  if has_key(s:c, 'started_up')
    " now source after/plugin/**/*.vim files explicitely. Vim doesn't do it (hack!)
    for k in keys(s:c['activated_plugins'])
      if !has_key(active, k)
        let rtp = scriptmanager#PluginRuntimePath(k)
        call scriptmanager#GlobThenSource(rtp.'/plugin/**/*.vim')
        call scriptmanager#GlobThenSource(rtp.'/after/plugin/**/*.vim')
      endif
    endfor
  endif
endfun

fun! scriptmanager#GlobThenSource(glob)
  for file in split(glob(a:glob),"\n")
    exec 'source '.file
  endfor
endf

augroup VIM_PLUGIN_MANAGER
  autocmd VimEnter * call  scriptmanager#Hack()
augroup end

" hack: Vim sources plugin files after sourcing .vimrc
"       Vim doesn't source the after/plugin/*.vim files in other runtime
"       paths. So do this *after* plugin/* files have been sourced
fun! scriptmanager#Hack()
  let s:c['started_up'] = 1

  " now source after/plugin/**/*.vim files explicitly. Vim doesn't do it (hack!)
  for p in keys(s:c['activated_plugins'])
      call scriptmanager#GlobThenSource(scriptmanager#PluginDirByName(p).'/after/plugin/**/*.vim')
  endfor
endf

fun! scriptmanager#AddonInfoFile(name)
  " this name is deprecated
  let f = scriptmanager#PluginDirByName(a:name).'/plugin-info.txt'
  if filereadable(f)
    return f
  else
    return scriptmanager#PluginDirByName(a:name).'/'.a:name.'-addon-info.txt'
  endif
endf

command! -nargs=* -complete=customlist,scriptmanager2#AddonCompletion ActivateAddons :call scriptmanager#Activate([<f-args>])
command! -nargs=* -complete=customlist,scriptmanager2#InstalledAddonCompletion ActivateInstalledAddons :call scriptmanager#Activate([<f-args>])
command! -nargs=* -complete=customlist,scriptmanager2#AddonCompletion UpdateAddons :call scriptmanager2#Update([<f-args>])
command! -nargs=* -complete=customlist,scriptmanager2#UninstallCompletion UninstallNotLoadedAddons :call scriptmanager2#UninstallAddons([<f-args>])

