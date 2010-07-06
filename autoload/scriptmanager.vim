" see README

" TODO move code into extra file which is required ocassionally only such as
" Install and UpdateAddons


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
let s:c['activated_plugins'] = {}
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

fun! s:shellescape(s)
  return shellescape(a:s,1)
endf

" is there a library providing an OS abstraction? This breaks Winndows
" xcopy or copy should be used there..
fun! scriptmanager#Copy(f,t)
  exec '!cp -r '.s:shellescape(a:f).' '.s:shellescape(a:t)
endfun

fun! scriptmanager#Checkout(targetDir, repository)
  let addVersionFile = 'call writefile([get(a:repository,"version","?")], a:targetDir."/version")'
  if a:repository['type'] == 'git'
    let parent = fnamemodify(a:targetDir,':h')
    exec '!git clone '.s:shellescape(a:repository['url']).' '.s:shellescape(a:targetDir)
    if !isdirectory(a:targetDir)
      throw "Failed checking out ".a:targetDir."!"
    endif
  elseif a:repository['type'] == 'hg'
    let parent = fnamemodify(a:targetDir,':h')
    exec '!hg clone '.s:shellescape(a:repository['url']).' '.s:shellescape(a:targetDir)
    if !isdirectory(a:targetDir)
      throw "Failed checking out ".a:targetDir."!"
    endif
  elseif a:repository['type'] == 'svn'
    let parent = fnamemodify(a:targetDir,':h')
    exec '!cd '.s:shellescape(parent).'&& svn checkout '.s:shellescape(a:repository['url']).' '.s:shellescape(a:targetDir)
    if !isdirectory(a:targetDir)
      throw "Failed checking out ".a:targetDir."!"
    endif

  " .vim file and type syntax?
  elseif has_key(a:repository, 'archive_name')
      \ && a:repository['archive_name'] =~ '\.vim$'

    if get(a:repository,'script-type','') == 'syntax'
      let target = 'syntax'
    else
      let target = get(a:repository,'target_dir','plugin')
    endif
    call mkdir(a:targetDir.'/'.target,'p')
    let aname = s:shellescape(a:repository['archive_name'])
    exec '!cd '.s:shellescape(a:targetDir).'/'.target.' &&'
       \ .'curl -o '.aname.' '.s:shellescape(a:repository['url'])
    exec addVersionFile
    call scriptmanager#Copy(a:targetDir, a:targetDir.'.backup')

  " .tar.gz or .tgz
  elseif has_key(a:repository, 'archive_name') && a:repository['archive_name'] =~ '\.\%(tar.gz\|tgz\)$'
    call mkdir(a:targetDir)
    let aname = s:shellescape(a:repository['archive_name'])
    let s = get(a:repository,'strip-components',1)
    exec '!cd '.s:shellescape(a:targetDir).' &&'
       \ .'curl -o '.aname.' '.s:shellescape(a:repository['url']).' &&'
       \ .'tar --strip-components='.s.' -xzf '.aname
    exec addVersionFile
    call scriptmanager#Copy(a:targetDir, a:targetDir.'.backup')


  " .tar
  elseif has_key(a:repository, 'archive_name') && a:repository['archive_name'] =~ '\.tar$'
    call mkdir(a:targetDir)
    let aname = s:shellescape(a:repository['archive_name'])
    exec '!cd '.s:shellescape(a:targetDir).' &&'
       \ .'curl -o '.aname.' '.s:shellescape(a:repository['url']).' &&'
       \ .'tar --strip-components=1 -xf '.aname
    exec addVersionFile
    call scriptmanager#Copy(a:targetDir, a:targetDir.'.backup')

  " .zip
  elseif has_key(a:repository, 'archive_name') && a:repository['archive_name'] =~ '\.zip$'
    call mkdir(a:targetDir)
    let aname = s:shellescape(a:repository['archive_name'])
    exec '!cd '.s:shellescape(a:targetDir).' &&'
       \ .'curl -o '.aname.' '.s:shellescape(a:repository['url']).' &&'
       \ .'unzip '.aname
    exec addVersionFile
    call scriptmanager#Copy(a:targetDir, a:targetDir.'.backup')

  " .vba reuse vimball#Vimball() function
  elseif has_key(a:repository, 'archive_name') && a:repository['archive_name'] =~ '\.vba\%(\.gz\)\?$'
    call mkdir(a:targetDir)
    let a = a:repository['archive_name']
    let aname = s:shellescape(a)
    exec '!cd '.s:shellescape(a:targetDir).' &&'
       \ .'curl -o '.aname.' '.s:shellescape(a:repository['url'])
    if a =~ '\.gz'
      " manually unzip .vba.gz as .gz isn't unpacked yet for some reason
      exec '!gunzip '.a:targetDir.'/'.a
      let a = a[:-4]
    endif
    exec 'sp '.a:targetDir.'/'.a
    call vimball#Vimball(1,a:targetDir)
    exec addVersionFile
    call scriptmanager#Copy(a:targetDir, a:targetDir.'.backup')
  else
    throw "Don't know how to checkout source location: ".string(a:repository)."!"
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

fun! scriptmanager#LoadKnownRepos()
  let known = s:c['known']
  if 0 == get(s:c['activated_plugins'], known, 0) && input('Activate plugin '.known.' to get more plugin sources? [y/n]:','') == 'y'
    call scriptmanager#Activate([known])
    " this should be done by Activate!
    exec 'source '.scriptmanager#PluginDirByName(known).'/plugin/vim-addon-manager-known-repositories.vim'
  endif
endf

fun! scriptmanager#UninstallAddons(list)
  let list = a:list
  if list == []
    echo "No plugins selected. If you ran UninstallNotLoadedAddons use <tab> or <c-d> to get a list of not loaded plugins."
    return
  endif
  call map(list, 'scriptmanager#PluginDirByName(v:val)')
  if input('Confirm running rm -fr on directories: '.join(list,", ").'? [y/n]') == 'y'
    for path in list
      exec '!rm -fr '.s:shellescape(path)
    endfor
  endif
endf

fun! scriptmanager#HelpTags(name)
  let d=scriptmanager#PluginDirByName(a:name).'/doc'
  if isdirectory(d) | exec 'helptags '.d | endif
endf

" {} if file dosen't exist
fun! scriptmanager#AddonInfo(name)
  let infoFile = scriptmanager#AddonInfoFile(a:name)
  let s:c['addon_infos'][a:name] = filereadable(infoFile)
    \ ? scriptmanager#ReadAddonInfo(infoFile)
    \ : {}
 return get(s:c['addon_infos'],a:name, {})
endf

" Install let's you install plugins by passing the url of a addon-info file
" This preprocessor replaces the urls by the plugin-names putting the
" repository information into the global dict
fun! scriptmanager#ReplaceAndFetchUrls(list)
  let l = a:list
  let idx = 0
  for idx in range(0, len(l)-1)
    silent! unlet t
    let n = l[idx]
    " assume n is either an url or a path
    if n =~ '^http://' && 'y' == input('Fetch plugin info from url '.n.' [y/n]')
      let t = tempfile()
      exec '!curl '.t.' > '.s:shellescape(t)
    elseif n =~  '[/\\]' && filereadable(n)
      let t = n
    endif
    if exists('t')
      let dic = scriptmanager#ReadAddonInfo(t)
      if !has_key(dic,'name') || !has_key(dic, 'repository')
        echoe n." is no valid addon-info file. It must contain both keys: name and repository"
        continue
      endif
      let s:c['plugin_sources'][dic['name']] = dic['repository']
      let l[idx] = dic['name']
    endif
  endfor
  return l
endfun

" opts: same as Activate
fun! scriptmanager#Install(toBeInstalledList, ...)
  let toBeInstalledList = scriptmanager#ReplaceAndFetchUrls(a:toBeInstalledList)
  let opts = a:0 == 0 ? {} : a:1
  for name in toBeInstalledList
    if scriptmanager#IsPluginInstalled(name)
      continue
    endif

    " ask user for to confirm installation unless he set auto_install
    if s:c['auto_install'] || get(opts,'auto_install',0) || input('Install plugin '.name.'? [y/n]:','') == 'y'

      if name != s:c['known'] | call scriptmanager#LoadKnownRepos() | endif

      let repository = get(s:c['plugin_sources'], name, get(opts, name,0))

      if type(repository) == type(0) && repository == 0
        throw "No repository location info known for plugin ".name."!"
      endif

      let d = get(repository, 'deprecated', '')
      if type(d) == type('') && d != ''
        echom "Deprecation warning package ".name. ":"
        echom d
        if 'y' != input('Plugin '.name.' is deprecated. See warning above. Install it? [y/n]','n')
          continue
        endif
      endif

      let pluginDir = scriptmanager#PluginDirByName(name)
      let infoFile = scriptmanager#AddonInfoFile(name)
      call scriptmanager#Checkout(pluginDir, repository)

      if !filereadable(infoFile) && has_key(s:c['missing_addon_infos'], name)
        call writefile([s:c['missing_addon_infos'][name]], infoFile)
      endif

      " install dependencies
     
      let infoFile = scriptmanager#AddonInfoFile(name)
      let info = scriptmanager#AddonInfo(name)

      let dependencies = get(info,'dependencies', {})

      " install dependencies merging opts with given repository sources
      " sources given in opts will win
      call scriptmanager#Install(keys(dependencies),
        \ extend(copy(opts), { 'plugin_sources' : extend(copy(dependencies), get(opts, 'plugin_sources',{}))}))
    endif
    call scriptmanager#HelpTags(name)
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

      let infoFile = scriptmanager#AddonInfoFile(name)
      if !filereadable(infoFile)
        call scriptmanager#Install([name], opts)
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

fun! scriptmanager#UpdateAddon(name)
  let directory = scriptmanager#PluginDirByName(a:name)
  if isdirectory(directory.'/.git')
    exec '!cd '.s:shellescape(directory).'&& git pull'
    return !v:shell_error
  elseif isdirectory(directory.'/.svn')
    exec '!cd '.s:shellescape(directory).'&& svn update'
    return !v:shell_error
  elseif isdirectory(directory.'/.hg')
    exec '!cd '.s:shellescape(directory, 1).'&& hg pull'
    return !v:shell_error
  else
    echoe "Updating plugin ".a:name." not implemented yet."
    return 0
  endif
endf


fun! scriptmanager#Update(list)
  let list = a:list
  if empty(list) && input('Update all loaded plugins? [y/n] ','y') == 'y'
    let list = keys(s:c['activated_plugins'])
  endif
  let failed = []
  for p in list
    if scriptmanager#UpdateAddon(p)
      call scriptmanager#HelpTags(p)
    else
      call add(failed,p)
    endif
  endfor
  if !empty(failed)
    echoe "Failed updating plugins: ".string(failed)."."
  endif
endf

" completion {{{

" optional arg = 0: only installed
"          arg = 1: installed and names from known-repositories
fun! scriptmanager#KnownAddons(...)
  let installable = a:0 > 0 ? a:1 : 0
  let list = map(split(glob(scriptmanager#PluginDirByName('*')),"\n"),"fnamemodify(v:val,':t')")
  let list = filter(list, 'isdirectory(v:val)')
  if installable == "installable"
    call scriptmanager#LoadKnownRepos()
    call extend(list, keys(s:c['plugin_sources']))
  endif
  " uniq items:
  let dict = {}
  for name in list
    let dict[name] = 1
  endfor
  return keys(dict)
endf

fun! s:DoCompletion(A,L,P,...)
  let config = a:0 > 0 ? a:1 : 0
  let names = scriptmanager#KnownAddons(config)

  let beforeC= a:L[:a:P-1]
  let word = matchstr(beforeC, '\zs\S*$')
  " ollow glob patterns 
  let word = substitute('\*','.*',word,'g')

  let not_loaded = config == "uninstall"
    \ ? " && index(keys(s:c['activated_plugins']), v:val) == -1"
    \ : ''

  return filter(names,'v:val =~ '.string(word) . not_loaded)
endf

fun! s:AddonCompletion(...)
  return call('s:DoCompletion',a:000+["installable"])
endf

fun! s:InstalledAddonCompletion(...)
  return call('s:DoCompletion',a:000)
endf

fun! s:UninstallCompletion(...)
  return call('s:DoCompletion',a:000+["uninstall"])
endf
"}}}

command! -nargs=* -complete=customlist,s:AddonCompletion ActivateAddons :call scriptmanager#Activate([<f-args>])
command! -nargs=* -complete=customlist,s:InstalledAddonCompletion ActivateInstalledAddons :call scriptmanager#Activate([<f-args>])
command! -nargs=* -complete=customlist,s:AddonCompletion UpdateAddons :call scriptmanager#Update([<f-args>])
command! -nargs=* -complete=customlist,s:UninstallCompletion UninstallNotLoadedAddons :call scriptmanager#UninstallAddons([<f-args>])

