" this may be useful for other projects.
" Thus move checking .hg .svn etc into a different file

fun! vcs_checkouts#Update(dir)
  let directory = a:dir
  if isdirectory(directory.'/.git')
    call s:exec_in_dir([{'d': directory, 'c': 'git pull'}])
    return !v:shell_error
  elseif isdirectory(directory.'/.svn')
    call s:exec_in_dir([{'d': directory, 'c': 'svn update'}])
    return !v:shell_error
  elseif isdirectory(directory.'/.hg')
    call s:exec_in_dir([
          \ {'d': directory, 'c': 'hg pull'},
          \ {'d': directory, 'c': 'hg update'},
          \ {'d': directory, 'c': 'hg merge'}
          \ ])
    return !v:shell_error
  else
    echoe "Updating plugin ".a:name." not implemented yet."
    return 0
  endif
endf

" repository = {'type': svn|hg|git, 'url': .. }
fun! vcs_checkouts#Checkout(targetDir, repository)
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
    call s:exec_in_dir([{'d': parent, 'c': 'svn checkout '.s:shellescape(a:repository['url']).' '.s:shellescape(a:targetDir)}])
    if !isdirectory(a:targetDir)
      throw "Failed checking out ".a:targetDir."!"
    endif
  endif
endf

fun! s:exec_in_dir(cmds)
  call vcs_checkouts#ExecIndir(a:cmds)
endf

fun! vcs_checkouts#ExecIndir(cmds)
  if has('win16') || has('win32') || has('win64')
    " set different lcd in extra buffer:
    new
    let lcd=""
    for c in a:cmds
      if has_key(c, "d")
        " TODO quoting
        exec "lcd ".c.d
      endif
      exec '!'.c.c
      " break if one of the pased commands failes:
      if v:shell_error != 0
        break
      endif
    endfor
    " should lcd withou args be used instead?
    bw!
  else
    " execute command sequences on linux
    let cmds_str = []
    for c in a:cmds
      call add(cmds_str, (has_key(c,"d") ? "cd ".s:shellescape(c.d)." && " : "" ). c.c)
    endfor
    exec '!'.join(cmds_str," && ")
  endif
endf

fun! s:shellescape(s)
  return shellescape(a:s,1)
endf
