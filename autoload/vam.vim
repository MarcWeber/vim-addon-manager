" see README

" this file contains code which is always used
" code which is used for installing / updating etc should go into vam/install.vim


" don't need a plugin. If you want to use this plugin you call Activate once
" anyway
augroup VAM_addon_info_handlers
  autocmd!
  autocmd BufRead,BufNewFile *-addon-info.txt,addon-info.json
    \ setlocal ft=addon-info
    \ | setlocal syntax=json
    \ | syn match Error "^\s*'"
  autocmd BufWritePost *-addon-info.txt,addon-info.json call vam#ReadAddonInfo(expand('%'))
augroup end

fun! vam#DefineAndBind(local,global,default)
  return 'if !exists('.string(a:global).') | let '.a:global.' = '.a:default.' | endif | let '.a:local.' = '.a:global
endf


" assign g:os
for os in split('amiga beos dos32 dos16 mac macunix os2 qnx unix vms win16 win32 win64 win32unix', ' ')
  if has(os) | let g:os = os | break | endif
endfor
let g:is_win = g:os[:2] == 'win'

exec vam#DefineAndBind('s:c','g:vim_addon_manager','{}')
let s:c['auto_install'] = get(s:c,'auto_install', 0)
" repository locations:
let s:c['plugin_sources'] = get(s:c,'plugin_sources', {})
" if a plugin has an item here the dict value contents will be written as plugin info file
let s:c['activated_plugins'] = get(s:c,'activated_plugins', {})

" gentoo users may install VAM system wide. In that case s:d is not writeable.
" In the future this may be put into a gentoo specific patch.
let s:d = expand('<sfile>:h:h:h')
let s:c['plugin_root_dir'] = get(s:c, 'plugin_root_dir', filewritable(s:d) ? s:d : '~/.vim/vim-addons' )
unlet s:d

if s:c['plugin_root_dir'] == expand('$HOME')
  echoe "VAM: Don't install VAM into ~/.vim the normal way. See docs -> SetupVAM function. Put it int ~/.vim/vim-addons/vim-addon-manager for example."
  finish
endif

" ensure we have absolute paths (windows doesn't like ~/.. ) :
let s:c['plugin_root_dir'] = expand(s:c['plugin_root_dir'])
let s:c['dont_source'] = get(s:c, 'dont_source', 0)
let s:c['plugin_dir_by_name'] = get(s:c, 'plugin_dir_by_name', 'vam#DefaultPluginDirFromName')
let s:c['addon_completion_lhs'] = get(s:c, 'addon_completion_lhs', '<C-x><C-p>')

" More options that are used for plugins’ installation are listed in 
" autoload/vam/install.vim

if g:is_win
  " if binary-utils path exists then add it to PATH
  let s:c['binary_utils'] = get(s:c,'binary_utils',s:c['plugin_root_dir'].'\binary-utils')
  let s:c['binary_utils_bin'] = s:c['binary_utils'].'\dist\bin'
  if isdirectory(s:c['binary_utils'])
    let $PATH=$PATH.';'.s:c['binary_utils_bin']
  endif
endif

" additional plugin sources should go into your .vimrc or into the repository
" called "vim-addon-manager-known-repositories" referenced here:
if executable('git')
  let s:c['plugin_sources']["vim-addon-manager-known-repositories"] = { 'type' : 'git', 'url': 'git://github.com/MarcWeber/vim-addon-manager-known-repositories.git' }
else
  let s:c['plugin_sources']["vim-addon-manager-known-repositories"] = { 'type' : 'archive', 'url': 'http://github.com/MarcWeber/vim-addon-manager-known-repositories/tarball/master', 'archive_name': 'vim-addon-manager-known-repositories-tip.tar.gz' }
endif

fun! vam#VerifyIsJSON(s)
  " You must allow single-quoted strings in order for writefile([string()]) that 
  " adds missing addon information to work
  let scalarless_body = substitute(a:s, '\v\"%(\\.|[^"\\])*\"|\''%(\''{2}|[^''])*\''|true|false|null|[+-]?\d+%(\.\d+%([Ee][+-]?\d+)?)?', '', 'g')
  return scalarless_body !~# "[^,:{}[\\] \t]"
endf

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

endf

fun! vam#DefaultPluginDirFromName(name)
  " this function maps addon names to their storage location. \/: are replaced
  " by - (See name rewriting)
  return s:c.plugin_root_dir.'/'.substitute(a:name, '[\\/:]\+', '-', 'g')
endfun
fun! vam#PluginDirFromName(...)
  return call(s:c.plugin_dir_by_name, a:000, {})
endf
fun! vam#PluginRuntimePath(name)
  let info = vam#AddonInfo(a:name)
  return vam#PluginDirFromName(a:name).(has_key(info, 'runtimepath') ? '/'.info['runtimepath'] : '')
endf

" doesn't check dependencies!
fun! vam#IsPluginInstalled(name)
  let d = vam#PluginDirFromName(a:name)

  " this will be dropped in about 12 months which is end of 2012
  let old_path=s:c.plugin_root_dir.'/'.substitute(a:name, '[\\/:]\+', '', 'g')
  if d != old_path && isdirectory(old_path)
    if confirm("VAM has changed addon names policy for name rewriting. Rename ".old_path." to ".d."?", "&Ok") == 1
      call rename(old_path, d)
    endif
  endif

  " if dir exists and its not a failed download
  " (empty archive directory)
  return isdirectory(d)
    \ && ( !isdirectory(d.'/archive')
    \     || len(glob(d.'/archive/*')) > 0 )
endf

" {} if file doesn't exist
fun! vam#AddonInfo(name)
  let infoFile = vam#AddonInfoFile(a:name)
  return filereadable(infoFile)
    \ ? vam#ReadAddonInfo(infoFile)
    \ : {}
endf


" opts: {
"   'plugin_sources': additional sources (used when installing dependencies)
"   'auto_install': when 1 overrides global setting, so you can autoinstall
"   trusted repositories only
" }
fun! vam#ActivateRecursively(list_of_names, ...)
  let opts = extend({'run_install_hooks': 1}, a:0 == 0 ? {} : a:1)

  for name in a:list_of_names
    if !has_key(s:c['activated_plugins'],  name)
      " break circular dependencies..
      let s:c['activated_plugins'][name] = 0

      let infoFile = vam#AddonInfoFile(name)
      if !filereadable(infoFile) && !vam#IsPluginInstalled(name)
        call vam#install#Install([name], opts)
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
      call add(opts['new_runtime_paths'], rtp)

      let s:c['activated_plugins'][name] = 1
    endif
  endfor
endf

let s:top_level = 0
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

  let opts = args[1]
  let topLevel = !has_key(opts, 'new_runtime_paths')

  " add new_runtime_paths state if not present in opts yet
  let new_runtime_paths = get(opts, 'new_runtime_paths',[])
  let opts['new_runtime_paths'] = new_runtime_paths

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
      call vam#GlobThenSource(rtp.'/ftdetect/*.vim')
    endfor

    " using force is very likely to cause the plugin to be sourced twice
    " I hope the plugins don't mind
    if !has('vim_starting') || get(opts, 'force_loading_plugins_now', 0)
      for rtp in new_runtime_paths
        call vam#GlobThenSource(rtp.'/plugin/**/*.vim')
        call vam#GlobThenSource(rtp.'/after/plugin/**/*.vim')
      endfor

      if !empty(new_runtime_paths)
        " The purpose of this line is to "refresh" buffer local vars and syntax.
        " (eg when loading a python plugin when opening a .py file)
        " Maybe its the responsibility of plugins to "refresh" settings of
        " buffers which are already open - I don't expect them to do so.
        " Let's see how much this breaks.
        call map(filter(range(1, bufnr('$')),
              \         'bufexists(v:val)'),
              \  'setbufvar(v:val, "&filetype", getbufvar(v:val, "&filetype"))')
      endif

    endif

  endif
endfun

fun! vam#DisplayAddonInfo(name)
  let repository = get(g:vim_addon_manager['plugin_sources'], a:name, {})
  let name = a:name
  if empty(repository) && a:name =~ '^\d\+$'
    " try to find by script id
    let dict = filter(copy(g:vim_addon_manager['plugin_sources']), 'get(v:val,"vim_script_nr","")."" == '.string(1*a:name))
    if (empty(dict))
      throw "unknown script ".a:name
    else
      let repository = get(values(dict), 0, {})
      let name = keys(dict)[0]
    endif
  end
  if empty(repository)
    echo "Invalid plugin name: " . a:name
    return
  endif
  call vam#Log(repeat('=', &columns-1), 'Comment')
  call vam#Log('Plugin: '.name.((has_key(repository, 'version'))?(' version '.repository.version):('')), 'None')
  if has_key(repository, 'vim_script_nr')
    call vam#Log('Script number: '.repository.vim_script_nr, 'None')
    call vam#Log('Vim.org page: http://www.vim.org/scripts/script.php?script_id='.repository.vim_script_nr, 'None')
  endif
  if has_key(repository, 'homepage')
    call vam#Log('Home page: '.repository.homepage)
  elseif repository.url =~? '^\w\+://github\.com/'
    call vam#Log('Home page: https://github.com/'.substitute(repository.url, '^\V\w\+://github.com/\v([^/]+\/[^/]{-}%(\.git)?)%(\/|$)@=.*', '\1', ''), 'None')
  elseif repository.url =~? '^\w\+://bitbucket\.org/'
    call vam#Log('Home page: https://bitbucket.org/'.substitute(repository.url, '^\V\w\+://bitbucket.org/\v([^/]+\/[^/]+).*', '\1', ''), 'None')
  endif
  call vam#Log('Source URL: '.repository.url.' (type '.get(repository, 'type', 'archive').')', 'None')
  for key in filter(keys(repository), 'v:val!~#''\vurl|vim_script_nr|version|type|homepage''')
    call vam#Log(key.': '.string(repository[key]), 'None')
  endfor
endfun

fun! vam#DisplayAddonsInfo(names)
  call vam#install#LoadPool()
  for name in a:names
    call vam#DisplayAddonInfo(name)
  endfor
endfun

fun! vam#GlobThenSource(glob)
  if s:c.dont_source | return | endif
  for file in split(glob(a:glob),"\n")
    exec 'source '.fnameescape(file)
  endfor
endf

augroup VIM_PLUGIN_MANAGER
  autocmd VimEnter * call  vam#Hack()
augroup end

" hack: Vim sources plugin files after sourcing .vimrc
"       Vim doesn't source the after/plugin/*.vim files in other runtime
"       paths. So do this *after* plugin/* files have been sourced
fun! vam#Hack()
  " now source after/plugin/**/*.vim files explicitly. Vim doesn't do it (hack!)
  for p in keys(s:c['activated_plugins'])
      call vam#GlobThenSource(vam#PluginDirFromName(p).'/after/plugin/**/*.vim')
  endfor
endf

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
command! -nargs=* -complete=customlist,vam#install#NotInstalledAddonCompletion InstallAddons :call vam#install#Install([<f-args>])
command! -nargs=* -complete=customlist,vam#install#AddonCompletion ActivateAddons :call vam#ActivateAddons([<f-args>])
command! -nargs=* -complete=customlist,vam#install#AddonCompletion AddonsInfo :call vam#DisplayAddonsInfo([<f-args>])
command! -nargs=* -complete=customlist,vam#install#InstalledAddonCompletion ActivateInstalledAddons :call vam#ActivateAddons([<f-args>])
command! -nargs=* -complete=customlist,vam#install#UpdateCompletion UpdateAddons :call vam#install#Update([<f-args>])
command! -nargs=0 UpdateActivatedAddons exec 'UpdateAddons '.join(keys(g:vim_addon_manager['activated_plugins']),' ')
command! -nargs=* -complete=customlist,vam#install#UninstallCompletion UninstallNotLoadedAddons :call vam#install#UninstallAddons([<f-args>])

function! s:RunInstallHooks(plugins)
  for name in a:plugins
    call vam#install#RunHook('post-install', vam#AddonInfo(name), vam#install#GetRepo(name, {}), vam#PluginDirFromName(name), {})
  endfor
endfunction
command! -nargs=+ -complete=customlist,vam#install#InstalledAddonCompletion RunInstallHooks :call s:RunInstallHooks([<f-args>])


" plugin name completion function:
if !empty(s:c.addon_completion_lhs)
  augroup VAM_addon_name_completion
    autocmd!
    execute 'autocmd FileType vim inoremap <buffer> <expr> '.s:c.addon_completion_lhs.' vam#utils#CompleteWith("vam#install#CompleteAddonName")'
  augroup END
endif

" vim: et ts=8 sts=2 sw=2
