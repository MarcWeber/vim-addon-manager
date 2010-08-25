let s:is_win = has('win16') || has('win32') || has('win64') || has('win95')
if s:is_win
    function! fileutils#Joinpath(...)
        return join(map(copy(a:000), 'substitute(v:val, "/", ''\\'', "g")'), '\')
    endfunction
else
    function! fileutils#Joinpath(...)
        return join(a:000, "/")
    endfunction
endif
function! s:getoption(option, default)
    if exists('g:fileutilsOptions') && type(g:fileutilsOptions)==type({})
        let option=get(g:fileutilsOptions, a:option, a:default)
        if option is a:default
            return option
        elseif type(option)!=type(a:default)
            if type(a:default)==type([]) && type(option)==type("")
                return [option]
            endif
            return a:default
        elseif type(a:default)==type([])
            let option=filter(copy(option), 'type(v:val)=='.type(""))
            if empty(option)
                return a:default
            endif
        endif
        return option
    endif
    return a:default
endfunction
" let users override curl command. Reuse netrw setting
let  s:curl = split(exists('g:netrw_http_cmd') ? g:netrw_http_cmd : 'curl -o')
if s:curl[0]==#"curl"
    call extend(s:curl, ['--location', '--max-redirs', 40], 1)
endif
let s:curl=s:getoption('curl', s:curl)
let s:cmddir=s:getoption("cmddir", "")
if !empty(s:cmddir)
    let s:cmddir=fileutils#Joinpath(s:cmddir, "")
endif
for s:a in ["gzip", "bzip2", "xz", "lzma"]
    let s:{s:a}=s:getoption(s:a, [s:cmddir.s:a, '-d'])
endfor
let   s:tar = s:getoption('tar', ['tar', '-xf'])
let   s:p7z = s:getoption('7z', ['7z', 'x'])
let s:unzip = s:getoption('unzip', ['unzip'])
let s:unrar = s:getoption('unrar', [((executable("unrar"))?('unrar'):('rar')), 'x'])
let s:prefer7z = s:getoption('prefer7z', 0)

function! s:shellescape(s)
    return shellescape(a:s, 1)
endfunction

if s:is_win
    if has("win32") || has("win64")
        let s:deltree=["rmdir", "/S", "/Q"]
    else
        let s:deltree=["deltree", "/Y"]
    endif
    let s:mv=["move"]
    function! fileutils#Execute(commands, ...)
        if !empty(a:000)
            new
            execute "lcd ".fnameescape(a:000[0])
        endif
        for c in a:commands
            silent execute '!'.join(map(copy(c), 's:shellescape(v:val)'))
            if !v:shell_error
                break
            endif
        endfor
        if !empty(a:000)
            bw!
        endif
        redraw!
        return !v:shell_error
    endfunction
else
    let s:deltree=["rm", "-rf"]
    let s:mv=["mv"]
    function! fileutils#Execute(commands, ...)
        let cmd=""
        if !empty(a:000)
            let cmd.="cd ".s:shellescape(a:000[0]).' && '
        endif
        let cmd.=join(map(deepcopy(a:commands),
                    \'join(map(v:val, "s:shellescape(v:val)"))'), ' && ')
        silent execute '!'.cmd
        redraw!
        return !v:shell_error
    endfunction
endif
function! fileutils#Mv(file, destination)
    if fnamemodify(a:file, ':p'.((isdirectory(a:destination))?(':h'):('')))==#fnamemodify(a:destination, ':p')
        return 1
    endif
    if isdirectory(a:file)
        return fileutils#Execute([s:mv+[a:file, a:destination]])
    else
        if isdirectory(a:destination)
            let destination=fileutils#Joinpath(a:destination, fnamemodify(a:file, ":t"))
        else
            let destination=a:destination
        endif
        return !rename(a:file, destination)
    endif
endfunction
function! fileutils#Rm(what)
    if isdirectory(a:what)
        call fileutils#Execute([s:deltree+[a:what]])
    else
        call delete(a:what)
    endif
    return 1
endfunction
function! fileutils#GetDirContents(directory)
    let files=split(
                \glob(
                \   substitute(
                \       escape(
                \           fileutils#Joinpath(a:directory, "*"),
                \           '[]?`\'),
                \   '\ze\*.', '\\', 'g')),
                \"\n", 1)
    if files==#[""]
        return []
    elseif s:is_win
        return files
    endif
    let r=[fileutils#Joinpath(a:directory, "")]
    while !empty(files)
        let curfile=remove(files, 0)
        while (!(filereadable(curfile) || isdirectory(curfile)) || index(r, curfile)!=-1) && !empty(files)
            let curfile.="\n".remove(files, 0)
        endwhile
        call add(r, curfile)
    endwhile
    call remove(r, 0)
    return r
endfunction
function! fileutils#ListMovedFiles(source, number)
    let files=fileutils#GetDirContents(a:source)
    if a:number==1
        return [[], files]
    endif
    let dirs=filter(copy(files), 'isdirectory(v:val)')
    call filter(files, 'filereadable(v:val)') " Filter out directories and unreadable files
    call map(copy(dirs), 'extend(files, fileutils#ListMovedFiles(v:val, a:number-1)[1])')
    return [dirs, files]
endfunction
function! fileutils#StripComponents(source, number, destination, ...)
    let [toremove, tomove]=fileutils#ListMovedFiles(a:source, a:number)
    if get(a:000, 0) && len(toremove)>1
        return 0
    endif
    call map(tomove, 'fileutils#Mv(v:val, a:destination)')
    call map(toremove, 'fileutils#Rm(v:val)')
    return index(tomove+toremove, 0)==-1
endfunction

function! fileutils#Get(url, target)
    let targetdirectory=fnamemodify(a:target, ':h')
    let targetfile=fnamemodify(a:target, ':t')
    return fileutils#Execute([s:curl+[targetfile, a:url]], targetdirectory)
endfunction

" All functions return list of files that should be deleted on success
let s:UnpackFunctions={}

if !s:prefer7z
    function! s:Unzip(cmd, archive, destination)
        let adir=fnamemodify(a:archive, ':p:h')
        let afile=fnamemodify(a:archive, ':t')
        let suf=fnamemodify(a:archive, ':t:e')
        if !empty(suf)
            let suf=".".suf
        endif
        let r=[]
        if fileutils#Execute([a:cmd+[afile]], adir)
            let destination=fnamemodify(a:destination, ':p')
            if destination!=#adir
                let ufile=fileutils#Joinpath(adir, fnamemodify(a:archive, ":t:r"))
                if !filereadable(ufile)
                    let ufile.=".tar"
                endif
                if !filereadable(ufile) || !fileutils#Mv(ufile, destination)
                    return
                endif
            endif
            return []
        endif
    endfunction
endif

function! s:Un7zip(archive, destination)
    let afile=fnamemodify(a:archive, ':p')
    let r=[]
    if fileutils#Execute([s:p7z+[afile]], a:destination)
        return [a:archive]
    endif
endfunction
let s:UnpackFunctions["application/x-7z"]=function("s:Un7zip")
let s:UnpackFunctions["application/x-compressed"]=function("s:Un7zip")

for s:a in ['gzip', 'bzip2', 'xz', 'lzma']
    if s:prefer7z || !executable(s:{s:a}[0])
        let s:UnpackFunctions["application/x-".s:a]=function("s:Un7zip")
    else
        execute "function! s:UnpackFunctions.last(archive, destination)\n".
                    \"return s:Unzip(s:".s:a.", a:archive, a:destination)\n"
                    \"endfunction"
        let s:UnpackFunctions['application/x-'.s:a]=s:UnpackFunctions.last
        unlet s:UnpackFunctions.last
    endif
endfor
unlet s:a

let s:unpackcommands={
            \"application/tar": s:tar,
            \"application/zip":   s:unzip,
            \"application/x-rar": s:unrar,
        \}
for [s:m, s:c] in items(s:unpackcommands)
    if s:prefer7z || !executable(s:c[0])
        let s:UnpackFunctions[s:m]=function("s:Un7zip")
    else
        execute "function! s:UnpackFunctions.last(archive, destination)\n".
                    \"let archive=fnamemodify(a:archive, ':p')\n".
                    \"if fileutils#Execute([".string(s:c)."+[archive]], a:destination)\n".
                    \"    return [archive]\n".
                    \"endif\n".
                    \"endfunction"
        let s:UnpackFunctions[s:m]=s:UnpackFunctions.last
        unlet s:UnpackFunctions.last
    endif
endfor
unlet s:m s:c
let s:UnpackFunctions["application/x-exe"]=function("s:Un7zip")
let s:UnpackFunctions["application/java-archive"]=function("s:Un7zip")
let s:UnpackFunctions["application/vnd.ms-cab-compressed"]=function("s:Un7zip")
let s:UnpackFunctions["application/arj"]=function("s:Un7zip")

function! s:UnpackFunctions.vimball(archive, destination)
    execute "view ".fnameescape(a:archive)
    call vimball#Vimball(1, a:destination)
    bwipeout
    return [a:archive]
endfunction
let s:UnpackFunctions['application/x-vimball']=s:UnpackFunctions.vimball
unlet s:UnpackFunctions.vimball

let s:mimeext={
            \"gz":   "application/x-gzip",
            \"tgz":  "application/x-gzip",
            \"bz2":  "application/x-bzip2",
            \"tbz2": "application/x-bzip2",
            \"xz":   "application/x-xz",
            \"txz":  "application/x-xz",
            \"lzma": "application/x-lzma",
            \"zip":  "application/zip",
            \"7z":   "application/x-7z",
            \"tar":  "application/tar",
            \"rar":  "application/x-rar",
            \"vba":  "application/x-vimball",
            \"exe":  "application/x-exe",
            \"jar":  "application/java-archive",
            \"arj":  "application/arj",
        \}
" If no MIME type is present, try to guess what is it based on extension
function! s:UnpackFunctions.octetstream(archive, destination)
    let ext=tolower(fnamemodify(a:archive, ':t:e'))
    if has_key(s:mimeext, ext)
        return s:UnpackFunctions[s:mimeext[ext]](a:archive, a:destination)
    else
        " Fallback to 7zip. Maybe it will be able to open it
        return s:Un7zip(a:archive, a:destination)
    endif
endfunction
let s:UnpackFunctions['application/octet-stream']=s:UnpackFunctions.octetstream
unlet s:UnpackFunctions.octetstream

let s:alternates={
            \"application/x-7z": ["application/x-7z-compressed",
            \                     "application/x-7zip",
            \                     "application/x-7zip-compressed"],
            \"application/x-gzip": ["application/x-gzip-compressed"],
            \"application/x-rar": ["application/x-rar-compressed"],
            \"application/vnd.ms-cab-compressed": ["application/cab"],
        \}

for [s:m, s:al] in items(s:alternates)
    for s:a in s:al
        let s:UnpackFunctions[s:a]=s:UnpackFunctions[s:m]
    endfor
endfor
unlet s:m s:al s:a

function! fileutils#Unpack(archive, destination)
    let mime="application/octet-stream"
    let r=s:UnpackFunctions[mime](a:archive, a:destination)
    if type(r)==type([])
        let newarchive=fileutils#Joinpath(a:destination, fnamemodify(a:archive, ":t:r"))
        if !filereadable(newarchive)
            let newarchive.=".tar"
        endif
        if !filereadable(newarchive) || newarchive==#a:archive
            return r
        endif
        let r2=fileutils#Unpack(newarchive, a:destination)
        if type(r2)==type([])
            return r+r2
        endif
        return r
    else
        if fileutils#Mv(a:archive, a:destination)
            return []
        endif
    endif
endfunction
