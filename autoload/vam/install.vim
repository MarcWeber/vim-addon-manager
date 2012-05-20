" vam#install contains code which is used when install plugins only

exec vam#DefineAndBind('s:c','g:vim_addon_manager','{}')

let s:c['change_to_unix_ff'] = get(s:c, 'change_to_unix_ff', (g:os=~#'unix'))
let s:c['do_diff'] = get(s:c, 'do_diff', 1)
let s:c['known'] = get(s:c,'known','vim-addon-manager-known-repositories')
let s:c['MergeSources'] = get(s:c, 'MergeSources', 'vam_known_repositories#MergeSources')
let s:c['pool_fun'] = get(s:c, 'pool_fun', 'vam#install#Pool')
let s:c['name_rewriting'] = get(s:c, 'name_rewriting', {})
let s:c['pre_update_hook_functions'] = get(s:c, 'pre_update_hook_functions', ['vam#install#CreatePatch'])
let s:c['post_update_hook_functions'] = get(s:c, 'post_update_hook_functions', ['vam#install#ApplyPatch'])

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
    " github:{Name}      {"type": "git", "url": "git://github.com/{Name}/vim-addon-{Name}}
    " github:{N}/{Repo}  {"type": "git", "url": "git://github.com/{N}/{Repo}"}
    let rest = a:name[len('github:'):]
    return {'type' : 'git', 'url' : 'git://github.com/'.(rest =~ '/' ? rest : rest.'/vim-addon-'.rest)}
  elseif a:name[:3]==#'git:'
    " git:{URL}          {"type": "git", "url": {URL}}
    return {'type' : 'git', 'url' : a:name[len('git:'):]}
  elseif a:name[:2]==#'hg:'
    return {'type' : 'hg', 'url' : a:name[len('hg:'):]}
  endif

endfun

fun! vam#install#GetRepo(name, opts)
  if a:name isnot# s:c['known'] | call vam#install#LoadPool() |endif

  let repository = get(s:c['plugin_sources'], a:name, get(a:opts, a:name, 0))
  if repository is 0
    unlet repository
    for key in sort(keys(s:c.name_rewriting))
      let repository=call(s:c.name_rewriting[key], [a:name], {})
      if type(repository) == type({})
        break
      endif
      unlet repository
    endfor
    if exists('repository')
      echom 'Name '.a:name.' expanded to :'.string(repository)
    else
      " try to find typos and renamings. Tell user about failure
      let maybe_fixes = []
      let name_ = vam#utils#TypoFix(a:name)
      for x in keys(s:c.plugin_sources)
        if vam#utils#TypoFix(x) == name_
          call add(maybe_fixes, a:name.' might be a typo, did you mean: '.x.' ?')
        endif
      endfor
      " try finding new name (VAM-kr only)
      try
        " using try because pool implementations other then VAM-kr could be
        " used
        call extend(maybe_fixes, vamkr#SuggestNewName(a:name))
      catch /Vim(call):E117:/
        " If VAM-kr activation policy is never, then the above will yield 
        " unknown function error
      endtry
      call vam#Log(join(["No repository location info known for plugin ".a:name."."] + maybe_fixes,"\n"))
      return 0
    endif
  endif
  return repository
endfun

" Install let's you install plugins by passing the url of a addon-info file
" This preprocessor replaces the urls by the plugin-names putting the
" repository information into the global dict
fun! vam#install#ReplaceAndFetchUrls(list)
  let l = a:list
  let idx = 0
  for idx in range(0, len(l)-1)
    let n = l[idx]
    " assume n is either an url or a path
    if n =~ '\m^https\?://' && s:confirm('Fetch plugin info from URL '.n.'?')
      let t = tempname()
      call vam#utils#Download(n, t)
    elseif n =~ '[/\\]' && filereadable(n)
      let t = n
    endif
    if exists('t')
      let dic = vam#ReadAddonInfo(t)
      unlet t
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

fun! vam#install#RunHook(hook, info, repository, pluginDir, opts)
  let hkey=tr(a:hook, '-', '_').'_hook_functions'
  if has_key(s:c, hkey)
    let d={}
    for d.hook in s:c[hkey]
      call call(d.hook, [a:info, a:repository, a:pluginDir, a:opts], {})
    endfor
  endif
  let hkey=a:hook.'-hook'
  if has_key(a:info, hkey)
    execute substitute(substitute(substitute(substitute(a:info[hkey],
          \'%d', 'a:pluginDir',  'g'),
          \'%r', 'a:repository', 'g'),
          \'%i', 'a:info',       'g'),
          \'%o', 'a:opts',       'g')
  endif
endfu

" opts: same as ActivateAddons
fun! vam#install#Install(toBeInstalledList, ...)
  let toBeInstalledList = vam#install#ReplaceAndFetchUrls(a:toBeInstalledList)
  let opts = a:0 == 0 ? {} : a:1
  let auto_install = s:c['auto_install'] || get(opts,'auto_install',0)
  for name in filter(copy(toBeInstalledList), '!vam#IsPluginInstalled(v:val)')
    let repository = vam#install#GetRepo(name, opts)
    " make sure all sources are known
    if repository is 0
      continue
    endif

    let confirmed = 0
    let origin = get(repository,'type','').' '.get(repository,'url','')

    " tell user about target directory. Some users don't get it the first time..
    let pluginDir = vam#PluginDirFromName(name)

    call vam#DisplayAddonInfo(name)
    call vam#Log('Target: '.pluginDir, 'None')
    if (has_key(opts, 'requested_by'))
      call vam#Log('Dependency chain: '.join([name]+opts.requested_by,' < '))
    endif

    let d = get(repository, 'deprecated', '')
    if type(d) == type('') && d != ''
      echom "!> Deprecation warning package ".name. ":"
      echom d
      " even for auto_install make user confirm the deprecation case
      if  !vam#Log('Origin: '.origin ,"None")
          \ && s:confirm('Plugin '.name.' is deprecated, see warning above. Install it?', 1)
        let confirmed = 1
      else
        continue
      endif
    endif

    " ask user for to confirm installation unless he set auto_install

    if auto_install
        \ || confirmed
        \ || (!vam#Log('Origin: '.origin ,"None")
              \ && s:confirm("Install plugin `".name."'?"))

      call vam#install#Checkout(pluginDir, repository)

      let infoFile = vam#AddonInfoFile(name)
      if has_key(repository, 'addon-info') && !filereadable(infoFile)
        call writefile([string(repository['addon-info'])], infoFile)
      endif

      " install dependencies
      let info = vam#AddonInfo(name)

      let dependencies = get(info, 'dependencies', {})

      " install dependencies merging opts with given repository sources
      " sources given in opts will win
      call vam#install#Install(keys(dependencies),
        \ extend(copy(opts), {
       \ 'plugin_sources' : extend(copy(dependencies), get(opts, 'plugin_sources',{})),
       \ 'requested_by' : [name] + get(opts, 'requested_by', [])
       \ }))

      call vam#install#HelpTags(name)
      if get(opts, 'run_install_hooks', 0)
        call vam#install#RunHook('post-install', info, repository, pluginDir, {})
      endif
    endif
  endfor
endf

fun! vam#install#CreatePatch(info, repository, pluginDir, hook_opts)
  let a:hook_opts.diff_do_diff=(s:c.do_diff && executable('diff'))
  " try creating diff by checking out old version again
  if a:hook_opts.diff_do_diff
    " move plugin to backup destination:
    let pluginDirBackup = a:pluginDir.'-'.a:hook_opts.oldVersion
    if isdirectory(pluginDirBackup) || filereadable(pluginDirBackup)
      if s:confirm('Remove old plugin backup directory ('.pluginDirBackup.')?')
        call vam#utils#RmFR(pluginDirBackup)
      else
        throw 'User abort: remove '.pluginDirBackup.' manually'
      endif
    endif
    call rename(a:pluginDir, pluginDirBackup)
    " can be romved. old version is encoded in tmp dir. Removing makes
    " diffing easier
    silent! call delete(pluginDirBackup.'/version')
    let a:hook_opts.diff_backup_dir=pluginDirBackup

    let diff_file = a:pluginDir.'-'.a:hook_opts.oldVersion.'.diff'
    let a:hook_opts.diff_file=diff_file
    " try to create a diff
    let archiveName = vam#install#ArchiveNameFromDict(a:repository)
    let archiveFileBackup = pluginDirBackup.'/archive/'.archiveName
    if !filereadable(archiveFileBackup)
      call vam#Log("Old archive file ".archiveFileBackup." is gone, can't try to create diff.")
    else
      let archiveFile = a:pluginDir.'/archive/'.archiveName
      call mkdir(a:pluginDir.'/archive', 'p')

      let rep_copy = deepcopy(a:repository)
      let rep_copy['url'] = 'file://'.expand(archiveFileBackup)
      call vam#install#Checkout(a:pluginDir, rep_copy)
      silent! call delete(a:pluginDir.'/version')
      try
        call vam#utils#ExecInDir(fnamemodify(a:pluginDir, ':h'), 'diff -U3 -r -a --binary $p $p > $p', fnamemodify(a:pluginDir,':t'), fnamemodify(pluginDirBackup,':t'), diff_file)
        silent! call delete(diff_file)
        let a:hook_opts.diff_do_diff=0
      catch /.*/
        " :-( this is expected. diff returns non zero exit status. This is hacky
        let a:hook_opts.diff_do_diff=1
      endtry
      call vam#utils#RmFR(a:pluginDir)
    endif
  endif
endfun
fun! vam#install#ApplyPatch(info, repository, pluginDir, hook_opts)
  " try applying patch
  if a:hook_opts.diff_do_diff
    if executable('patch')
      let diff_file=a:hook_opts.diff_file
      let pluginDirBackup=a:hook_opts.diff_backup_dir
      try
        call vam#utils#ExecInDir(a:pluginDir, 'patch --binary -p1 --input=$p', diff_file)
        call vam#Log('Patching suceeded', 'None')
        call delete(diff_file)
        call vam#utils#RmFR(pluginDirBackup)
      catch /.*/
        call vam#Log('Failed to apply patch '.diff_file.' ('.v:exception.'), original files may be found in '.pluginDirBackup)
      endtry
    else
      call vam#Log('Failed trying to apply diff: “patch” executable not found')
    endif
  endif
endfun

" this function will be refactored slightly soon by either me or ZyX.
" returns
" "up-to-date" if addon is up to date
" "updated" if addon was updated succesfully
" "failed" if addon could not be updated. Error is logged in this case
fun! vam#install#UpdateAddon(name)
  call vam#Log( "Considering ".a:name." for update" ,'type','unknown')
  let pluginDir = vam#PluginDirFromName(a:name)
  if !isdirectory(pluginDir)
    return 'missing'
  endif
  " First, try updating using VCS. Return 1 if everything is ok, 0 if exception 
  " is thrown
  try
    let r = vcs_checkouts#Update(pluginDir)
    if r isnot# 'unknown'
      if r is# 'updated'
        call vam#install#RunHook('post-scms-update', vam#AddonInfo(a:name), {}, pluginDir, {})
      endif
      return r
    endif
  catch /.*/
    call vam#Log(v:exception)
    return 'failed'
  endtry

  "Next, try updating plugin by archive

  " we have to find out whether there is a new version:
  call vam#install#LoadPool()
  let repository = get(s:c['plugin_sources'], a:name, {})
  if empty(repository)
    call vam#Log("Don't know how to update ".a:name." because it is not contained in plugin_sources")
    return 'failed'
  endif
  let newVersion = get(repository, 'version', '?')


  if a:name is# 'vim-addon-manager'
    " load utils before the file is moved below
    runtime autoload/vam/util.vim
  endif

  if get(repository, 'type', 0) isnot# 'archive'
    call vam#Log("Not updating ".a:name." because the repository description suggests using VCS ".get(repository, 'type', 'unknown').'.'
          \ ."\nYour install seems to be of type archive/manual/www.vim.org/unknown."
          \ ."\nIf you want to update ".a:name." remove ".pluginDir." and let VAM check it out again."
          \ )
    return 'failed'
  endif

  let versionFile = pluginDir.'/version'
  let oldVersion = filereadable(versionFile) ? readfile(versionFile, 'b')[0] : "?"
  if oldVersion !=# newVersion || newVersion == '?'
    " update plugin
    echom "Updating plugin ".a:name." because ".(newVersion == '?' ? 'version is unknown' : 'there is a different version')

    let hook_opts={'oldVersion': oldVersion}
    call vam#install#RunHook('pre-update', vam#AddonInfo(a:name), repository, pluginDir, hook_opts)

    " checkout new version (checkout into empty location - same as installing):
    if isdirectory(pluginDir)
      call vam#utils#RmFR(pluginDir)
    endif
    call vam#install#Checkout(pluginDir, repository)

    call vam#install#RunHook('post-update', vam#AddonInfo(a:name), repository, pluginDir, hook_opts)

    return 'updated'
  elseif oldVersion == newVersion
    call vam#Log( "Not updating plugin ".a:name.", ".newVersion." is current")
    return 'up-to-date'
  else
    call vam#Log( "Not updating plugin ".a:name." because there is no version according to version key")
  endif
  return 'up-to-date'
endf

fun! vam#install#Update(list)
  let list = a:list

  if s:c.known isnot 0
    if vam#install#UpdateAddon(s:c.known)
      call vam#install#HelpTags(s:c.known)
    endif
  endif
  " refresh sources:
  call vam#install#LoadPool(1)

  if empty(list) && s:confirm('Update all loaded plugins?')
    let list = keys(s:c['activated_plugins'])
  endif
  let by_reply = {}
  for p in list
    let r = vam#install#UpdateAddon(p)
    if r is# 'updated'
      call vam#install#HelpTags(p)
    endif
    if (!has_key(by_reply,r))
      let by_reply[r] = []
    endif
    call add(by_reply[r], p)
  endfor
  let labels = {'updated': 'Updated:', 'failed': 'Failed to update:',
        \       'up-to-date': 'Already up to date:',
        \       'possibly updated': 'Don’t know how to determine update state (possibly updated):',
        \       'missing': 'Plugin not installed:',}
  for [k,v] in items(by_reply)
    call vam#Log(get(labels,k,k).' '.string(by_reply[k]).".", k is# 'failed' ? 'WarningMsg' : 'Type')
  endfor
endf

" completion {{{

fun! vam#install#KnownAddons(type)
  call vam#install#LoadPool()
  let k = {}
  " from pool
  call extend(k, s:c.plugin_sources)
  " Disk completion using default plugin dir location.
  " Don’t do this if plugin_root_dir contains newline: split(glob) does not work 
  " properly in this case. Also don’t do this if we require notinstalled 
  " plugins.
  if a:type isnot# 'notinstalled' &&
        \s:c.plugin_dir_by_name is# 'vam#DefaultPluginDirFromName' &&
        \stridx(s:c.plugin_root_dir, "\n")==-1
    for n in split(glob(s:c.plugin_root_dir.'/*', "\n"))
      " We don’t care about values: so no need to make it complex
      let k[fnamemodify(n, ':t')] = 1
    endfor
  endif
  return sort(keys(k))
endf

" Filters:
" 1. Start of the name must be the same as completed name
" 2. Part of the name must be the same as completed name
" 3. User correctly entered start of the string, but punctuation characters 
"    inside were mistaken. Also takes globs as '*'=~'[[:punct:]]'.
" 4. There may be missing characters somewhere at the word boundary, but user 
"    correctly entered start of the word
" 5. There may be missing characters somewhere at the word boundary, but first 
"    character is correct
" 6. Name has completely wrong order of characters, but not the first character
" 7. Punctuation characters inside string were mistaken.
"    Also takes globs as '*'=~'[[:punct:]]'.
" 8. There may be missing characters somewhere at the word boundary
" 9. There may be some missing charaters inside a word
let s:smartfilters=[
      \['1',        '"v:val[:".(len(a:str)-1)."]==?".string(a:str)'],
      \['1',        '"stridx(tolower(v:val), ".string(tolower(a:str)).")!=-1"'],
      \['haspunct', '"v:val=~?".string("\\v^".regnopunct)'],
      \['haspunct', '"v:val=~?".string("\\v^".regboundary)'],
      \['lstr>1',   '"v:val=~?".string("\\v^".reginside)'],
      \['lstr>1',   '"v:val=~?".string(regwrongorder)'],
      \['haspunct', '"v:val=~?".string(regnopunct)'],
      \['haspunct', '"v:val=~?".string(regboundary)'],
      \['lstr>1',   '"v:val=~?".string(reginside)'],
    \]
fun! vam#install#GetFilters(str)
  if empty(a:str)
    return ['1']
  endif
  let lstr=len(a:str)
  let haspunct=(match(a:str, "[[:punct:]]")!=-1)
  let regnopunct='\V'.substitute(a:str, '\v[[:punct:]]+', '\\.\\*', 'g')
  let estrchars=map(split(a:str,'\v\_.@='), 'escape(v:val, "\\")')
  let regwrongorder='\V\^'.estrchars[0].'\%(\.\*'.join(estrchars[1:], '\)\@=\%(\.\*').'\)\@='
  let regboundary='\V'.join(map(split(a:str, '\v[[:punct:]]@<=|[[:punct:]]@='), 'escape(v:val, "\\")'), '\.\*')
  let reginside='\V'.join(estrchars, '\.\*')
  return map(filter(copy(s:smartfilters), 'eval(v:val[0])'), 'eval(v:val[1])')
endfun

fun! vam#install#FilterVariants(str, variants)
  let list=copy(a:variants)
  let r=[]
  for filter in vam#install#GetFilters(a:str)
    let newlist=[]
    call map(list, '('.filter.')?(add(r, v:val)):(add(newlist, v:val))')
    " We already have enough results to show, so stop thinking that user needs 
    " more variants
    if len(r)>8
      break
    endif
    let list=newlist
  endfor
  return r
endfun

fun! vam#install#CompleteAddonName(findstart, base)
  if a:findstart
    let match_text=matchstr(getline('.')[:col('.')-1], "[^'\"()[\\]{}\t ]*$")
    return col('.')-len(match_text)-1
  else
    call map(vam#install#FilterVariants(a:base, vam#install#KnownAddons(0)),
          \  'complete_add({"word": v:val, '.
          \                '"menu": "Script id: ".'.
          \                        'get(get(s:c.plugin_sources, v:val, {}), '.
          \                            '"vim_script_nr", "NA")})')
    return []
  endif
endfun

let s:postfilters={
      \'installed':    'isdirectory(vam#PluginDirFromName(v:val))',
      \'notloaded':    '(!has_key(s:c.activated_plugins, v:val)) && '.
      \                'isdirectory(vam#PluginDirFromName(v:val))',
      \'notinstalled': '!isdirectory(vam#PluginDirFromName(v:val))',
    \}
fun! vam#install#DoCompletion(A, L, P, ...)
  let list=vam#install#KnownAddons(get(a:000, 0, 0))
  let str=matchstr(a:L[:a:P-1], '\S*$')
  let r=vam#install#FilterVariants(str, list)
  if a:0
    call filter(r, s:postfilters[a:1])
  endif
  return r
endfun

fun! vam#install#AddonCompletion(...)
  return call('vam#install#DoCompletion',a:000)
endf

fun! vam#install#NotInstalledAddonCompletion(...)
  return call('vam#install#DoCompletion',a:000+["notinstalled"])
endf

fun! vam#install#InstalledAddonCompletion(...)
  return call('vam#install#DoCompletion',a:000+["installed"])
endf

fun! vam#install#UninstallCompletion(...)
  return call('vam#install#DoCompletion',a:000+["notloaded"])
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
  call map(list, 'vam#PluginDirFromName(v:val)')
  if s:confirm('Will now remove '.join(list, ', ').'. Confirm?')
    call map(list, 'vam#utils#RmFR(v:val)')
  endif
endf

fun! vam#install#HelpTags(name)
  let d=vam#PluginDirFromName(a:name).'/doc'
  if isdirectory(d) | exec 'helptags '.fnameescape(d) | endif
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
    let archiveName = fnamemodify(substitute(get(a:repository,'archive_name',''), '\.\@<=VIM$', 'vim', ''),':t')
    if empty(archiveName)
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

    call writefile([get(a:repository, 'version', '?')], a:targetDir.'/version', 'b')
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

"{{{1 Pool
" VAM does call this function for you when using {Activate/Install}Addon() or
" one of those commands. Read doc/vim-addon-manager.txt to learn about the
" pool of plugin sources. Also see option "known_repos_activation_policy"
fun! vam#install#LoadKnownRepos()
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
    endif
  endif
endfun

" The default pool of know plugins for VAM: vim-addon-manager-known-repositories
fun! vam#install#Pool()
  call vam#install#LoadKnownRepos()
  return vam_known_repositories#Pool()
endfun

" (re)loads pool of known plugins
fun! vam#install#LoadPool(...)
  let force = a:0 > 0 ? a:1 : 0
  if force || !has_key(s:c, 'pool_loaded')
    " update plugin_sources
    let s:c.plugin_sources = call(s:c.pool_fun, [], {})

    let s:c.pool_loaded = 1
  endif
endf
"}}}1


if g:is_win
  fun! vam#install#FetchAdditionalWindowsTools() abort
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
