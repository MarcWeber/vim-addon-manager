" vam#install contains code which is used when install plugins only

let s:curl = exists('g:netrw_http_cmd') ? g:netrw_http_cmd : 'curl -o'
exec vam#DefineAndBind('s:c','g:vim_addon_manager','{}')

let s:c.name_rewriting = get(s:c, 'name_rewriting', {})
call extend(s:c.name_rewriting, {'99git+github': 'vam#install#RewriteName'})

fun! s:confirm(msg, ...)
  if getchar(1)
    let char = getchar()
    if type(char) == type(0)
      let char = nr2char(char)
    endif
    let char = tolower(char)
    if a:0
      if type(a:1)==type("")
        let choices = tolower(substitute(a:1, '\v\&@<!.', '', 'g'))
        let idx     = stridx(choices, char)+1
        return idx ? idx : get(a:000, 1, 1)
      else
        return char is# 's'
      endif
    else
      return char isnot# 'n'
    endif
  elseif a:0 && type(a:1) == type("")
    return call("confirm", [a:msg]+a:000)
  else
    " Don't allow [y] with additional argument intentionally: it is too easy to 
    " overlook the dialog. So force users typing [s] instead
    return confirm(a:msg, a:0 ? "&No\nYe&s" : "&Yes\n&No") == 1+a:0
  endif
endfun

fun! vam#install#RewriteName(name)
  if a:name[:6]==#'github:'
    let rest = a:name[len('github:'):]
    return {'type' : 'git', 'url' : 'git://github.com/'.(rest =~ '/' ? rest : rest.'/vim-addon-'.rest)}
  elseif a:name[:3]==#'git:'
    return {'type' : 'git', 'url' : a:name[len('git:'):]}
  endif
endfun

" Install let's you install plugins by passing the url of a addon-info file
" This preprocessor replaces the urls by the plugin-names putting the
" repository information into the global dict
fun! vam#install#ReplaceAndFetchUrls(list)
  let l = a:list
  let idx = 0
  for idx in range(0, len(l)-1)
    if exists('t') | unlet t | endif
    let n = l[idx]
    " assume n is either an url or a path
    if n =~ '^http://' && s:confirm('Fetch plugin info from URL '.n.'?')
      let t = tempfile()
      call vam#utils#RunShell(s:curl.' $ > $', n, t)
    elseif n =~  '[/\\]' && filereadable(n)
      let t = n
    endif
    if exists('t')
      let dic = vam#ReadAddonInfo(t)
      if !has_key(dic,'name') || !has_key(dic, 'repository')
        call vam#Log( n." is no valid addon-info file. It must contain both keys: name and repository")
        continue
      endif
      let s:c['plugin_sources'][dic['name']] = dic['repository']
      let l[idx] = dic['name']
    endif
  endfor
  return l
endfun


" opts: same as ActivateAddons
fun! vam#install#Install(toBeInstalledList, ...)
  let toBeInstalledList = vam#install#ReplaceAndFetchUrls(a:toBeInstalledList)
  let opts = a:0 == 0 ? {} : a:1
  let auto_install = s:c['auto_install'] || get(opts,'auto_install',0)
  for name in toBeInstalledList
    " make sure all sources are known
    if vam#IsPluginInstalled(name)
      continue
    endif
    if name != s:c['known'] | call vam#install#LoadKnownRepos(opts) | endif

    let repository = get(s:c['plugin_sources'], name, get(opts, name,0))

    if type(repository) == type(0) && repository == 0
      unlet repository
      for key in sort(keys(s:c.name_rewriting))
        let repository=call(s:c.name_rewriting[key], [name], {})
        if type(repository) == type({})
          break
        endif
        unlet repository
      endfor
      if exists('repository')
        echom 'Name '.name.' expanded to :'.string(repository)
      else
        call vam#Log( "No repository location info known for plugin ".name."! (typo?)")
        continue " due to abort this won't take place ?
      endif
    endif

    let confirmed = 0
    let origin = get(repository,'type','').' '.get(repository,'url','')

    " tell user about target directory. Some users don't get it the first time..
    let pluginDir = vam#PluginDirByName(name)
    echom name." target: ".pluginDir

    let d = get(repository, 'deprecated', '')
    if type(d) == type('') && d != ''
      echom "!> Deprecation warning package ".name. ":"
      echom d
      " even for auto_install make user confirm the deprecation case
      if  !vam#Log('origin: '.origin ,"None")
          \ && s:confirm('Plugin '.name.' is deprecated, see warning above. Install it?', 1)
        let confirmed = 1
      else
        continue
      endif
    endif

    " ask user for to confirm installation unless he set auto_install

    if auto_install 
        \ || confirmed 
        \ || (!vam#Log('origin: '.origin ,"None")
              \ && s:confirm("Install plugin `".name."'?"))

      let infoFile = vam#AddonInfoFile(name)
      call vam#install#Checkout(pluginDir, repository)

      if !filereadable(infoFile) && has_key(s:c['missing_addon_infos'], name)
        call writefile([s:c['missing_addon_infos'][name]], infoFile)
      endif

      " install dependencies

      let infoFile = vam#AddonInfoFile(name)
      let info = vam#AddonInfo(name)

      let dependencies = get(info,'dependencies', {})

      " install dependencies merging opts with given repository sources
      " sources given in opts will win
      call vam#install#Install(keys(dependencies),
        \ extend(copy(opts), { 'plugin_sources' : extend(copy(dependencies), get(opts, 'plugin_sources',{}))}))
    endif
    call vam#install#HelpTags(name)
  endfor
endf

" this function will be refactored slightly soon by either me or ZyX.
fun! vam#install#UpdateAddon(name)
  call vam#Log( "Consediring ".a:name." for update" ,'type','unkown')
  let pluginDir = vam#PluginDirByName(a:name)
  " First, try updating using VCS. Return 1 if everything is ok, 0 if exception 
  " is thrown
  try
    if vcs_checkouts#Update(pluginDir)
      return 1
    endif
  catch /.*/
    call vam#Log( v:exception)
    return 0
  endtry

  "Next, try updating plugin by archive

  " we have to find out whether there is a new version:
  call vam#install#LoadKnownRepos({})
  let repository = get(s:c['plugin_sources'], a:name, {})
  if empty(repository)
    call vam#Log( "Don't know how to update ".a:name." because it is (no longer?) contained in plugin_sources")
    return 0
  endif
  let newVersion = get(repository,'version','?')


  if a:name == 'vim-addon-manager'
    " load utils before the file is moved below
    runtime autoload/vam/util.vim
  endif

  if get(repository, 'type', '') != 'archive'
    call vam#Log( "Not updating ".a:name." because the repository description suggests using VCS ".get(repository,'type','unkown').'.'
          \ ."\n Your install seems to be of type archive/manual/www.vim.org/unkown."
          \ ."\n If you want to udpate ".a:name." remove ".pluginDir." and let VAM check it out again."
          \ )
    return 0
  endif

  let versionFile = pluginDir.'/version'
  let oldVersion = filereadable(versionFile) ? readfile(versionFile, 1)[0] : "?"
  if oldVersion != newVersion || newVersion == '?'
    " update plugin
    echom "Updating plugin ".a:name." because ".(newVersion == '?' ? 'version is unkown' : 'there is a different version')

    " move plugin to backup destination:
    let pluginDirBackup = pluginDir.'-'.oldVersion
    if isdirectory(pluginDirBackup) || filereadable(pluginDirBackup)
      if s:confirm("Remove old plugin backup directory (".pluginDirBackup.")?")
        call vam#utils#RmFR(pluginDirBackup)
      else
        throw "User abort: remove ".pluginDirBackup." manually"
      endif
    endif
    call rename(pluginDir, pluginDirBackup)
    " can be romved. old version is encoded in tmp dir. Removing makes
    " diffing easier
    silent! call delete(pluginDirBackup.'/version')

    " try creating diff by checking out old version again
    if s:c['do_diff'] && executable('diff')
      let diff_file = s:c['plugin_root_dir'].'/'.a:name.'-'.oldVersion.'.diff'
      " try to create a diff
      let archiveName = vam#install#ArchiveNameFromDict(repository)
      let archiveFileBackup = pluginDirBackup.'/archive/'.archiveName
      if !filereadable(archiveFileBackup)
        call vam#Log( "Old archive file ".archiveFileBackup." is gone, can't try to create diff.")
      else
        let archiveFile = pluginDir.'/archive/'.archiveName
        call mkdir(pluginDir.'/archive','p')

        let rep_copy = deepcopy(repository)
        let rep_copy['url'] = 'file://'.expand(archiveFileBackup)
        call vam#install#Checkout(pluginDir, rep_copy)
        silent! call delete(pluginDir.'/version')
        try
          call vam#utils#ExecInDir([{'d': s:c['plugin_root_dir'], 'c': vam#utils#ShellDSL('diff -U3 -r -a --binary $p $p', fnamemodify(pluginDir,':t'), fnamemodify(pluginDirBackup,':t')).' > '.diff_file}])
          silent! call delete(diff_file)
        catch /.*/
          " :-( this is expected. diff returns non zero exit status. This is hacky
          let diff=1
        endtry
        call vam#utils#RmFR(pluginDir)
        echo 6
      endif
    endif

    " checkout new version (checkout into empty location - same as installing):
    call vam#install#Checkout(pluginDir, repository)

    " try applying patch
    let patch_failure = 0
    if exists('diff')
      if executable("patch")
        try
          call vam#utils#ExecInDir([{'d': pluginDir, 'c': vam#utils#ShellDSL('patch --binary -p1 --input=$p', diff_file)}])
          echom "Patching suceeded"
          let patch_failure = 0
          call delete(diff_file)
          let patch_failure = 0
        catch /.*/
          let patch_failure = 1
          call vam#Log( "Failed applying patch ".diff_file." kept old dir in ".pluginDirBackup)
        endtry
      else
        call vam#Log( "Failed trying to apply diff. patch exectubale not found")
        let patch_failure = 1
      endif
    endif

    " tidy up - if user didn't provide diff we remove old directory
    if !patch_failure
      call vam#utils#RmFR(pluginDirBackup)
    endif
  elseif oldVersion == newVersion
    call vam#Log( "Not updating plugin ".a:name.", ".newVersion." is current")
    return 1
  else
    call vam#Log( "Not updating plugin ".a:name." because there is no version according to version key")
  endif
  return 1
endf

fun! vam#install#Update(list)
  let list = a:list
  if empty(list) && s:confirm('Update all loaded plugins?')
    call vam#install#LoadKnownRepos({}, ' so that its updated as well')
    " include vim-addon-manager in list
    if !s:c['system_wide'] && isdirectory(vam#PluginDirByName('vim-addon-manager'))
      call vam#ActivateAddons(['vim-addon-manager'])
    endif
    let list = keys(s:c['activated_plugins'])
  endif
  let failed = []
  for p in list
    if vam#install#UpdateAddon(p)
      call vam#install#HelpTags(p)
    else
      call add(failed,p)
    endif
  endfor
  if !empty(failed)
    call vam#Log( "Failed updating plugins: ".string(failed).".")
  endif
endf

" completion {{{

" optional arg = 0: only installed
"          arg = 1: installed and names from known-repositories
fun! vam#install#KnownAddons(...)
  let which = a:0 > 0 ? a:1 : ''
  let list = filter(split(glob(vam#PluginDirByName('*')),"\n"), 'isdirectory(v:val)')
  let list = map(list, "fnamemodify(v:val,':t')")
  if which == "installable"
    call vam#install#LoadKnownRepos({})
    call extend(list, keys(s:c['plugin_sources']))
  elseif which == "installed"
    " hard to find out. Doing glob is best thing to do..
  endif
  " uniq items:
  let dict = {}
  for name in list
    let dict[name] = 1
  endfor
  return keys(dict)
endf

fun! vam#install#DoCompletion(A,L,P,...)
  let config = a:0 > 0 ? a:1 : ''
  let names = vam#install#KnownAddons(config)

  let beforeC= a:L[:a:P-1]
  let word = matchstr(beforeC, '\zs\S*$')
  " allow glob patterns
  let word = substitute(word, '\*','.*','g')

  let not_loaded = config == "uninstall"
    \ ? " && index(keys(s:c['activated_plugins']), v:val) == -1"
    \ : ''

  return filter(names,'v:val =~? '.string(word) . not_loaded)
endf

fun! vam#install#AddonCompletion(...)
  return call('vam#install#DoCompletion',a:000+["installable"])
endf

fun! vam#install#InstalledAddonCompletion(...)
  return call('vam#install#DoCompletion',a:000)
endf

fun! vam#install#UninstallCompletion(...)
  return call('vam#install#DoCompletion',a:000+["uninstall"])
endf

fun! vam#install#UpdateCompletion(...)
  return call('vam#install#DoCompletion',a:000+["installed"])
endf
"}}}


fun! vam#install#UninstallAddons(list)
  let list = a:list
  if list == []
    echo "No plugins selected. If you ran UninstallNotLoadedAddons use <tab> or <c-d> to get a list of not loaded plugins."
    return
  endif
  call map(list, 'vam#PluginDirByName(v:val)')
  if s:confirm('Confirm running rm -fr on directories: '.join(list,", ").'?')
    call map(list, 'vam#utils#RmFR(v:val)')
  endif
endf

fun! vam#install#HelpTags(name)
  let d=vam#PluginDirByName(a:name).'/doc'
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

" basename of url. if archive_name is given use that instead
fun! vam#install#ArchiveNameFromDict(repository)
    let archiveName = fnamemodify(substitute(get(a:repository,'archive_name',''), '\.\zsVIM$', 'vim', ''),':t')
    if archiveName == ''
      let archiveName = fnamemodify(a:repository['url'],':t')
    endif
    return archiveName
endf


" may throw EXCEPTION_UNPACK
fun! vam#install#Checkout(targetDir, repository) abort
  if get(a:repository, 'script-type') is 'patch'
    call vam#Log(
          \ "This plugin requires patching and recompiling vim.\n"
          \ ."VAM could not do this, so you have to apply patch\n"
          \ ."manually."
          \ )
  endif
  if get(a:repository,'type','') =~ 'git\|hg\|svn\|bzr'
    call vcs_checkouts#Checkout(a:targetDir, a:repository)
  else
    " archive based repositories - no VCS

    if !isdirectory(a:targetDir) | call mkdir(a:targetDir.'/archive','p') | endif

    " basename VIM -> vim
    let archiveName = vam#install#ArchiveNameFromDict(a:repository)

    " archive will be downloaded to this location
    let archiveFile = a:targetDir.'/archive/'.archiveName

    call vam#utils#Download(a:repository['url'], archiveFile)

    call vam#utils#Unpack(archiveFile, a:targetDir,
                \                  {'strip-components': get(a:repository,'strip-components',-1),
                \                   'script-type': tolower(get(a:repository, 'script-type', 'plugin')),
                \                   'unix_ff': get(a:repository, 'unix_ff', get(s:c, 'change_to_unix_ff')) })

    call writefile([get(a:repository,"version","?")], a:targetDir."/version")
  endif
endfun

" is there a library providing an OS abstraction? This breaks Winndows
" xcopy or copy should be used there..
fun! vam#install#Copy(f,t)
  if g:is_win
    call vam#utils#RunShell('xcopy /e /i $ $', a:f, a:t)
  else
    call vam#utils#RunShell('cp -r $ $', a:f, a:t)
  endif
endfun


fun! vam#install#LoadKnownRepos(opts, ...)
  " opts: only used to pass topLevel argument

  " this could be done better: see BUGS section in documantation "force".
  " Unletting in case of failure is not important because this only
  " deactivates a warning
  let g:in_load_known_repositories = 1

  let known = s:c['known']
  let reason = a:0 > 0 ? a:1 : 'get more plugin sources'
  if 0 == get(s:c['activated_plugins'], known, 0)
    let policy=get(s:c, 'known_repos_activation_policy', 'autoload')
    if policy==?"ask"
      let reply = s:confirm('Activate plugin '.known.' to '.reason."?", "&Yes\n&No\nN&ever (during session)")
    elseif policy==?"never"
      let reply=2
    else
      let reply=1
    endif
    if reply == 3 | let s:c.known_repos_activation_policy = "never" | endif
    if reply == 1
      " don't pass opts so that new_runtime_paths is not set which will
      " trigger topLevel adding -known-repos to rtp immediately
      call vam#ActivateAddons([known], {})
      if has('vim_starting')
        " This is not done in .vimrc because Vim loads plugin/*.vim files after
        " having finished processing .vimrc. So do it manually
        exec 'source '.vam#PluginDirByName(known).'/plugin/vim-addon-manager-known-repositories.vim'
      endif
    endif
  endif
  unlet g:in_load_known_repositories
endf


fun! vam#install#MergeTarget()
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
fun! vam#install#MergePluginFiles(plugins, skip_pattern)
  if !filereadable('/bin/sh')
    throw "you should be using Linux.. This code is likely to break on other operating systems!"
  endif

  let target = vam#install#MergeTarget()

  for r in a:plugins
    if !has_key(s:c['activated_plugins'], r)
      throw "JoinPluginFiles: all plugins must be activated (which ensures that they have been installed). This plugin is not active: ".r
    endif
  endfor

  let runtimepaths = map(copy(a:plugins), 'vam#PluginRuntimePath(v:val)')

  " 1)
  for r in runtimepaths
    if (isdirectory(r.'/plugin'))
      call vam#utils#RunShell('mv $ $', r.'/plugin', r.'/plugin-merged')
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

          " negate if, remove triple { if present (I don't care)
          let lines[i-1] = 'if !('.matchstr(substitute(lines[i-1],'"[^"]*{\{3}.*','',''),'if\s*\zs.*').')'
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

fun! vam#install#UnmergePluginFiles()
  let path = fnamemodify(vam#PluginRuntimePath('vim-addon-manager'),':h')
  for merged in split(glob(path.'/*/plugin-merged'),"\n")
            \ +split(glob(path.'/*/*/plugin-merged'),"\n")
    echo "unmerging ".merged
    call rename(merged, substitute(merged,'-merged$','',''))
  endfor
  call delete(vam#install#MergeTarget())
endfun


if g:is_win
  fun! vam#install#FetchAdditionalWindowsTools() abort
    if !executable("curl") && s:curl == "curl -o"
      throw "No curl found. Either set g:netrw_http_cmd='path/curl -o' or put it in PATH"
    endif
    if !isdirectory(s:c['binary_utils'].'\dist')
      call mkdir(s:c['binary_utils'].'\dist','p')
    endif
    " we have curl, so we can fetch remaining deps using Download and Unpack
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
        call vam#utils#DownloadFromMirrors(v[0].v[1], s:c['binary_utils'])
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
        call vam#utils#Unpack(s:c['binary_utils'].'\'.tools[k][1], s:c['binary_utils'].'\dist')
      endif
    endfor

  "if executable("7z")
    "echo "you already have 7z in PATH. Nothing to be done"
    "return
  "endif
  "let _7zurl = 'mirror://sourceforge/sevenzip/7-Zip/4.65/7z465.exe'
  "call vam#utils#DownloadFromMirrors(_7zurl, s:c['binary_utils'].'/7z.exe')

  endf
endif
" vim: et ts=8 sts=2 sw=2
