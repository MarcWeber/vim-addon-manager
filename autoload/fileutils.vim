
" let users override curl command. Reuse netrw setting
let  s:curl = split(exists('g:netrw_http_cmd') ? g:netrw_http_cmd : 'curl -o')
let  s:gzip = 'gzip'
let s:bzip2 = 'bzip2'
let    s:xz = 'xz'
let  s:lzma = 'lzma'
let   s:p7z = '7z'
let   s:tar = 'tar'
let s:unzip = 'unzip'
let s:unrar = 'unrar'
let s:is_win = has('win16') || has('win32') || has('win64') || has('win95')
let s:prefer7z = s:is_win

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
    function! fileutils#GetMIME(file)
        return "application/octet-stream"
    endfunction
    function! fileutils#Joinpath(...)
        return expand(join(a:000, "/"))
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
    function! fileutils#GetMIME(file)
        return substitute(system("file --mime-type --brief ".s:shellescape(a:file)),
                    \     '\_s', '', 'g')
    endfunction
    function! fileutils#Joinpath(...)
        return join(a:000, "/")
    endfunction
endif
function! fileutils#Mv(file, destination)
    if getftype(a:file)=="dir"
        return fileutils#Execute([s:mv+[a:file, a:destination]])
    else
        if getftype(a:destination)=="dir"
            let destination=fileutils#Joinpath(a:destination, fnamemodify(a:file, ":t"))
        else
            let destination=a:destination
        endif
        return !rename(a:file, destination)
    endif
endfunction
function! fileutils#Rm(what)
    if getftype(a:what)=="dir"
        call fileutils#Execute([s:deltree+[a:what]])
    else
        call delete(a:what)
    endif
    return 1
endfunction

function! fileutils#Get(url, target)
    let targetdirectory=fnamemodify(a:target, ':h')
    let targetfile=fnamemodify(a:target, ':t')
    call fileutils#Execute([s:curl+[targetfile, a:url]], targetdirectory)
    return !v:shell_error
endfunction

" All functions return list of files that should be deleted on success
let s:UnpackFunctions={}

if !s:prefer7z
    function! s:Unzip(program, archive, destination)
        let adir=fnamemodify(a:archive, ':p:h')
        let afile=fnamemodify(a:archive, ':t')
        let suf=fnamemodify(a:archive, ':t:e')
        if !empty(suf)
            let suf=".".suf
        endif
        let r=[]
        if fileutils#Execute([[a:program, '-d', afile]], adir)
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
    if fileutils#Execute([[s:p7z, "x", afile]], a:destination)
        return [a:archive]
    endif
endfunction
let s:UnpackFunctions["application/x-7z"]=function("s:Un7zip")
let s:UnpackFunctions["application/x-compressed"]=function("s:Un7zip")

for s:a in ['gzip', 'bzip2', 'xz', 'lzma']
    if s:prefer7z
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

if s:prefer7z
    let s:UnpackFunctions["application/x-tar"]=function("s:Un7zip")
    let s:UnpackFunctions["application/zip"]  =function("s:Un7zip")
    let s:UnpackFunctions["application/x-rar"]=function("s:Un7zip")
else
    let s:unpackcommands={
                \"application/x-tar": "s:tar,'-xf'",
                \"application/zip":   "s:unzip",
                \"application/x-rar": "s:unrar,'x'",
            \}
    for [s:m, s:c] in items(s:unpackcommands)
        execute "function! s:UnpackFunctions.last(archive, destination)\n".
                    \"let archive=fnamemodify(a:archive, ':p')\n".
                    \"if fileutils#Execute([[".s:c.",archive]], a:destination)\n".
                    \"    return [archive]\n".
                    \"endif\n".
                    \"endfunction"
        let s:UnpackFunctions[s:m]=s:UnpackFunctions.last
        unlet s:UnpackFunctions.last
    endfor
    unlet s:m s:c
endif
let s:UnpackFunctions["application/x-exe"]=function("s:Un7zip")
let s:UnpackFunctions["application/java-archive"]=function("s:Un7zip")
let s:UnpackFunctions["application/vnd.ms-cab-compressed"]=function("s:Un7zip")

function! s:UnpackFunctions.vimball(archive, destination)
    execute "view ".fnameescape(a:archive)
    call vimball#Vimball(1, a:destination)
    bwipeout
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
    let mime=fileutils#GetMIME(a:archive)
    if !has_key(s:UnpackFunctions, mime)
        let mime="application/octet-stream"
    endif
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
