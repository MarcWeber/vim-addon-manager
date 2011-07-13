exec vam#DefineAndBind('s:c','g:vim_addon_manager','{}')
let s:c.shallow_clones = get(s:c,'shallow_clones',1)
let s:c.scm_extra_args = get(s:c,'scm_extra_args',{})

let s:se = s:c.scm_extra_args
" this is not proberly quoted yet thus its will change:
" using list so that we can encode ['$ $',[1,2]] (quoting values if needed)
let s:se.git = get(s:c,'git', [s:c.shallow_clones ? '--depth 1' : ''])

" this may be useful for other projects.
" Thus move checking .hg .svn etc into a different file

fun! vcs_checkouts#Update(dir)
  let directory = a:dir
  if isdirectory(directory.'/.git')
    call s:exec_in_dir([{'d': directory, 'c': 'git fetch'}])
  elseif isdirectory(directory.'/.svn')
    call s:exec_in_dir([{'d': directory, 'c': 'svn update'}])
  elseif isdirectory(directory.'/.bzr')
    call vam#utils#RunShell('bzr pull -d $', directory)
  elseif isdirectory(directory.'/.hg')
    call vam#utils#RunShell('hg pull -u -R $', directory)
  else
    " not knowing how to update a repo is not a failure
    return 0
  endif
  if v:shell_error
    throw "Updating ".a:dir." falied. Got exit code: ".v:shell_error
  endif
  return 1
endf

" repository = {'type': git|hg|svn|bzr, 'url': .. }
fun! vcs_checkouts#Checkout(targetDir, repository)
  if a:repository['type'] == 'git'
    call vam#utils#RunShell('git clone '.s:se.git[0].' $ $p', a:repository.url, a:targetDir)
  elseif a:repository['type'] == 'hg'
    call vam#utils#RunShell('hg clone $ $p', a:repository.url, a:targetDir)
  elseif a:repository['type'] == 'bzr'
    call vam#utils#RunShell('bzr branch $ $p', a:repository.url, a:targetDir)
  elseif a:repository['type'] == 'svn'
    let args=['svn checkout $ $p', a:repository.url, a:targetDir]
    for key in filter(['username', 'password'], 'has_key(a:repository, v:val)')
      let args[0].=' --'.key.' $'
      let args+=[a:repository[key]]
    endfor
    call call('vam#utils#RunShell', args)
  else
    " Keep old behavior: no throw for unknown repository type
    return
  endif
  if !isdirectory(a:targetDir)
    throw "Failed checking out ".a:targetDir."!"
  endif
endf

fun! s:exec_in_dir(cmds)
  call vcs_checkouts#ExecIndir(a:cmds)
endf

fun! vcs_checkouts#ExecIndir(cmds) abort
  if g:is_win
    " set different lcd in extra buffer:
    new
    let lcd=""
    for c in a:cmds
      if has_key(c, "d")
        exec "lcd ".fnameescape(c.d)
      endif
      if has_key(c, "c")
        exec 'silent !'.c.c
      endif
      " break if one of the pased commands failes:
      if v:shell_error != 0
        throw "error executing ".c.c
      endif
    endfor
    " should lcd withou args be used instead?
    bw!
  else
    " execute command sequences on linux
    let cmds_str = []
    for c in a:cmds
      if has_key(c, "d")
        call add(cmds_str, "cd ".shellescape(c.d, 1))
      endif
      if has_key(c, "c")
        call add(cmds_str, c.c)
      endif
    endfor
    exec 'silent !'.join(cmds_str," && ")
    if v:shell_error != 0
      throw "error executing ".string(cmds_str)
    endif
  endif
endf
" vim: et ts=8 sts=2 sw=2
