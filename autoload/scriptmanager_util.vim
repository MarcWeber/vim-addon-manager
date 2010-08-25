" let users override curl command. Reuse netrw setting
let s:curl = exists('g:netrw_http_cmd') ? g:netrw_http_cmd : 'curl -o'

" cmds = list of {'d':  dir to run command in, 'c': the command line to be run }
fun! s:exec_in_dir(cmds)
  call vcs_checkouts#ExecIndir(a:cmds)
endf

" insert arguments at placeholders $ shell escaping the value
" usage: s:shellescape("rm -fr $ $ $", [file1, file2, file3])
fun! s:shellescape(cmd, ...)
  let list = copy(a:000)
  let r = ''
  let l = split(a:cmd, '\$', 1)
  let r = l[0]
  for x in l[1:]
    let r .= shellescape(remove(list, 0),1).x
  endfor
  return r
endf

" may throw EXCEPTION_UNPACK.*
" most packages are shipped in a directory. Eg ADDON/plugin/*
" strip_components=1 strips of this ADDON directory (implemented for tar.* " archives only)

" !! If you change this run the test, please: call vim_addon_manager_tests#Tests('.')
fun! scriptmanager_util#Unpack(archive, targetdir, strip_components)
  let filestoremove=fileutils#Unpack(a:archive, a:targetdir)
  if type(filestoremove) != type([])
    throw "EXCEPTION_UNPACK failed to unpack plugin"
  endif
  call map(filestoremove, 'fileutils#Rm(v:val)')
  if a:strip_components
    call fileutils#StripComponents(a:targetdir, a:strip_components+1, a:targetdir)
  endif
endf

" a "direct link" (found on the downrload page)
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
  call fileutils#Get(url, t)
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
