" let users override curl command. Reuse netrw setting
let s:curl = exists('g:netrw_http_cmd') ? g:netrw_http_cmd : 'curl -o'

" cmds = list of {'d':  dir to run command in, 'c': the command line to be run }
fun! s:exec_in_dir(cmds)
  call vcs_checkouts#ExecIndir(a:cmds)
endf

" insert arguments at placeholders $ shell escaping the value
" usage: s:shellescape("rm --arg $ -fr $p $p $p", [string, file1, file2, file3])
"
" the / \ annoyance of Windows is fixed by calling expand which replaces / by
" \ on Windows. This only happens by the $p substitution
fun! s:shellescape(cmd, ...)
  let list = copy(a:000)
  let r = ''
  let l = split(a:cmd, '\$', 1)
  let r = l[0]
  for x in l[1:]
    let i = remove(list, 0)
    if x[0] == 'p'
      let x = x[1:]
      let i = expand(i)
    endif
    let r .= shellescape(i,1).x
  endfor
  return r
endf

" TODO improve this and move somewhere else?
fun! scriptmanager_util#ShellDSL(...)
  return call('s:shellescape', a:000)
endf

"Usages: EndsWith('name.tar',   '.tar', '.txt') returns 1 even if .tar was .txt
fun! s:EndsWith(name, ...)
  return  a:name =~? '\%('.substitute(join(a:000,'\|'),'\.','\\.','g').'\)$'
endf

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
fun! scriptmanager_util#Unpack(archive, targetdir, ...)
  let opts = a:0 > 0 ? a:1 : {}
  let strip_components = get(opts, 'strip-components', -1)
  let delSource = get(opts, 'del-source', 0)

  let esc_archive = s:shellescape('$', a:archive)
  let tgt = [{'d': a:targetdir}]

  if strip_components > 0 || strip_components == -1
    " when stripping don' strip which was there before unpacking
    let keep = scriptmanager_util#Glob(a:targetdir.'/*')
    let strip = 'call scriptmanager_util#StripComponents(a:targetdir, strip_components, keep)'
  else
    let strip = ''
  endif

  " [ ending, chars to strip, chars to add, command to do the unpacking ]
  let gzbzip2 = {
        \ '.gz':   [-4, '','gzip -d'],
        \ '.tgz':   [-3,'ar','gzip -d'],
        \ '.bz2':   [-5, '', 'bzip2 -d'],
        \ '.tbz2':  [-4,'ar','bzip2 -d'],
        \ }

  " .vim file and type syntax?
  if a:archive =~? '\.vim$'
    call writefile(readfile(a:archive,'b'), a:targetdir.'/'.fnamemodify(a:archive, ':t'),'b')

  " .gz .bzip2 (or .vba.* or .tar.*)
  elseif s:EndsWith(a:archive, keys(gzbzip2) )
    " I was told tar on Windows is buggy and can't handle xj or xz correctly
    " so unpack in two phases:

    for [k,z] in items(gzbzip2)
      if s:EndsWith(a:archive, k)
        " without ext
        let unpacked = a:archive[:z[0]]
        " correct ext
        let renameTo = unpacked.z[1]

        " PHASE (1): gunzip or bunzip using gzip,bzip2 or 7z:
        if executable('7z') && !exists('g:prefer_tar')
          echoe "using 7z"
          " defaulting to 7z why or why not?
          call s:exec_in_dir([{'d': fnamemodify(a:archive, ':h'), 'c': '7z x '.esc_archive }])
          " 7z renames tgz to tar
        else
          " make a backup. gunzip etc rm the original file
          if !delSource
            let b = a:archive.'.bak'
            call scriptmanager_util#CopyFile(a:archive, b)
          endif

          " unpack
          call s:exec_in_dir([{'c': z[2].' '.esc_archive }])

          " copy backup back:
          if !delSource | call rename(b, a:archive) | endif
        endif

        if !filereadable(renameTo)
          " windows tar does not rename .tgz to .tar ?
          call rename(unpacked, renameTo)
        endif

        " PHASE (2): now unpack .tar or .vba file and tidy up temp file:
        call scriptmanager_util#Unpack(renameTo, a:targetdir, { 'strip-components': strip_components, 'del-source': 1 })
        call delete(renameTo)
        break
      endif
      unlet k z
    endfor

    " execute in target dir:

    " .tar
  elseif s:EndsWith(a:archive, '.tar')
    if executable('7z')
      call s:exec_in_dir(tgt + [{'c': '7z x '.esc_archive }])
    else
      call s:exec_in_dir(tgt + [{'c': 'tar -xf '.esc_archive }])
    endif
    exec strip

    " .zip
  elseif s:EndsWith(a:archive, '.zip')
    if executable('7z')
      call s:exec_in_dir(tgt + [{'c': '7z x '.esc_archive }])
    else
      call s:exec_in_dir(tgt + [{'c': 'unzip '.esc_archive }])
    endif
    exec strip

    " .7z, .cab, .rar, .arj, .jar
    " (I have actually seen only .7z and .rar, but 7z supports other formats 
    " too)
  elseif s:EndsWith(a:archive,  '.7z','.cab','.arj','.rar','.jar')
    call s:exec_in_dir(tgt + [{'c': '7z x '.esc_archive }])
    exec strip

  elseif s:EndsWith(a:archive, '.vba')
    " .vba reuse vimball#Vimball() function
    exec 'sp '.fnameescape(a:archive)
    call vimball#Vimball(1,a:targetdir)
    " wipe out buffer
    bw!
  else
    throw "EXCEPTION_UNPACK: don't know how to unpack ". a:archive
  endif

  if delSource && !filereadable(a:archive)
    call delete(a:archive)
  endif

endf

" Usage: Glob($HOME.'/*') will list hidden files as well
fun! scriptmanager_util#Glob(path)
  return split(glob(a:path),"\n")
  + filter(split(glob(substitute(a:path,'\*','.*','g')),"\n"),'v:val != "." && v:val != ".."')
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
fun! scriptmanager_util#StripComponents(dir, num, keepdirs)
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
    for gdir in filter(scriptmanager_util#Glob(a:dir.'/*'),'isdirectory(v:val)')
      if index(a:keepdirs, gdir)!=-1 | continue | endif
      call add(toremove, gdir)
      if strip_single_dir && len(toremove)>=2
        return
      endif
      " for each gdir/*
      for path in scriptmanager_util#Glob(gdir.'/*')
        " move out of dir
        call add(tomove, [path, a:dir.'/'.fnamemodify(path, ':t')])
      endfor
    endfor
    call map(tomove, 'rename(v:val[0], v:val[1])')
    call map(toremove, 'scriptmanager_util#RmFR(v:val)')
  endfor
endf

" also copies 0. May throw an exception on failure
fun! scriptmanager_util#CopyFile(a,b)
  let fc = readfile(a:a, 'b')
  if writefile(fc, a:b, 'b') != 0
    throw "copying file ".a:a." to ".a:b." failed"
  endif
endf

fun! scriptmanager_util#Download(url, targetFile)
  " allow redirection because of sourceforge mirrors:

  let s:curl = exists('g:netrw_http_cmd') ? g:netrw_http_cmd : 'curl -o'
  " Let's hope that nobody is using a dir called "curl " .. because
  " substitution will be wrong then
  let c = substitute(s:curl, '\ccurl\(\.exe\)\?\%( \|$\)','curl\1 --location --max-redirs 40 ','')
  call s:exec_in_dir([{'c': s:shellescape(c.' $p $', a:targetFile, a:url)}])
endf

fun! scriptmanager_util#RmFR(dir_or_file)
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
  if cmd == ""
    throw "don't know how to RmFR on this system: ".g:os
  else
    exec '!'.s:shellescape(cmd.' $', a:dir_or_file)
  endif
endf


" Prepare a list of runtimepaths as stored in the addon package data
" for inclusion in &runtimepath.
fun! scriptmanager_util#EscapeRuntimePaths(paths)
  return map(copy(a:paths), 'substitute(v:val, '','', ''\\,'', ''g'')')
endf


" a "direct link" (found on the download page)
" such as "http://downloads.sourceforge.net/project/gnuwin32/gzip/1.3.12-1/gzip-1.3.12-1-bin.zip"
" can be downloaded this way:
" call scriptmanager_util#DownloadFromMirrors("mirror://sourceforge/gnuwin32/gzip/1.3.12-1/gzip-1.3.12-1-bin.zip","/tmp")
fun! scriptmanager_util#DownloadFromMirrors(url, targetDir)
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
  call scriptmanager_util#Download(url, t)
endf


let s:tmpDir = ""
" this is not cleaned up on shutdown yet !
" tmpname():
" on windows C:\Users\NAME\AppData\Local\Temp\VIG3DB6.tmp
" on linux /tmp/v106312/111
"
" on linux this returns /tmp/a:name
" on windows it returns C:\Users\NAME\AppData\Local\Temp/a:name
fun! scriptmanager_util#TempDir(name)
  if s:tmpDir == ""
    let s:tmpDir = fnamemodify(tempname(), ":h".(g:is_win ? '': ':h'))
  endif
  " expand make \ out of / on Windows
  return expand(s:tmpDir.'/'.a:name)
endf
