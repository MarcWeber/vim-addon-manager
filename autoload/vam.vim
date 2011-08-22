" see README

" this file contains code which is always used
" code which is used for installing / updating etc should go into vam/install.vim


" don't need a plugin. If you want to use this plugin you call Activate once
" anyway
augroup VIM_ADDON_MANAGER
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
let s:c['missing_addon_infos'] = get(s:c,'missing_addon_infos', {})
let s:c['activated_plugins'] = get(s:c,'activated_plugins', {})
" If directory where plugin is installed is writeable, then this plugin was
" likely installed by user according to the instruction. If it is not, then it
" is likely a system-wide installation.
let s:c['system_wide'] = !filewritable(expand('<sfile>:h:h:h'))
let s:c['plugin_root_dir'] = get(s:c, 'plugin_root_dir', ((s:c['system_wide'])?
            \                                               ('~/vim-addons'):
            \                                               (expand('<sfile>:h:h:h'))))
" ensure we have absolute paths (windows doesn't like ~/.. ) :
let s:c['plugin_root_dir'] = expand(s:c['plugin_root_dir'])
let s:c['known'] = get(s:c,'known','vim-addon-manager-known-repositories')
let s:c['change_to_unix_ff'] = get(s:c, 'change_to_unix_ff', (g:os=~#'unix'))
let s:c['do_diff'] = get(s:c, 'do_diff', 1)
let s:c['dont_source'] = get(s:c, 'dont_source', 0)

" for testing it is necessary to avoid the "Press enter to continue lines"
" (cygwin?). Thus provide an option making all shell commands silent
" However don't set this to 1 by default. If something goes wrong I want users
" to see what went wrong. Not everybody knows how to debug VimL!
let s:c['silent_shell_commands'] = get(s:c,'silent_shell_commands', 0)

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
  let stringless_body = substitute(a:s,'"\%(\\.\|[^"\\]\)*"','','g')
  return stringless_body !~# "[^,:{}\\[\\]0-9.\\-+Eaeflnr-u \t]"
endf

" use join so that you can break the dict into multiple lines. This makes
" reading it much easier
fun! vam#ReadAddonInfo(path)

  " don't add "b" because it'll read dos files as "\r\n" which will fail the
  " check and evaluate in eval. \r\n is checked out by some msys git
  " versions with strange settings

  " using eval is evil!
  let body = join(readfile(a:path),"")

  if s:c.dont_source && '1' != system('php', '<?php echo is_array(json_decode(file_get_contents('.string(a:path).'), true));')
    call vam#Log( "Invalid JSON in ".a:path."!")
    return {}
  endif

  if vam#VerifyIsJSON(body)
      " using eval is now safe!
      return eval(body)
  else
    call vam#Log( "Invalid JSON in ".a:path."!")
    return {}
  endif

endf

fun! vam#PluginDirByName(name)
  return s:c['plugin_root_dir'].'/'.substitute(a:name,'[\\/:]','','g')
endf
fun! vam#PluginRuntimePath(name)
  let info = vam#AddonInfo(a:name)
  return vam#PluginDirByName(a:name).(has_key(info, 'runtimepath') ? '/'.info['runtimepath'] : '')
endf

" doesn't check dependencies!
fun! vam#IsPluginInstalled(name)
  let d = vam#PluginDirByName(a:name)
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
  let opts = a:0 == 0 ? {} : a:1

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
        \ extend(copy(opts), { 'plugin_sources' : extend(copy(dependencies), get(opts, 'plugin_sources',{}))}))

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

  " don't know why activating known-repos causes trouble Silex reported it
  " does. Doing so is not recommended. So prevent it
  if !exists('g:in_load_known_repositories') && index(args[0],"vim-addon-manager-known-repositories") != -1
    throw "You should not activate vim-addon-manager-known-repositories. vim-addon-mananger will do so for you when needed. This way Vim starts up faster in the common case. Also try vam#install#LoadKnownRepos() instead."
  endif

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

    if !has('vim_starting')
      for rtp in new_runtime_paths
        call vam#GlobThenSource(rtp.'/plugin/**/*.vim')
        call vam#GlobThenSource(rtp.'/after/plugin/**/*.vim')
      endfor
    endif

    for rtp in new_runtime_paths
      call vam#GlobThenSource(rtp.'/ftdetect/*.vim')
    endfor

  endif
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
      call vam#GlobThenSource(vam#PluginDirByName(p).'/after/plugin/**/*.vim')
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

  let p = vam#PluginDirByName(a:name)
  let default = p.'/addon-info.json'
  let choices = [ default , p.'/plugin-info.txt', p.'/'.a:name.'-addon-info.txt']
  for f in choices
    if filereadable(f)
      return f
    endif
  endfor
  return default
endf

" looks like an error but is not. Catches users attention. Logs to :messages
fun! vam#Log(s, ...)
  let hi = a:0 > 0 ? a:1 : 'WarningMsg'
  exec 'echohl '. hi
  for l in split(a:s, "\n")
    exec 'echomsg '.string(l)
  endfor
  echohl None
endfun

" If you want these commands witohut activating plugins call
" vam#ActivateAddons([]) with empty list. Not moving them into plugin/vam.vim
" to prevent additional IO seeks.
command! -nargs=* -complete=customlist,vam#install#AddonCompletion InstallAddons :call vam#install#Install([<f-args>])
command! -nargs=* -complete=customlist,vam#install#AddonCompletion ActivateAddons :call vam#ActivateAddons([<f-args>])
command! -nargs=* -complete=customlist,vam#install#InstalledAddonCompletion ActivateInstalledAddons :call vam#ActivateAddons([<f-args>])
command! -nargs=* -complete=customlist,vam#install#UpdateCompletion UpdateAddons :call vam#install#Update([<f-args>])
command! -nargs=* -complete=customlist,vam#install#UninstallCompletion UninstallNotLoadedAddons :call vam#install#UninstallAddons([<f-args>])

" vim: et ts=8 sts=2 sw=2
