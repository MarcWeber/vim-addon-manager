" see README

" this file contains code which is always used
" code which is used for installing / updating etc should go into vam/install.vim

" if people use VAM they also want nocompatible
if &compatible | set nocompatible | endif


" don't need a plugin. If you want to use this plugin you call Activate once
" anyway
fun! vam#DefineAndBind(local,global,default)
  return 'if !exists('.string(a:global).') | let '.a:global.' = '.a:default.' | endif | let '.a:local.' = '.a:global
endfun


" assign g:os
for os in split('amiga beos dos32 dos16 mac macunix os2 qnx unix vms win16 win32 win64 win32unix', ' ')
  if has(os) | let g:os = os | break | endif
endfor
let g:is_win = g:os[:2] == 'win'

exec vam#DefineAndBind('s:c','g:vim_addon_manager','{}')
let s:c.auto_install               = get(s:c,'auto_install',                0)
" repository locations:
let s:c.plugin_sources             = get(s:c,'plugin_sources',              {})
" if a plugin has an item here the dict value contents will be written as plugin info file
" Note: VAM itself may be added after definition of vam#PluginDirFromName 
" function
let s:c.activated_plugins          = get(s:c,'activated_plugins',           {})

let s:c.create_addon_info_handlers = get(s:c, 'create_addon_info_handlers', 1)

" Users may install VAM system wide. In that case s:d is not writeable.
let s:d = expand('<sfile>:h:h:h', 1)
let s:c.plugin_root_dir = get(s:c, 'plugin_root_dir', filewritable(s:d) ? s:d : '~/.vim/vim-addons')
unlet s:d

if s:c.plugin_root_dir is# expand('~', 1)
  echohl Error
  echomsg "VAM: Don't install VAM into ~/.vim the normal way. See docs -> SetupVAM function. Put it int ~/.vim/vim-addons/vim-addon-manager for example."
  echohl None
  finish
endif

" ensure we have absolute paths (windows doesn't like ~/.. ) :
let s:c.plugin_root_dir = expand(fnameescape(s:c.plugin_root_dir), 1)

let s:c.additional_addon_dirs = get(s:c, 'additional_addon_dirs', [])
call map(s:c.additional_addon_dirs, 'expand(fnameescape(v:val), 1)')

let s:c.dont_source          = get(s:c, 'dont_source',          0)
let s:c.plugin_dir_by_name   = get(s:c, 'plugin_dir_by_name',   'vam#DefaultPluginDirFromName')
let s:c.addon_completion_lhs = get(s:c, 'addon_completion_lhs', '<C-x><C-p>')
let s:c.debug_activation     = get(s:c, 'debug_activation',     0)
let s:c.pool_item_check_fun  = get(s:c, 'pool_item_check_fun',  'none')
let s:c.source_missing_files = get(s:c, 'source_missing_files', &loadplugins)

" experimental: will be documented when its tested
" don't echo lines, add them to a buffer to prevent those nasty "Press Enter"
" to show more requests by Vim
" TODO: move log code into other file (such as utils.vim) because its not used on each startup
" TODO: think about autowriting it
let s:c.log_to_buf      = get(s:c, 'log_to_buf', 0)
let s:c.log_buffer_name = get(s:c, 'log_buffer_name', s:c.plugin_root_dir.'/VAM_LOG.txt')

" More options that are used for plugins’ installation are listed in 
" autoload/vam/install.vim

if g:is_win && has_key(s:c, 'binary_utils')
  " if binary-utils path exists then add it to PATH
  let s:c.binary_utils = get(s:c,'binary_utils', tr(s:c.plugin_root_dir, '/', '\').'\binary-utils')
  let s:c.binary_utils_bin = s:c.binary_utils.'\dist\bin'
  if isdirectory(s:c.binary_utils)
    let $PATH=$PATH.';'.s:c.binary_utils_bin
  endif
endif

" additional plugin sources should go into your .vimrc or into the repository
" called "vim-addon-manager-known-repositories" referenced here:
if executable('git')
  let s:c.plugin_sources["vim-addon-manager-known-repositories"] = {'type' : 'git', 'url': 'git://github.com/MarcWeber/vim-addon-manager-known-repositories'}
else
  let s:c.plugin_sources["vim-addon-manager-known-repositories"] = {'type' : 'archive', 'url': 'http://github.com/MarcWeber/vim-addon-manager-known-repositories/tarball/master', 'archive_name': 'vim-addon-manager-known-repositories-tip.tar.gz'}
endif

if s:c.create_addon_info_handlers
  augroup VAM_addon_info_handlers
    autocmd!
    autocmd BufRead,BufNewFile *-addon-info.txt,addon-info.json
      \ setlocal ft=addon-info
      \ | setlocal syntax=json
      \ | syn match Error "^\s*'"
    autocmd BufWritePost *-addon-info.txt,addon-info.json call vam#ReadAddonInfo(expand('%', 1))
  augroup END
endif

fun! vam#VerifyIsJSON(s)
  " You must allow single-quoted strings in order for writefile([string()]) that 
  " adds missing addon information to work
  let scalarless_body = substitute(a:s, '\v\"%(\\.|[^"\\])*\"|\''%(\''{2}|[^''])*\''|true|false|null|[+-]?\d+%(\.\d+%([Ee][+-]?\d+)?)?', '', 'g')
  return scalarless_body !~# "[^,:{}[\\] \t]"
endfun

" use join so that you can break the dict into multiple lines. This makes
" reading it much easier
fun! vam#ReadAddonInfo(path)

  " don't add "b" because it'll read dos files as "\r\n" which will fail the
  " check and evaluate in eval. \r\n is checked out by some msys git
  " versions with strange settings

  " using eval is evil!
  let body = join(readfile(a:path),"")

  if vam#VerifyIsJSON(body)
    let true=1
    let false=0
    let null=''
    " using eval is now safe!
    return eval(body)
  else
    call vam#Log( "Invalid JSON in ".a:path."!")
    return {}
  endif

endfun

fun! vam#DefaultPluginDirFromName(name) abort
  " this function maps addon names to their storage location. \/: are replaced
  " by - (See name rewriting)
  let dirs = [s:c.plugin_root_dir] + s:c.additional_addon_dirs
  let name = substitute(a:name, '[\\/:]\+', '-', 'g')
  let existing = filter(copy(dirs), "isdirectory(v:val.'/'.".string(name).')')
  return (empty(existing) ? dirs[0] : existing[0]).'/'.name
endfun
fun! vam#PluginDirFromName(...)
  return call(s:c.plugin_dir_by_name, a:000, {})
endfun
fun! vam#PluginRuntimePath(name)
  let info = vam#AddonInfo(a:name)
  return vam#PluginDirFromName(a:name).(has_key(info, 'runtimepath') ? '/'.info.runtimepath : '')
endfun

" adding VAM, so that its contained in list passed to :UpdateActivatedAddons 
if filewritable(vam#PluginDirFromName('vim-addon-manager'))==2
  let s:c.activated_plugins['vim-addon-manager']=1
endif

" doesn't check dependencies!
fun! vam#IsPluginInstalled(name)
  let d = vam#PluginDirFromName(a:name)

  " if dir exists and its not a failed download
  " (empty archive directory)
  return isdirectory(d)
    \ && (!isdirectory(d.'/archive')
    \     || !empty(glob(fnameescape(d).'/archive/*', 1)))
endfun

" {} if file doesn't exist
fun! vam#AddonInfo(name)
  let infoFile = vam#AddonInfoFile(a:name)
  return filereadable(infoFile)
    \ ? vam#ReadAddonInfo(infoFile)
    \ : {}
endfun


" opts: {
"   'plugin_sources': additional sources (used when installing dependencies)
"   'auto_install': when 1 overrides global setting, so you can autoinstall
"   trusted repositories only
" }
fun! vam#ActivateRecursively(list_of_names, ...)
  let opts = extend({'run_install_hooks': 1}, a:0 == 0 ? {} : a:1)

  for name in a:list_of_names
    if !has_key(s:c.activated_plugins,  name)
      " break circular dependencies..
      let s:c.activated_plugins[name] = 0

      let infoFile = vam#AddonInfoFile(name)
      if !filereadable(infoFile) && !vam#IsPluginInstalled(name)
        if empty(vam#install#Install([name], opts))
          unlet s:c.activated_plugins[name]
          continue
        endif
      endif
      let info = vam#AddonInfo(name)
      let dependencies = get(info,'dependencies', {})

      " activate dependencies merging opts with given repository sources
      " sources given in opts will win
      call vam#ActivateAddons(keys(dependencies),
        \ extend(copy(opts), {
            \ 'plugin_sources' : extend(copy(dependencies), get(opts, 'plugin_sources',{})),
            \ 'requested_by' : [name] + get(opts, 'requested_by', [])
        \ }))

      " source plugin/* files ?
      let rtp = vam#PluginRuntimePath(name)
      call add(opts.new_runtime_paths, rtp)

      let s:c.activated_plugins[name] = 1

      if s:c.debug_activation
        " activation takes place later (-> new_runtime_paths), but messages will be in order
        " XXX Lengths of “as it was requested by” and “which was requested by” 
        "     match
        call vam#Log('Will activate '.name.(empty(get(opts, 'requested_by'))?
              \                             (' as it was specified by user.'):
              \                             ("\n  as it was requested by ".
              \                               join(opts.requested_by, "\n  which was requested by ").'.')))
      endif
    endif
  endfor
endfun

fun! s:GetAuGroups()
  redir => aus
  silent autocmd VimEnter,BufEnter,TabEnter,BufWinEnter,WinEnter,GUIEnter
  redir END
  let augs = {}
  for [group, event] in map(filter(split(aus, "\n"),
        \                          'v:val=~#''\v^\w+\s+\w+$'''),
        \                   'split(v:val)')
    if has_key(augs, group)
      call add(augs[group], event)
    else
      let augs[group] = [event]
    endif
  endfor
  return augs
endfun

fun! s:ResetVars(buf)
  let filetype = getbufvar(a:buf, '&filetype')
  let syntax   = getbufvar(a:buf, '&syntax')
  call setbufvar(a:buf, '&filetype', filetype)
  if filetype isnot# syntax
    call setbufvar(a:buf, '&syntax', syntax)
  endif
endfun

" see also ActivateRecursively
" Activate activates the plugins and their dependencies recursively.
" I sources both: plugin/*.vim and after/plugin/*.vim files when called after
" .vimrc has been sourced which happens when you activate plugins manually.
fun! vam#ActivateAddons(...) abort
  let args = copy(a:000)
  if a:0 == 0 | return | endif

  if  type(args[0])==type("")
    " way of usage 1: pass addon names as function arguments
    " Example: ActivateAddons("name1","name2")

    " This way of calling has two flaws:
    " - doesn't scale due to amount of args limitation
    " - you can't pass autoinstall=1
    " Therefore we should get rid of this way..
    
    " verify that all args are strings only because errors are hard to debug
    if !empty(filter(copy(args),'type(v:val) != type("")'))
      throw "Bad argument to vam#ActivateAddons: only Strings are permitted. Use ActivateAddons(['n1','n2',..], {..}) to pass options dictionary"
    endif

    let args=[args, {}]
  else
    " way of usage 2: pass addon names as list optionally passing options
    " Example: ActivateAddons(["name1","name2"], { options })

    let args=[args[0], get(args,1,{})]
  endif

  " now opts should be defined
  " args[0] = plugin names
  " args[1] = options

  " g:vam_plugin_whitelist is used for bisecting.
  " Using a different global name so that collisions with user's ~/.vimrc are
  " less likely
  let opts = args[1]
  let topLevel = !has_key(opts, 'new_runtime_paths')

  if exists('g:vam_plugin_whitelist') && topLevel
    call filter(args[0],   'index(g:vam_plugin_whitelist, v:val) != -1')
  endif

  " add new_runtime_paths state if not present in opts yet
  let new_runtime_paths = get(opts, 'new_runtime_paths', [])
  let to_be_activated   = get(opts, 'to_be_activated',   {})


  let opts.new_runtime_paths = new_runtime_paths
  let opts.to_be_activated   = to_be_activated

  for a in args[0]
    let to_be_activated[a] = 1
  endfor

  call call('vam#ActivateRecursively', args)

  if topLevel
    " deferred tasks:
    " - add addons to runtimepath
    " - add source plugin/**/*.vim files in case Activate was called long
    "   after .vimrc has been sourced

    " add paths after ~/.vim but before $VIMRUNTIME
    " don't miss the after directories if they exist and
    " put them last! (Thanks to Oliver Teuliere)
    let rtp = split(&runtimepath, '\v(\\@<!(\\.)*\\)@<!\,')
    let escapeComma = 'escape(v:val, '','')'
    let after = filter(map(copy(new_runtime_paths), 'v:val."/after"'), 'isdirectory(v:val)')
    if !s:c.dont_source
      let &runtimepath=join(rtp[:0] + map(copy(new_runtime_paths), escapeComma)
                  \                 + rtp[1:]
                  \                 + map(after, escapeComma),
                  \         ",")
    endif
    unlet rtp

    for rtp in new_runtime_paths
      " filetype off/on would do the same ?
      call vam#GlobThenSource(rtp, 'ftdetect/*.vim')
    endfor

    " HACKS source files which Vim only sources at startup (before VimEnter)
    "
    " using force is very likely to cause the plugin to be sourced twice
    " I hope the plugins don't mind
    if (&loadplugins && !has('vim_starting')) || get(opts, 'force_loading_plugins_now', 0)
      " get all au groups which have been defined before sourcing additional
      " plugin files
      let oldaugs = s:GetAuGroups()

      for rtp in new_runtime_paths
        call vam#GlobThenSource(rtp, 'plugin/**/*.vim')
        call vam#GlobThenSource(rtp, 'after/plugin/**/*.vim')
      endfor

      " Now find out which au groups are new and run them manually, cause
      " Vim does so only when starting up. NerdTree and powerline are two
      " plugins serving as sample. Both use VimEnter.
      let newaugs = filter(s:GetAuGroups(), '!has_key(oldaugs, v:key)')
      let event_to_groups = {}
      for [group, events] in items(newaugs)
        for event in events
          if has_key(event_to_groups, event)
            call add(event_to_groups[event], group)
          else
            let event_to_groups[event] = [group]
          endif
        endfor
      endfor
      for event in filter((has('gui_running')?['GUIEnter']:[])+['VimEnter',
            \              'TabEnter', 'WinEnter', 'BufEnter', 'BufWinEnter'],
            \             'has_key(event_to_groups, v:val)')
        for group in event_to_groups[event]
          execute 'doautocmd' group event
        endfor
      endfor

      if !empty(new_runtime_paths)
        " The purpose of this line is to "refresh" buffer local vars and syntax.
        " (eg when loading a python plugin when opening a .py file)
        " Maybe its the responsibility of plugins to "refresh" settings of
        " buffers which are already open - I don't expect them to do so.
        " Let's see how much this breaks.
        call map(filter(range(1, bufnr('$')),
              \         'bufexists(v:val)'),
              \  's:ResetVars(v:val)')
      endif
    endif

    let failed = filter(keys(to_be_activated), '!has_key(s:c.activated_plugins, v:val)')
    if !empty(failed)
      throw 'These plugins could not be activated for some reason: '.string(failed)
    endif
  endif
endfun

fun! vam#DisplayAddonInfoLines(name, repository)
  let name = a:name
  let repository = a:repository
  let lines = []
  call add(lines, 'Plugin: '.name.((has_key(repository, 'version'))?(' version '.repository.version):('')))
  if has_key(repository, 'vim_script_nr')
    call add(lines, 'Script number: '.repository.vim_script_nr)
    call add(lines, 'Vim.org page: http://www.vim.org/scripts/script.php?script_id='.repository.vim_script_nr)
  endif
  if has_key(repository, 'homepage')
    call add(lines, 'Home page: '.repository.homepage)
  elseif repository.url =~? '^\w\+://github\.com/'
    call add(lines, 'Home page: https://github.com/'.substitute(repository.url, '^\V\w\+://github.com/\v([^/]+\/[^/]{-}%(\.git)?)%(\/|$)@=.*', '\1', ''))
  elseif repository.url =~? '^\w\+://bitbucket\.org/'
    call add(lines, 'Home page: https://bitbucket.org/'.substitute(repository.url, '^\V\w\+://bitbucket.org/\v([^/]+\/[^/]+).*', '\1', ''))
  endif
  call add(lines, 'Source URL: '.repository.url.' (type '.get(repository, 'type', 'archive').')',)
  for key in filter(keys(repository), 'v:val!~#''\vurl|vim_script_nr|version|type|homepage''')
    call add(lines, key.': '.string(repository[key]))
  endfor
  return lines
endfun

fun! vam#ShowRepositoryInfo(label, name, repository)
  call vam#Log('===== '.a:label.' '.repeat('=', &columns-10-len(a:label)), 'Comment')
  call vam#Log(join(vam#DisplayAddonInfoLines(a:name, a:repository),"\n"), 'None')
endf

fun! vam#DisplayAddonInfo(name, fuzzy)
  let name = a:name
  let found = 0

  let repository = get(g:vim_addon_manager.plugin_sources, name, {})
  if !empty(repository)
    call vam#ShowRepositoryInfo("by-name", name, repository)
    let found += 1
  endif

  " try to find by script-id
  if empty(repository) && a:name =~ '^\d\+$'
    " try to find by script id
    let dict = filter(copy(g:vim_addon_manager.plugin_sources), '+get(v:val,"vim_script_nr",-1) == '.(+a:name))
    if (empty(dict))
      throw "Unknown script ".a:name
    else
      let name = keys(dict)[0]
      call vam#ShowRepositoryInfo("by-id", keys(dict)[0], values(dict)[0])
      let found += 1
    endif
  endif

  if found == 0 && a:fuzzy

    " try to find by comparing name against anything found in the dictionary.
    " Thus you can also search for git://github/...

    " normalize .git in git(hub) names:
    let name = substitute(name, '\.git$','','g')

    for [r,k] in items(g:vim_addon_manager.plugin_sources)
      if string(k) =~ name
        call vam#ShowRepositoryInfo("by-fuzzy-search", r, k)
        let found += 1
      endif
      unlet r k
    endfor
  endif

  if found == 0
    echo "Invalid plugin name: " . a:name
    return
  endif

endfun

fun! vam#DisplayAddonsInfo(names)
  call vam#install#LoadPool()
  for name in a:names
    call vam#DisplayAddonInfo(name, 1)
  endfor
endfun

fun! vam#SourceFiles(fs)
  for file in a:fs
    exec 'source '.fnameescape(file)
  endfor
endfun

" FIXME won't list hidden files as well
if v:version>703 || (v:version==703 && has('patch465'))
  fun! vam#GlobInDir(dir, glob)
    return glob(fnameescape(a:dir).'/'.a:glob, 1, 1)
  endfun
else
  fun! vam#GlobInDir(dir, glob)
    return split(glob(fnameescape(a:dir).'/'.a:glob, 1), "\n")
  endfun
endif

fun! vam#GlobThenSource(dir, glob)
  if s:c.dont_source | return | endif
  call vam#SourceFiles(vam#GlobInDir(a:dir, a:glob))
endfun

if s:c.source_missing_files
  augroup VIM_PLUGIN_MANAGER
    autocmd! VimEnter * nested call  vam#SourceMissingPlugins()
  augroup END
endif

" taken from tlib
fun! vam#OutputAsList(command) "{{{3
    " let lines = ''
    redir => lines
    silent! exec a:command
    redir END
    return split(lines, '\n')
endfun

let s:sep=fnamemodify(expand('<sfile>:h', 1), ':p')[-1:]
let s:sesep=escape(s:sep, '\&~')
let s:resep='\V'.escape(s:sep, '\').'\+'
fun! s:normpath(path)
  return substitute(expand(fnameescape(resolve(a:path)), 1), s:resep, s:sesep, 'g')
endfun

" hack: Vim sources plugin files after sourcing .vimrc
"       Vim doesn't source the after/plugin/*.vim files in other runtime
"       paths. So do this *after* plugin/* files have been sourced
"
"       If you activate addons in plugin/*.vim files Vim will miss
"       plugin/*.vim files of those files - so make sure they are alle sourced
" 
" This function takes about 1ms to execute my system
fun! vam#SourceMissingPlugins()
  " files which should have been sourced:
  let fs = []
  let rtp = split(&runtimepath, '\v(\\@<!(\\.)*\\)@<!\,')
  for r in rtp | call extend(fs, vam#GlobInDir(r, 'plugin/**/*.vim')) | endfor
  call map(fs, 's:normpath(v:val)')

  let scriptnames = map(vam#OutputAsList('scriptnames'), 's:normpath(v:val[(stridx(v:val,":")+2):-1])')
  call filter(fs, 'index(scriptnames,  v:val) == -1')
  call vam#SourceFiles(fs)
endfun

fun! vam#AddonInfoFile(name)
  " history:
  " 1) plugin-info.txt was the first name (deprecated)
  " 2) a:name-addon-info.txt was the second recommended name (maybe deprecated - no hurry)
  " 3) Now the recommended way is addon-info.json because:
  "   - you can rename a script without having to rename the file
  "   - json says all about its contents (Let's hope all browsers still render
  "     it in a readable way

  let p = vam#PluginDirFromName(a:name)
  let default = p.'/addon-info.json'
  let choices = [ default , p.'/plugin-info.txt', p.'/'.a:name.'-addon-info.txt']
  for f in choices
    if filereadable(f)
      return f
    endif
  endfor
  return default
endfun

" looks like an error but is not. Catches users attention. Logs to :messages
fun! vam#Log(s, ...)
  if s:c.log_to_buf
    let nr = bufnr(s:c.log_buffer_name)
    if nr == -1
      " create buffer and add date header
      execute 'split' fnameescape(s:c.log_buffer_name)
      cal append('$', '>>>>>>>>>>>> '.strftime('%c'))

      autocmd! BufDelete <buffer> w
      " on quit BufDelete is not run!!
      autocmd! VimLeave <buffer> w

    else
      exec 'b '.nr
    endif
    cal append('$', split(a:s, "\n", 1))
    " if the buffer appears to be modified vim asks questions when quitting,
    " I want it to be silent, it gets written bi au command see above
    " yes - if vim crashes logs are lost. I hope it doesn't happen to often.
    " Writing on each messages seems overkill to me - The log may get long
    " over time
    setlocal nomodified
  else
    let hi = a:0 > 0 ? a:1 : 'WarningMsg'
    exec 'echohl '. hi
    for l in split(a:s, "\n", 1)
      if empty(l)
        echom ' '
      else
        echom l
      endif
    endfor
    echohl None
  endif
endfun

" If you want these commands witohut activating plugins call
" vam#ActivateAddons([]) with empty list. Not moving them into plugin/vam.vim
" to prevent additional IO seeks.

" its likely that the command names change introducing nice naming sheme
" Not sure which is best. Options:
" 1) *VAM  2) Addon* 3) VAM*
" 3 seems to be best but is more to type.
" Using 1) you can still show all commands by :*VAM<c-d> but this scheme is
" less common. So 2) is my favorite right now. I'm too lazy to break things at
command! -nargs=* -bar -complete=customlist,vam#install#NotInstalledAddonCompletion InstallAddons :call vam#install#Install([<f-args>])
command! -nargs=* -bar -complete=customlist,vam#install#AddonCompletion ActivateAddons :call vam#ActivateAddons([<f-args>])
command! -nargs=* -bar -complete=customlist,vam#install#AddonCompletion AddonsInfo :call vam#DisplayAddonsInfo([<f-args>])
command! -nargs=* -bar -complete=customlist,vam#install#InstalledAddonCompletion ActivateInstalledAddons :call vam#ActivateAddons([<f-args>])
command! -nargs=* -bar -complete=customlist,vam#install#UpdateCompletion UpdateAddons :call vam#install#Update([<f-args>])
command! -nargs=0 -bar UpdateActivatedAddons exec 'UpdateAddons '.join(keys(g:vim_addon_manager.activated_plugins),' ')
command! -nargs=0 -bar ListActivatedAddons :echo join(keys(g:vim_addon_manager.activated_plugins))
command! -nargs=* -bar -complete=customlist,vam#install#UninstallCompletion UninstallNotLoadedAddons :call vam#install#UninstallAddons([<f-args>])

command! -nargs=* -complete=customlist,vam#bisect#BisectCompletion AddonsBisect :call vam#bisect#Bisect(<f-args>)

fun! s:RunInstallHooks(plugins)
  for name in a:plugins
    call vam#install#RunHook('post-install', vam#AddonInfo(name), vam#install#GetRepo(name, {}), vam#PluginDirFromName(name), {})
  endfor
endfun
command! -nargs=+ -complete=customlist,vam#install#InstalledAddonCompletion RunInstallHooks :call s:RunInstallHooks([<f-args>])


" plugin name completion function:
if !empty(s:c.addon_completion_lhs)
  augroup VAM_addon_name_completion
    autocmd!
    execute 'autocmd FileType vim inoremap <buffer> <expr> '.s:c.addon_completion_lhs.' vam#utils#CompleteWith("vam#install#CompleteAddonName")'
  augroup END
endif

" vim: et ts=8 sts=2 sw=2
