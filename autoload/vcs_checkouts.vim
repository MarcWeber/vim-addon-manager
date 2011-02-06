" this may be useful for other projects.
" Thus move checking .hg .svn etc into a different file

fun! vcs_checkouts#Update(dir)
  let directory = a:dir
  if isdirectory(directory.'/.git')
    call s:exec_in_dir([{'d': directory, 'c': 'git pull'}])
  elseif isdirectory(directory.'/.svn')
    call s:exec_in_dir([{'d': directory, 'c': 'svn update'}])
  elseif isdirectory(directory.'/.bzr')
    call s:exec_in_dir([{'d': directory, 'c': 'bzr pull'}])
  elseif isdirectory(directory.'/.hg')
    call s:exec_in_dir([
          \ {'d': directory, 'c': 'hg pull'},
          \ {'d': directory, 'c': 'hg update'}
          \ ])
  else
    " not knowing how to update a repo is not a failure
    return 0
  endif
  if v:shell_error
    throw "updating ".a:dir." falied. Got exit code: ".v:shell_error
  endif
  return 1
endf

" repository = {'type': git|hg|svn|bzr, 'url': .. }
fun! vcs_checkouts#Checkout(targetDir, repository)
  if a:repository['type'] == 'git'
    exec '!'.scriptmanager_util#ShellDSL('git clone $ $p', a:repository['url'], a:targetDir)
    if !isdirectory(a:targetDir)
      throw "Failed checking out ".a:targetDir."!"
    endif
  elseif a:repository['type'] == 'hg'
    let parent = fnamemodify(a:targetDir,':h')
    exec '!'.scriptmanager_util#ShellDSL('hg clone $ $p', a:repository['url'], a:targetDir)
    if !isdirectory(a:targetDir)
      throw "Failed checking out ".a:targetDir."!"
    endif
  elseif a:repository['type'] == 'bzr'
    exec '!'.scriptmanager_util#ShellDSL('bzr branch $ $p', a:repository['url'], a:targetDir)
    if !isdirectory(a:targetDir)
      throw "Failed checking out ".a:targetDir."!"
    endif
  elseif a:repository['type'] == 'svn'
    let parent = fnamemodify(a:targetDir,':h')
    call s:exec_in_dir([{'d': parent, 'c': 'svn checkout '.s:shellescape(a:repository['url']).' '.s:shellescape(a:targetDir)}])
    if !isdirectory(a:targetDir)
      throw "Failed checking out ".a:targetDir."!"
    endif
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
        " http://stackoverflow.com/questions/355988/how-do-i-deal-with-quote-characters-when-using-cmd-exe
        " cmd should neither have have /c nor /K (?)
        " Silex (irc) helped finding this
        exec '!"'.c.c.'"'
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
      if has_key(c,"d")
        call add(cmds_str, "cd ".s:shellescape(c.d))
      endif
      if has_key(c,"c")
        call add(cmds_str, c.c)
      endif
    endfor
    exec '!'.join(cmds_str," && ")
    if v:shell_error != 0
      throw "error executing ".string(cmds_str)
    endif
  endif
endf

fun! s:shellescape(s)
  return shellescape(a:s,1)
endf
