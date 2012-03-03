" vam#DefineAndBind('s:c','g:vim_addon_manager','{}')
if !exists('g:vim_addon_manager') | let g:vim_addon_manager = {} | endif | let s:c = g:vim_addon_manager

" Defaulting to 7z why or why not?
let s:c.omit_7z=get(s:c, 'omit_7z', 0)

" let users override curl command. Reuse netrw setting
" Let's hope that nobody is using a dir called "curl " .. because
" substitution will be wrong then
let s:http_cmd = exists('g:netrw_http_cmd') ?
      \             substitute(g:netrw_http_cmd, '\c\vcurl(\.exe)?%(\ |$)', 'curl\1 --location --max-redirs 40 ', '') :
      \          executable('curl') ?
      \             'curl -L --max-redirs 40 -o' :
      \          executable('wget') ?
      \             'wget -O'
      \          :
      \             0

" for testing it is necessary to avoid the "Press enter to continue lines".
" Thus provide an option making all shell commands use “system”
let s:c['shell_commands_run_method'] = get(s:c, 'shell_commands_run_method', 'bang')

" insert arguments at placeholders $ shell escaping the value
" usage: s:shellescape("rm --arg $ -fr $p $p $p", [string, file1, file2, file3])
"
" the / \ annoyance of Windows is fixed by calling expand which replaces / by
" \ on Windows. This only happens by the $p substitution
" if $ is followed by a number its treated as index

" Examples:
" s:ShellDSL('$', 'escape this/\') == '''escape this/\'''
" s:ShellDSL('$1 $[2p] $1p', 'escape this/\',\'other\') =='''escape this/'' ''other'' ''escape this/'''
" s:ShellDSL('$.url $[1p.url] $1p.url', {'url':'URL'} ) =='''URL'' ''URL'' ''URL'''
fun! s:ShellDSL(special, cmd, ...) abort
  let args = a:000
  let r = ''
  let l = split(a:cmd, '\V$', 1)
  let r = l[0]
  let i = 0
  for x in l[1:]
    let list = matchlist(x, '\[\?\(\d*\)\(p\)\?\(\.[^ \t\]]*\)\?\]\?')
    if empty(list)
      " should not happen
      throw 's:ShellDSL, bad : '.x
    endif
    if list[1] != ''
      let p= args[list[1]-1]
    else
      let p = args[i]
      let i += 1
    endif
    if list[3] != ''
      for path in split(list[3],'\.')
        let tmp = p[path] | unlet p | let p = tmp
      endfor
    endif
    if list[2] == 'p'
      let p = expand(fnameescape(p))
    endif
    let r .= shellescape(p, a:special).x[len(list[0]):]
    unlet p
  endfor
  return r
endf

fun! s:Cmd(expect_code_0, cmd) abort
  call vam#Log(a:cmd, 'PreProc')
  if s:c.shell_commands_run_method[-4:] is# 'bang'
    execute '!'.a:cmd
  elseif s:c.shell_commands_run_method is# 'system'
    call vam#Log(system(a:cmd), 'None')
  else
    throw 'Unknown run method: '.s:c.shell_commands_run_method
  endif
  if a:expect_code_0 && v:shell_error != 0
    let s:c.last_shell_command = a:cmd
    throw "Command “".a:cmd."” exited with error code ".v:shell_error
  endif
  return v:shell_error
endf

" TODO improve this and move somewhere else?
fun! vam#utils#RunShell(...) abort
  let special=(s:c.shell_commands_run_method[-4:] is# 'bang')
  let cmd = call('s:ShellDSL', [special]+a:000)
  return s:Cmd(0, cmd)
endf

fun! vam#utils#ExecInDir(dir, ...) abort
  let special=(s:c.shell_commands_run_method[-4:] is# 'bang')
  if g:is_win
    " set different lcd in extra buffer:
    new
    try
      execute 'lcd' fnameescape(a:dir)
      let cmd=call('s:ShellDSL', [special]+a:000)
      call s:Cmd(1, cmd)
    finally
      bw!
    endtry
  else
    let cmd=s:ShellDSL(special, 'cd $p', a:dir).' && '.
          \ call('s:ShellDSL', [special]+a:000)
    call s:Cmd(1, cmd)
  endif
endf

fun! vam#utils#System(...)
  let cmd=call('s:ShellDSL', [0]+a:000)
  let r=system(cmd)
  if v:shell_error
    return 0
  endif
  return r
endfun

"Usages: EndsWith('name.tar',   '.tar', '.txt') returns 1 even if .tar was .txt
fun! s:EndsWith(name, ...)
  return  a:name =~? '\%('.substitute(join(a:000,'\|'),'\.','\\.','g').'\)$'
endf

" Warning: Currently hooks should not depend on order of their execution
let s:post_unpack_hooks={}
fun s:post_unpack_hooks.fix_layout(opts, targetDir, fixDir)
  " if there are *.vim files but no */**/*.vim files they layout is likely to
  " be broken. Try fixing it
  let rtpvimfiles=glob(a:targetDir.'/*.vim')
  if  !empty(rtpvimfiles) && empty(glob(a:targetDir.'/*/**/*.vim'))
    " also see [fix-layout]

    " fixing .vim file locations was missed above. So fix it now
    " example plugin requiring this: sketch
    if (!isdirectory(a:fixDir))
      call mkdir(a:fixDir, 'p')
    endif
    for f in map(split(rtpvimfiles, "\n"), 'fnamemodify(v:val, ":t")')
      call rename(a:targetDir.'/'.f, a:fixDir.'/'.f)
    endfor
  endif
endfun
fun s:post_unpack_hooks.change_to_unix_ff(opts, targetDir, fixDir)
  if get(a:opts, 'unix_ff', 0)
    for f in filter(vam#utils#Glob(a:targetDir.'/**/*.vim'), 'filewritable(v:val)==1')
      call writefile(map(readfile(f, 'b'),
                  \'((v:val[-1:] is# "\r")?(v:val[:-2]):(v:val))'), f, 'b')
    endfor
  endif
endfun

fun! s:StripIfNeeded(opts, targetDir)
  let strip_components = get(a:opts, 'strip-components', -1)

  if strip_components!=0
    call vam#utils#StripComponents(a:targetDir, strip_components, [a:targetDir.'/archive'])
  endif
endfun

" may throw EXCEPTION_UNPACK.*
" most packages are shipped in a directory. Eg ADDON/plugin/*
" strip-components=1 strips of this ADDON directory (implemented for tar.* " archives only)
"
" assumes the dir containing archive is writable to place tmp files in. eg
" .tar when unpacking .tar.gz. because gunzip and bunzip2 remove the original
" file a backup is made if del-source is not set. However file permissions may
" no tbe preserved. I don't think its worth fixing. If you think different
" contact me.

" !! If you change this run the test, please: call vim_addon_manager_tests#Tests('.')
fun! vam#utils#Unpack(archive, targetDir, ...)
  let opts = a:0 > 0 ? a:1 : {}
  let delSource = get(opts, 'del-source', 0)

  " [ ending, chars to strip, chars to add, command to do the unpacking ]
  let gzbzip2 = {
        \ '.xz':    [-4,   '', 'xz -d '  ],
        \ '.txz':   [-3, 'ar', 'xz -d '  ],
        \ '.gz':    [-4,   '', 'gzip -d' ],
        \ '.tgz':   [-3, 'ar', 'gzip -d' ],
        \ '.bz2':   [-5,   '', 'bzip2 -d'],
        \ '.tbz2':  [-4, 'ar', 'bzip2 -d'],
        \ '.tbz':   [-3, 'ar', 'bzip2 -d'],
        \ }


  let fixDir = a:targetDir.'/plugin'
  let type = get(opts, 'script-type', 'plugin')
  if type  =~# '\v^%(%(after\/)?syntax|indent|ftplugin)$'
    let fixDir = a:targetDir.'/'.type
  elseif type is 'color scheme'
    let fixDir = a:targetDir.'/colors'
  endif

  " 7z renames .tbz, .tbz2, .tar.bz2 to .tar, but it preserves names stored by 
  " gzip (if any): if you do
  "   tar -cf ../abc.tar . && gzip ../abc.tar && mv ../abc.tar.gz ../def.tar.gz
  " you will find that “7z x ../def.tar.gz” unpacks archive “abc.tar” because 
  " gzip stored its name.
  let use_7z=(!s:c.omit_7z && executable('7z'))

  " .vim file and type syntax?
  if a:archive =~? '\.vim$'
    " hook for plugin / syntax files: Move into the correct direcotry:
    if (!isdirectory(fixDir))
      call mkdir(fixDir, 'p')
    endif
    " also see [fix-layout]
    call writefile(readfile(a:archive,'b'), fixDir.'/'.fnamemodify(a:archive, ':t'), 'b')

  " .gz, .xz, .bz2 (or .vba.* or .tar.*)
  elseif call(function('s:EndsWith'), [a:archive] + keys(gzbzip2) )
    " I was told tar on Windows is buggy and can't handle xj or xz correctly
    " so unpack in two phases:
    for [k,z] in items(gzbzip2)
      if s:EndsWith(a:archive, k)
        " without ext
        let unpacked = a:archive[:z[0]]
        " correct ext
        let renameTo = unpacked.z[1]

        " PHASE (1): gunzip or bunzip using gzip,bzip2 or 7z:
        if use_7z
          call vam#utils#RunShell('7z x -o$ $', fnamemodify(a:archive, ':h'), a:archive)
        else
          " make a backup. gunzip etc rm the original file
          if !delSource
            let b = a:archive.'.bak'
            call vam#utils#CopyFile(a:archive, b)
          endif

          " unpack
          call vam#utils#RunShell(z[2].' $', a:archive)

          " copy backup back:
          if !delSource | call rename(b, a:archive) | endif
        endif

        if !filereadable(renameTo)
          " Windows gzip does not rename .tgz to .tar ?
          call rename(unpacked, renameTo)
        endif

        " PHASE (2): now unpack .tar or .vba file and tidy up temp file:
        call vam#utils#Unpack(renameTo, a:targetDir, extend({'del-source': 1}, opts))
        call delete(renameTo)
        break
      endif
      unlet k z
    endfor

  " .tar
  elseif s:EndsWith(a:archive, '.tar')
    if use_7z
      call vam#utils#RunShell('7z x -o$ $', a:targetDir, a:archive)
    else
      call vam#utils#ExecInDir(a:targetDir, 'tar -xf $', a:archive)
    endif
    call s:StripIfNeeded(opts, a:targetDir)

  " .zip
  elseif s:EndsWith(a:archive, '.zip')
    if use_7z
      call vam#utils#RunShell('7z x -o$ $', a:targetDir, a:archive)
    else
      call vam#utils#ExecInDir(a:targetDir, 'unzip $', a:archive)
    endif
    call s:StripIfNeeded(opts, a:targetDir)

  " .7z, .cab, .rar, .arj, .jar
  " (I have actually seen only .7z and .rar, but 7z supports other formats too)
  elseif s:EndsWith(a:archive,  '.7z','.cab','.arj','.rar','.jar')
    call vam#utils#RunShell('7z x -o$ $', a:targetDir, a:archive)
    call s:StripIfNeeded(opts, a:targetDir)

  elseif s:EndsWith(a:archive, '.vba','.vmb')
    " .vba reuse vimball#Vimball() function
    exec 'sp '.fnameescape(a:archive)
    call vimball#Vimball(1,a:targetDir)
    " wipe out buffer
    bw!
  else
    throw "EXCEPTION_UNPACK: don't know how to unpack ". a:archive
  endif

  if delSource && filereadable(a:archive)
    call delete(a:archive)
  endif

  let hargs=[opts, a:targetDir, fixDir]
  for key in keys(s:post_unpack_hooks)
    call call(s:post_unpack_hooks[key], hargs, {})
  endfor
endf

" Usage: Glob($HOME.'/*')
" FIXME won't list hidden files as well
fun! vam#utils#Glob(path)
  return split(glob(a:path),"\n")
  " The following does not filter . and .. components at all and spoils ** 
  " patterns (but it lacks `\' at the start of the line, so it is not even 
  " executed). Commenting this line just clarifies this issue
  " + filter(split(glob(substitute(a:path,'\*','.*','g')),"\n"),'v:val != "." && v:val != ".."')
endf

" move */* one level up, then remove first * matches
" if you don't want all dirs to be removed add them to keepdirs
" Example:
"
" A/activte/file.tar
" A/the-plugin/ftplugin/...
" A/the-plugin/autoload/...
" StripComponents(A, 1, "^activate")
" will yield strip the-plugin directory off.
"
" This emulatios tar --strip-components option (which is not present in 7z or
" unzip)
"
" If num==-1, then StripComponents will strip only if it finds that there is 
" only one directory that needs stripping
fun! vam#utils#StripComponents(dir, num, keepdirs)
  let num = a:num
  let strip_single_dir = 0
  if num == -1
    let num = 1
    let strip_single_dir = 1
  endif
  for i in range(0, num-1)
    let tomove = []
    let toremove = []
    " for each a:dir/*
    for gdir in filter(vam#utils#Glob(a:dir.'/*'),'isdirectory(v:val)')
      if index(a:keepdirs, gdir)!=-1 | continue | endif
      call add(toremove, gdir)
      if strip_single_dir && len(toremove)>=2
        return
      endif
      " for each gdir/*
      for path in vam#utils#Glob(gdir.'/*')
        " move out of dir
        call add(tomove, [path, a:dir.'/'.fnamemodify(path, ':t')])
      endfor
    endfor
    if strip_single_dir && !empty(toremove) && toremove[0]=~#'\v/%(autoload|colors|compiler|ftplugin|indent|keymap|lang|plugin|print|spell|syntax)$'
      return
    endif
    call map(tomove, 'rename(v:val[0], v:val[1])')
    call map(toremove, 'vam#utils#RmFR(v:val)')
  endfor
endf

" also copies 0. May throw an exception on failure
fun! vam#utils#CopyFile(a,b)
  let fc = readfile(a:a, 'b')
  if writefile(fc, a:b, 'b') != 0
    throw "copying file ".a:a." to ".a:b." failed"
  endif
endf

fun! vam#utils#Download(url, targetFile)
  if s:http_cmd is 0
    throw "Neither curl nor wget was found. Either set g:netrw_http_cmd or put one of them in PATH"
  endif
  " allow redirection because of sourceforge mirrors:
  call vam#utils#RunShell(s:http_cmd.' $p $', a:targetFile, a:url)
endf

fun! vam#utils#RmFR(dir_or_file)
  let cmd = ""
  if has('win32') || has('win64')
    if getftype(a:dir_or_file) == 'dir'
      let cmd = 'rmdir /S /Q'
    else
      let cmd = 'erase /F'
    endif
  elseif has('win16') || has('win95')
    " Dos-style COMMAND.COM. These are _UNTESTED_
    if getftype(a:dir_or_file) == 'dir'
      let cmd = 'deltree /Y'
    else
      let cmd = 'erase /F'
    endif
  else
    let cmd = "rm -fr"
  endif
  if empty(cmd)
    throw "Don't know how to recursively remove directory on ".g:os." system"
  else
    call vam#utils#RunShell(cmd.' $', a:dir_or_file)
  endif
endf


" a "direct link" (found on the download page)
" such as "http://downloads.sourceforge.net/project/gnuwin32/gzip/1.3.12-1/gzip-1.3.12-1-bin.zip"
" can be downloaded this way:
" call vam#utils#DownloadFromMirrors("mirror://sourceforge/gnuwin32/gzip/1.3.12-1/gzip-1.3.12-1-bin.zip","/tmp")
fun! vam#utils#DownloadFromMirrors(url, targetDir)
  let mirrors_sourceforge = [
        \   'http://heanet.dl.sourceforge.net/sourceforge/',
        \   'http://surfnet.dl.sourceforge.net/sourceforge/',
        \ ]

  let m = matchlist(a:url, '^mirror:\/\/\([^/\\]\+\)\/\(.*\)')

  if len(m) > 3
    let url =  mirrors_{m[1]}[0].m[2]
  endif
  " if target is a directory append basename of url
  let t = a:targetDir
  if isdirectory(t)
    let t = t .'/'.fnamemodify(url,':t')
  endif
  call vam#utils#Download(url, t)
endf


let s:tmpDir = ""
" this is not cleaned up on shutdown yet !
" tmpname():
" on windows C:\Users\NAME\AppData\Local\Temp\VIG3DB6.tmp
" on linux /tmp/v106312/111
"
" on linux this returns /tmp/a:name
" on windows it returns C:\Users\NAME\AppData\Local\Temp/a:name
fun! vam#utils#TempDir(name)
  if s:tmpDir == ""
    let s:tmpDir = fnamemodify(tempname(), ":h".(g:is_win ? '': ':h'))
  endif
  " expand make \ out of / on Windows
  return expand(s:tmpDir.'/'.a:name)
endf

" tries finding a new name if a plugin was renamed.
" Also tries to provide suggestions if you made trivial typos (case,
" forgetting _ special characters and such)
fun! vam#utils#TypoFix(name)
   return substitute(tolower(a:name), '[_/\-]*', '', 'g')
endf


"{{{1 Completion
" sample usage:
" inoremap <buffer> <expr> \start_completion vam#utils#CompleteWith("vam#install#CompleteAddonName")'
let s:savedomnifuncs={}
fun! vam#utils#CompleteWith(fun)
  if &l:omnifunc isnot# a:fun
    let s:savedomnifuncs[bufnr('%')]=&l:omnifunc
    call s:SetRestoringOmnifuncAutocommands()
    let &l:omnifunc=a:fun
  endif
  return "\<C-x>\<C-o>"
endfun

" Restore &omnifunc when different events are launched
fun! s:SetRestoringOmnifuncAutocommands()
  let buf=bufnr('%')
  let restoreofcode='if has_key(s:savedomnifuncs, '.buf.') | '.
        \               'let &l:omnifunc=remove(s:savedomnifuncs, '.buf.') | '.
        \           'endif'
  let restoreofifnotpumvisible='if !pumvisible() | '.restoreofcode.' | endif'
  augroup VAM_restore_completion
    if exists('##InsertCharPre')
      execute 'autocmd! InsertCharPre <buffer> '.restoreofifnotpumvisible
    else
      execute 'autocmd! CursorHoldI   <buffer> '.restoreofifnotpumvisible
    endif
    execute 'autocmd! InsertLeave <buffer> '.restoreofcode
  augroup END
endfun
"}}}1

" vim: et ts=8 sts=2 sw=2
