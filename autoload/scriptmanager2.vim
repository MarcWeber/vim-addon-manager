" scriptmanager2 contains code which is used when install plugins only

exec scriptmanager#DefineAndBind('s:c','g:vim_script_manager','{}')

" let users override curl command. Reuse netrw setting
let s:curl = exists('g:netrw_http_cmd') ? g:netrw_http_cmd : 'curl -o'

" Install let's you install plugins by passing the url of a addon-info file
" This preprocessor replaces the urls by the plugin-names putting the
" repository information into the global dict
fun! scriptmanager2#ReplaceAndFetchUrls(list)
  let l = a:list
  let idx = 0
  for idx in range(0, len(l)-1)
    silent! unlet t
    let n = l[idx]
    " assume n is either an url or a path
    if n =~ '^http://' && 'y' == input('Fetch plugin info from url '.n.' [y/n]')
      let t = tempfile()
      exec '!'.s:curl.' '.t.' > '.s:shellescape(t)
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
fun! scriptmanager2#Install(toBeInstalledList, ...)
  let toBeInstalledList = scriptmanager2#ReplaceAndFetchUrls(a:toBeInstalledList)
  let opts = a:0 == 0 ? {} : a:1
  for name in toBeInstalledList
    if scriptmanager#IsPluginInstalled(name)
      continue
    endif

    " ask user for to confirm installation unless he set auto_install
    if s:c['auto_install'] || get(opts,'auto_install',0) || input('Install plugin '.name.'? [y/n]:','') == 'y'

      if name != s:c['known'] | call scriptmanager2#LoadKnownRepos() | endif

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
      call scriptmanager2#Checkout(pluginDir, repository)

      if !filereadable(infoFile) && has_key(s:c['missing_addon_infos'], name)
        call writefile([s:c['missing_addon_infos'][name]], infoFile)
      endif

      " install dependencies
     
      let infoFile = scriptmanager#AddonInfoFile(name)
      let info = scriptmanager#AddonInfo(name)

      let dependencies = get(info,'dependencies', {})

      " install dependencies merging opts with given repository sources
      " sources given in opts will win
      call scriptmanager2#Install(keys(dependencies),
        \ extend(copy(opts), { 'plugin_sources' : extend(copy(dependencies), get(opts, 'plugin_sources',{}))}))
    endif
    call scriptmanager2#HelpTags(name)
  endfor
endf

fun! scriptmanager2#UpdateAddon(name)
  let directory = scriptmanager#PluginDirByName(a:name)
  return vcs_checkouts#Update(directory)
endf

fun! scriptmanager2#Update(list)
  let list = a:list
  if empty(list) && input('Update all loaded plugins? [y/n] ','y') == 'y'
    call scriptmanager2#LoadKnownRepos(' so that its updated as well')
    let list = keys(s:c['activated_plugins'])
  endif
  let failed = []
  for p in list
    if scriptmanager2#UpdateAddon(p)
      call scriptmanager2#HelpTags(p)
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
fun! scriptmanager2#KnownAddons(...)
  let installable = a:0 > 0 ? a:1 : 0
  let list = map(split(glob(scriptmanager#PluginDirByName('*')),"\n"),"fnamemodify(v:val,':t')")
  let list = filter(list, 'isdirectory(v:val)')
  if installable == "installable"
    call scriptmanager2#LoadKnownRepos()
    call extend(list, keys(s:c['plugin_sources']))
  endif
  " uniq items:
  let dict = {}
  for name in list
    let dict[name] = 1
  endfor
  return keys(dict)
endf

fun! scriptmanager2#DoCompletion(A,L,P,...)
  let config = a:0 > 0 ? a:1 : 0
  let names = scriptmanager2#KnownAddons(config)

  let beforeC= a:L[:a:P-1]
  let word = matchstr(beforeC, '\zs\S*$')
  " ollow glob patterns 
  let word = substitute('\*','.*',word,'g')

  let not_loaded = config == "uninstall"
    \ ? " && index(keys(s:c['activated_plugins']), v:val) == -1"
    \ : ''

  return filter(names,'v:val =~ '.string(word) . not_loaded)
endf

fun! scriptmanager2#AddonCompletion(...)
  return call('scriptmanager2#DoCompletion',a:000+["installable"])
endf

fun! scriptmanager2#InstalledAddonCompletion(...)
  return call('scriptmanager2#DoCompletion',a:000)
endf

fun! scriptmanager2#UninstallCompletion(...)
  return call('scriptmanager2#DoCompletion',a:000+["uninstall"])
endf
"}}}


fun! scriptmanager2#UninstallAddons(list)
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

fun! scriptmanager2#HelpTags(name)
  let d=scriptmanager#PluginDirByName(a:name).'/doc'
  if isdirectory(d) | exec 'helptags '.d | endif
endf

fun! scriptmanager2#Checkout(targetDir, repository)
  let addVersionFile = 'call writefile([get(a:repository,"version","?")], a:targetDir."/version")'
  if a:repository['type'] =~ 'git\|hg\|svn'
    call vcs_checkouts#Checkout(a:targetDir, a:repository)

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
    call s:exec_in_dir([{'d':  a:targetDir.'/'.target, 'c': s:curl.' '.aname.' '.s:shellescape(a:repository['url'])}])
    exec addVersionFile
    call scriptmanager2#Copy(a:targetDir, a:targetDir.'.backup')

  " .tar.gz or .tgz
  elseif has_key(a:repository, 'archive_name') && a:repository['archive_name'] =~ '\.\%(tar.gz\|tgz\)$'
    call mkdir(a:targetDir)
    let aname = s:shellescape(a:repository['archive_name'])
    let s = get(a:repository,'strip-components',1)
    call s:exec_in_dir([{'d':  a:targetDir, 'c': s:curl.' '.aname.' '.s:shellescape(a:repository['url'])}
          \ , {'c': 'tar --strip-components='.s.' -xzf '.aname}])
    exec addVersionFile
    call scriptmanager2#Copy(a:targetDir, a:targetDir.'.backup')


  " .tar
  elseif has_key(a:repository, 'archive_name') && a:repository['archive_name'] =~ '\.tar$'
    call mkdir(a:targetDir)
    let aname = s:shellescape(a:repository['archive_name'])
    call s:exec_in_dir([{'d':  a:targetDir, 'c': s:curl.' '.aname.' '.s:shellescape(a:repository['url'])}
          \ , {'c': 'tar --strip-components='.s.' -xzf '.aname}])
    exec addVersionFile
    call scriptmanager2#Copy(a:targetDir, a:targetDir.'.backup')

  " .zip
  elseif has_key(a:repository, 'archive_name') && a:repository['archive_name'] =~ '\.zip$'
    call mkdir(a:targetDir)
    let aname = s:shellescape(a:repository['archive_name'])
    call s:exec_in_dir([{'d':  a:targetDir, 'c': s:curl.' '.s:shellescape(a:targetDir).'/'.aname.' '.s:shellescape(a:repository['url'])}
       \ , {'c': 'unzip '.aname } ])
    exec addVersionFile
    call scriptmanager2#Copy(a:targetDir, a:targetDir.'.backup')

  " .vba reuse vimball#Vimball() function
  elseif has_key(a:repository, 'archive_name') && a:repository['archive_name'] =~ '\.vba\%(\.gz\)\?$'
    call mkdir(a:targetDir)
    let a = a:repository['archive_name']
    let aname = s:shellescape(a)
    call s:exec_in_dir([{'d':  a:targetDir, 'c': s:curl.' '.aname.' '.s:shellescape(a:repository['url'])}])
    if a =~ '\.gz'
      " manually unzip .vba.gz as .gz isn't unpacked yet for some reason
      exec '!gunzip "'.a:targetDir.'/'.a.'"'
      let a = a[:-4]
    endif
    exec 'sp '.a:targetDir.'/'.a
    call vimball#Vimball(1,a:targetDir)
    exec addVersionFile
    call scriptmanager2#Copy(a:targetDir, a:targetDir.'.backup')
  else
    throw "Don't know how to checkout source location: ".string(a:repository)."!"
  endif
endf

fun! s:shellescape(s)
  return shellescape(a:s,1)
endf

" cmds = list of {'d':  dir to run command in, 'c': the command line to be run }
fun! s:exec_in_dir(cmds)
  call vcs_checkouts#ExecIndir(a:cmds)
endf

" is there a library providing an OS abstraction? This breaks Winndows
" xcopy or copy should be used there..
fun! scriptmanager2#Copy(f,t)
  if has('win16') || has('win32') || has('win64')
    exec '!xcopy /e /i '.s:shellescape(a:f).' '.s:shellescape(a:t)
  else
    exec '!cp -r '.s:shellescape(a:f).' '.s:shellescape(a:t)
  endif
endfun


fun! scriptmanager2#LoadKnownRepos(...)
  let known = s:c['known']
  let reason = a:0 > 0 ? a:1 : 'get more plugin sources'
  if 0 == get(s:c['activated_plugins'], known, 0) && input('Activate plugin '.known.' to '.reason.'? [y/n]:','') == 'y'
    call scriptmanager#Activate([known])
    " this should be done by Activate!
    exec 'source '.scriptmanager#PluginDirByName(known).'/plugin/vim-addon-manager-known-repositories.vim'
  endif
endf


fun! scriptmanager2#MergeTarget()
  return split(&runtimepath,",")[0].'/after/plugin/vim-addon-manager-merged.vim'
endf

" if you machine is under IO load starting up Vim can take some time
" This function tries to optimize this by reading all the plugin/*.vim
" files joining them to one vim file.
"
" 1) rename plugin to plugin-merged (so that they are no longer sourced by Vim)
" 2) read plugin/*.vim_merged files
" 3) replace clashing s:name vars by uniq names
" 4) rewrite the guards (everything containing finish)
" 5) write final merged file to ~/.vim/after/plugin/vim-addon-manager-merged.vim
"    so that its sourced automatically
"
" TODO: take after plugins int account?
fun! scriptmanager2#MergePluginFiles(plugins, skip_pattern)
  if !filereadable('/bin/sh')
    throw "you should be using Linux.. This code is likely to break on other operating systems!"
  endif

  let target = scriptmanager2#MergeTarget()

  for r in a:plugins
    if !has_key(s:c['activated_plugins'], r)
      throw "JoinPluginFiles: all plugins must be activated (which ensures that they have been installed). This plugin is not active: ".r
    endif
  endfor

  let runtimepaths = map(copy(a:plugins), 'scriptmanager#PluginRuntimePath(v:val)')

  " 1)
  for r in runtimepaths
    if (isdirectory(r.'/plugin'))
      call s:exec_in_dir([{'c':'mv '.s:shellescape(r.'/plugin').' '.s:shellescape(r.'/plugin-merged')}])
    endif
  endfor

  " 2)
  let file_local_vars = {}
  let uniq = 1
  let all_contents = ""
  for r in runtimepaths
    for file in split(glob(r.'/plugin-merged/*.vim'),"\n")

      if file =~ a:skip_pattern
        let all_contents .= "\" ignoring ".file."\n"
        continue
      endif

      let names_this_file = {}
      let contents =join(readfile(file, 'b'),"\n")
      for l in split("s:abc s:foobar",'\ze\<s:')[1:]
        let names_this_file[matchstr(l,'^s:\zs[^ [(=)\]]*')] = 1
      endfor
      " handle duplicate local vars: 3)
      for k in keys(names_this_file)
        if has_key(file_local_vars, k)
          let new = 'uniq_'.uniq
          let uniq += 1
          let file_local_vars[new] = 1
          let contents = "\" replaced: ".k." by ".new."\n".substitute(contents, 's:'.k,'s:'.new,'g')
        else
          let file_local_vars[k] = 1
        endif
      endfor

      " find finish which start at the end of a line.
      " They are often used to separated Vim code from additional info such as
      " history (eg tlib is using it). Comment remaining lines
      let lines = split(contents,"\n")
      let comment = 0
      for i in range(0,len(lines)-1)
        if lines[i] =~ '^finish'
          let comment = 1
        endif
        if comment
          let lines[i] = "\" ".lines[i]
        endif
      endfor
      let contents = join(lines,"\n")

      " guards 4)
      " find guards replace them by if .. endif blocks
      let lines = split(contents,"\n")
      for i in range(2,len(lines)-1)
        if lines[i] =~ '^\s*finish' && lines[i-1] =~ '^\s*if\s'
          " found a guard
          
          " negate if, remove {{{ if present (I don't care)
          let lines[i-1] = 'if !('.matchstr(substitute(lines[i-1],'"[^"]*{{{.*','',''),'if\s*\zs.*').')'
          let j = i+1
          while j < len(lines) && lines[j] !~ '^\s*endif'
            let lines[j] = ''
            let j = j+1
          endwhile
          let lines[j] = ''
          " guards are never longer than 10 lines
          if j - i > 10
            throw "something probably has gone wrong while removing guard for file".file." start at line: ".i
          endif
          call add(lines,'endif')
          let contents = join(lines,"\n")
          break
        endif
      endfor


      " comment remaining finish lines. This does not catch if .. | finish | endif and such
      " :-(
      " adding additional \n because not all scripts have a final \n..
      let contents = substitute(contents, '\<finish\>','" finish','g')
      let all_contents .= "\n"
            \ ."\"merged: ".file."\n"
            \ .contents
            \ ."\n"
            \ ."\"merged: ".file." end\n"
    endfor
  endfor

  let d =fnamemodify(target,':h')
  if !isdirectory(d) | call mkdir(d,'p') | endif
  call writefile(split(all_contents,"\n"), target)

endf

fun! scriptmanager2#UnmergePluginFiles()
  let path = fnamemodify(scriptmanager#PluginRuntimePath('vim-addon-manager'),':h')
  for merged in split(glob(path.'/*/plugin-merged'),"\n")
            \ +split(glob(path.'/*/*/plugin-merged'),"\n")
    echo "unmerging ".merged
    call rename(merged, substitute(merged,'-merged$','',''))
  endfor
  call delete(scriptmanager2#MergeTarget())
endfun
