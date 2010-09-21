" scriptmanager2 contains code which is used when install plugins only

let s:curl = exists('g:netrw_http_cmd') ? g:netrw_http_cmd : 'curl -o'
exec scriptmanager#DefineAndBind('s:c','g:vim_script_manager','{}')


let s:system_wide = !filewritable(expand('<sfile>'))

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

    let pluginDir = scriptmanager#PluginDirByName(name)
    " ask user for to confirm installation unless he set auto_install
    if s:c['auto_install'] || get(opts,'auto_install',0) || input('Install plugin "'.name.'" into "'.s:c['plugin_root_dir'].'" ? [y/n]:','') == 'y'

      if name != s:c['known'] | call scriptmanager2#LoadKnownRepos() | endif

      let repository = get(s:c['plugin_sources'], name, get(opts, name,0))

      if type(repository) == type(0) && repository == 0
        echoe "No repository location info known for plugin ".name."!"
        return
      endif

      let d = get(repository, 'deprecated', '')
      if type(d) == type('') && d != ''
        echom "Deprecation warning package ".name. ":"
        echom d
        if 'y' != input('Plugin '.name.' is deprecated. See warning above. Install it? [y/n]','n')
          continue
        endif
      endif

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

" this function will be refactored slightly soon by either me or Zyx.
fun! scriptmanager2#UpdateAddon(name)
  let pluginDir = scriptmanager#PluginDirByName(a:name)
  if !vcs_checkouts#Update(pluginDir)
    " try updating plugin by archive
    
    " dose the user have made any changes? :
    let pluginDir = scriptmanager#PluginDirByName(a:name)
    let backup = scriptmanager#PluginDirByName(a:name).'.backup'
    let container = fnamemodify(backup,':h')
    let diff_file = containing.'/'.a:name.'.diff-orig'

    if executable('diff') && isdirectory(backup)
      call s:exec_in_dir([{'c':'diff -r '.s:shellescape(r.'/plugin').' '.s:shellescape(r.'/plugin-merged')}])
    endif
    
    if filereadable(pluginDir.'/version')
      let pluginversion = get(readfile(pluginDir.'/version'), 0, "?")
      let repository = get(s:c['plugin_sources'], a:name, {})
      if empty(repository)
        echoe "Cannot update plugin ".a:name.": no repository locations known."
        return
      endif
      let newpluginversion = get(repository, 'version', '?')
      if newpluginversion==#'?'
        echoe "Cannot update plugin ".a:name.": no version information is available."
      elseif pluginversion==#newpluginversion
        " Though we are not updating plugin, this is not an error
        return 1
      endif
      if scriptmanager2#Checkout(pluginDir, repository)
        return
      endif
      return 1
    endif
    return
  endif
  return 1
endf

fun! scriptmanager2#Update(list)
  let list = a:list
  if empty(list) && input('Update all loaded plugins? [y/n] ','y') == 'y'
    call scriptmanager2#LoadKnownRepos(' so that its updated as well')
    " include vim-addon-manager in list
    if !s:system_wide
      call scriptmanager#Activate(['vim-addon-manager'])
    endif
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

" " if --strip-components fails finish this workaround:
" " emulate it in VimL
" fun! s:StripComponents(targetDir, num)
"   let dostrip = 1*a:num
"   while x in range(1, 1*a:num)
"     let dirs = split(glob(a:targetDir.'/*'),"\n")
"     if len(dirs) > 1
"       throw "can't strip, multiple dirs found!"
"     endif
"     for f in split(glob(dirs[0].'/*'),"\n")
"       call rename(file_or_dir, fnamemodify(f,':h:h').'/'.fnamemodify(f,':t'))
"     endfor
"     call remove_dir_or_file(fnamemodify(f,':h'))
"   endwhile
" endfun


" may throw EXCEPTION_UNPACK
fun! scriptmanager2#Checkout(targetDir, repository) abort
  if get(a:repository,'type','') =~ 'git\|hg\|svn'
    call vcs_checkouts#Checkout(a:targetDir, a:repository)
  else
    " archive based repositories - no VCS
    " must have a:repository['archive_name']

    if !isdirectory(a:targetDir) | call mkdir(a:targetDir.'/archive','p') | endif

    " basename VIM -> vim
    let archiveName = fnamemodify(substitute(get(a:repository,'archive_name',''), '\.\zsVIM$', 'vim', ''),':t')
    if archiveName == ''
      let archiveName = fnamemodify(a:repository['url'],':t')
    endif

    " archive will be downloaded to this location
    let archiveFile = a:targetDir.'/archive/'.archiveName

    call scriptmanager_util#Download(a:repository['url'], archiveFile)

    call scriptmanager_util#Unpack(archiveFile, a:targetDir,{ 'strip-components': get(a:repository,'strip-components',-1) })

    call writefile([get(a:repository,"version","?")], a:targetDir."/version")

    " hook for plugin / syntax files: Move into the correct direcotry:
    if a:repository['archive_name'] =~? '\.vim$' 
      let type = tolower(get(a:repository,'script-type',''))
      if type  =~# '^syntax\|indent\|ftplugin$'
        let dir = a:targetDir.'/'.type
        call mkdir(dir)
        call rename(a:targetDir.'/'.archiveName, dir.'/'.archiveName)
      endif
    endif
  endif
endfun

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
  if g:is_win
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


if g:is_win
  fun! scriptmanager2#FetchAdditionalWindowsTools() abort
    if !executable("curl") && s:curl == "curl -o"
      throw "No curl found. Either set g:netrw_http_cmd='path/curl -o' or put it in PATH"
    endif
    if !isdirectory(s:c['binary_utils'].'\dist')
      call mkdir(s:c['binary_utils'].'\dist','p')
    endif
    " we have curl, so we can fetch remaingin deps using Download and Unpack
    let tools = {
      \ 'gzip': ['mirror://sourceforge/gnuwin32/gzip/1.3.12-1/', "gzip-1.3.12-1-bin.zip", ["gzip", "7z"]],
      \ 'bzip2':['mirror://sourceforge/gnuwin32/bzip2/1.0.5/', "bzip2-1.0.5-bin.zip", ["bzip2", "7z"] ],
      \ 'tar':  ['mirror://sourceforge/gnuwin32/tar/1.13-1/',"tar-1.13-1-bin.zip", ["tar", "7z"] ],
      \ 'zip':  ['mirror://sourceforge/gnuwin32/unzip/5.51-1/', "unzip-5.51-1-bin.zip", ["unzip","7z"] ],
      \ 'diffutils': ['mirror://sourceforge/gnuwin32/diffutils/2.8.7-1/',"diffutils-2.8.7-1-bin.zip", "diff"],
      \ 'patch': [ 'mirror://sourceforge/gnuwin32/patch/2.5.9-7/',"patch-2.5.9-7-bin.zip", "patch"]
      \ }
    for v in values(tools)
      echo "downloading ".v[1]
      for ex in v[2]
        if executable(ex) | continue | endif
      endfor
      if !filereadable(s:c['binary_utils'].'\'.v[1])
        call scriptmanager_util#DownloadFromMirrors(v[0].v[1], s:c['binary_utils'])
      endif
    endfor

    if !executable('unzip')
      " colorize this?
      echo "__ its your turn: __"
      echom "__ move all files of the zip directory into ".s:c['binary_utils'].'/dist . Close the Explorer window and the shell window to continue. Press any key'
      call getchar()
      exec "!".expand(s:c['binary_utils'].'/'. tools.zip[1])
      let $PATH=$PATH.';'.s:c['binary_utils_bin']
      if !executable('unzip')
        throw "can't execute unzip. Something failed!"
      endif
    endif

    " now we have unzip and can do rest
    for k in ["gzip","bzip2","tar","diffutils","patch"]
      if !executable(tools[k][2])
        call scriptmanager_util#Unpack(s:c['binary_utils'].'\'.tools[k][1], s:c['binary_utils'].'\dist')
      endif
    endfor

  "if executable("7z")
    "echo "you already have 7z in PATH. Nothing to be done"
    "return
  "endif
  "let _7zurl = 'mirror://sourceforge/sevenzip/7-Zip/4.65/7z465.exe'
  "call scriptmanager_util#DownloadFromMirrors(_7zurl, s:c['binary_utils'].'/7z.exe')

  endf
endif
