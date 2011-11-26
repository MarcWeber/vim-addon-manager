" eventually this code will be moved into its own plugin in the future. Cause
" its very short probably VAM will keep a copy

exec vam#DefineAndBind('s:c','g:vim_addon_manager','{}')
let s:c.scms = get(s:c, 'scms', {})

" What's important about these configurations ?
"
" s:c.scms.{scm}.clone are called with additional (repository, targetDir),
"                      absense of targetDir indicates failure
" s:c.scms.{scm}.update are called with additional (repository), non-zero return
"                       value indicates failure
"
" Both should contain list that looks like if you are going to do the job using 
" `call call("call", s:scms.{scm}.{key})'.
"
" You can explicitely set executable location using
"
" Thus you can overwrite them and implement whatever behaviour you like.
" The default implemenation should be close to what users expect from the VCS
" being used. However if you prefer mercurial overriding git_checkout is the
" way to make mercurial checkout git repos instead (like ZyX ? :)
"
" Later we can even add additional implementations telling user that upstream
" has changed etc .. (TODO)
let s:git_checkout='git clone $.url $p'
if executable('git') && stridx(system('git clone --help'), '--depth')!=-1
  let s:git_checkout='git clone --depth 1 $.url $p'
endif
let s:scm_defaults={
      \'git': {'clone': ['vam#utils#RunShell', [s:git_checkout       ]],
      \       'update': ['vam#utils#RunShell', ['cd $p && git pull'  ]],},
      \ 'hg': {'clone': ['vam#utils#RunShell', ['hg clone $.url $p'  ]],
      \       'update': ['vam#utils#RunShell', ['hg pull -u -R $p'   ]],},
      \'bzr': {'clone': ['vam#utils#RunShell', ['bzr branch $.url $p']],
      \       'update': ['vam#utils#RunShell', ['bzr pull -d $p'     ]],},
      \'svn': {'clone': ['vcs_checkouts#SVNCheckout', []],
      \       'update': ['vam#utils#RunShell', ['svn update $p'      ]],},
      \'_bundle': {'update': ['vcs_checkouts#UpdateBundle', []],},
    \}
let s:c.scms=get(s:c, 'scms', {})
call map(filter(copy(s:c.scms), 'has_key(s:scm_defaults, v:key)'), 'extend(v:val, s:scm_defaults[v:key], "keep")')
call extend(s:c.scms, s:scm_defaults, 'keep')
call map(copy(s:c.scms), 'extend(v:val, {"dir": ".".v:key})')

fun! vcs_checkouts#GetBundle(repository, targetDir)
  let [dummystr, protocol, user, domain, port, path; dummylst]=
              \matchlist(a:repository, '\v^%(([^:]+)\:\/\/)?'.
              \                           '%(([^@/:]+)\@)?'.
              \                            '([^/:]*)'.
              \                           '%(\:(\d+))?'.
              \                            '(.*)$')
  if domain is? 'github.com'
    let url="https://".domain."/".'.s:ghpath.'."/zipball/master"
    let archive='master.zip'
  elseif domain is? 'bitbucket.org'
    let url="https://".domain.path."/get/default.zip"
    let archive='default.zip'
  elseif domain is? 'git.devnull.li'
    let url="http://".domain.path."/snapshot/master.tar.gz"
    let archive='master.tar.gz'
  else
    throw 'Don’t know how to get bundle from '.domain
  endif
  call vam#install#Checkout(a:targetDir, {'type': 'archive', 'url': url, 'archive': archive})
  call mkdir(a:targetDir.'/._bundle')
  call writefile([url, archive], a:targetDir.'/._bundle/opts', 'b')
endfun

fun! vcs_checkouts#UpdateBundle(targetDir)
  let [url, archive]=readfile(a:targetDir.'/._bundle/url', 'b')
  call vam#utils#RmFR(a:targetDir)
  call vam#install#Checkout(a:targetDir, {'type': 'archive', 'url': url, 'archive': archive})
endfun

fun! s:TryCmd(...)
  try
    call call('vam#utils#RunShell', a:000)
    return 1
  catch
    return 0
  endtry
endfun

fun! vcs_checkouts#GitCheckout(repository, targetDir)
  if executable('git')
    call vam#utils#RunShell(s:git_checkout, a:repository, a:targetDir)
  elseif executable('hg') && s:TryCmd('hg clone $.url $p', a:repository, a:targetDir)
    return
  else
    call vcs_checkouts#GetBundle(a:repository, a:targetDir)
  endif
endfun

fun! vcs_checkouts#MercurialCheckout(repository, targetDir)
  if executable('hg')
    call vam#utils#RunShell('hg clone $.url $p', a:repository, a:targetDir)
  else
    call vcs_checkouts#GetBundle(a:repository, a:targetDir)
  endif
endfun

fun! vcs_checkouts#SubversionCheckout(repository, targetDir)
  if executable('svn')
    call vcs_checkouts#SVNCheckout(a:repository, a:targetDir)
  elseif executable('hg') && s:TryCmd('hg clone $.url $p', a:repository, a:targetDir)
    return
  elseif executable('bzr') && s:TryCmd('bzr branch $.url $p', a:repository, a:targetDir)
    return
  endif
endfun

fun! vcs_checkouts#SVNCheckout(repository, targetDir)
  let args=['svn checkout $.url $3p', a:repository, a:repository.url, a:targetDir]
  for key in filter(['username', 'password'], 'has_key(a:repository, v:val)')
    let args[0].=' --'.key.' $'
    let args+=[a:repository[key]]
  endfor
  call call('vam#utils#RunShell', args)
endfun

" this may be useful for other projects.
" Thus move checking .hg .svn etc into a different file

fun! vcs_checkouts#Update(dir)
  for [scm, sdescr] in items(s:c.scms)
    if isdirectory(a:dir.'/'.(sdescr.dir))
      break
    endif
    unlet sdescr
  endfor

  if !exists('sdescr')
    return 0
  endif

  let c=sdescr.update
  if call(c[0], c[1] + [a:dir], get(c, 2, {}))
    throw 'Updating '.a:dir.' failed'
  endif

  return 1
endf

" repository = {'type': git|hg|svn|bzr, 'url': .. }
fun! vcs_checkouts#Checkout(targetDir, repository)
  if has_key(s:c.scms, a:repository.type)
    let c=s:c.scms[a:repository.type].clone
    call call(c[0], c[1]+[a:repository, a:targetDir], get(c, 2, {}))
  else
    " Keep old behavior: no throw for unknown repository type
    return
  endif
  if !isdirectory(a:targetDir)
    throw "Failure. Plugin directory ".a:targetDir." should have been created but does not exist !"
  endif
endf

let s:exec_in_dir=function('vam#utils#ExecInDir')

" vim: et ts=8 sts=2 sw=2
