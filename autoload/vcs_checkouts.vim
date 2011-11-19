" eventually this code will be moved into its own plugin in the future. Cause
" its very short probably VAM will keep a copy

exec vam#DefineAndBind('s:c','g:vim_addon_manager','{}')
let s:c.shallow_clones = get(s:c,'shallow_clones', executable('git') && system('git clone --help') =~ '--depth')
let s:c.scm_extra_args = get(s:c,'scm_extra_args',{'git': [(s:c.shallow_clones ? '--depth 1': '')]})
let s:c.scms_support = get(s:c, 'scms_support', 'auto')
let s:se = s:c.scm_extra_args
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
let s:scm_defaults={
      \'git': {'clone': ['vam#utils#RunShell', ['git clone $.url $p' ]],
      \       'update': ['vam#utils#RunShell', ['cd $p && git pull'  ]],},
      \ 'hg': {'clone': ['vam#utils#RunShell', ['hg clone $.url $p'  ]],
      \       'update': ['vam#utils#RunShell', ['hg pull -u -R $p'   ]],},
      \'bzr': {'clone': ['vam#utils#RunShell', ['bzr branch $.url $p']],
      \       'update': ['vam#utils#RunShell', ['bzr pull -d $p'     ]],},
      \'svn': {'clone': ['vcs_checkouts#SVNCheckout', []],
      \       'update': ['vam#utils#RunShell', ['svn update $p'      ]],},
    \}
if executable('git') && stridx(system('git clone --help'), '--depth')!=-1
  let s:scm_defaults.git.clone[1][0]='git clone --depth 1 $.url $p'
endif
for [s:scm, s:val] in items(s:scm_defaults)
  if has_key(s:c.scms, s:scm)
    call extend(s:c.scms[s:scm], s:val, 'keep')
  else
    let s:c.scms[s:scm]=s:val
  endif
  let s:c.scms[s:scm].dir='.'.s:scm
endfor
unlet s:scm s:val
call map(copy(s:c.scms), 'extend(v:val, {"executable": v:key}, "keep")')

fun! vcs_checkouts#SetSCMSupport()
  if s:c.scms_support is# 'auto'
    for [scm, sdescr] in items(s:c.scms)
      let s:c[scm.'_support']=executable(sdescr.executable)
    endfor
  elseif s:c.scms_support is# 'no' || s:c.scms_support is# 'all'
    let supportvalue=(s:c.scms_support is# 'all')
    for scm in keys(s:c.scms)
      let s:c[scm.'_support']=supportvalue
    endfor
  elseif type(s:c.scms_support)==type({})
    for [scm, val] in items(s:c.scms_support)
      let s:c[scm.'_support']=val
    endfor
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
