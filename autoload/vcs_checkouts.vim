" eventually this code will be moved into its own plugin in the future. Cause
" its very short probably VAM will keep a copy

exec vam#DefineAndBind('s:c','g:vim_addon_manager','{}')
let s:c.shallow_clones = get(s:c,'shallow_clones', executable('git') && system('git clone --help') =~ '--depth')
let s:c.scm_extra_args = get(s:c,'scm_extra_args',{})

let s:se = s:c.scm_extra_args
" this is not proberly quoted yet thus its will change:
" using list so that we can encode ['$ $',[1,2]] (quoting values if needed)
let s:se.git = get(s:c,'git', [s:c.shallow_clones ? '--depth 1' : ''])

" What's important about these configurations ?
"
" s:*_checkout are called with (repository, targetDir)
" s:*_update are called with (repository, vcs_directory)
"
" Thus you can overwrite them and implement whatever behaviour you like.
" The default implemenation should be close to what users expect from the VCS
" being used. However if you prefer mercurial overriding git_checkout is the
" way to make mercurial checkout git repos instead (like ZyX ? :)
"
" Later we can even add additional implementations telling user that upstream
" has changed etc .. (TODO)
let s:c.git_checkout = get(s:c, 'git_checkout', { 'f': 'vam#utils#RunShell', 'a': ['git clone '.s:se.git[0].' $.url $p'] })
let s:c.hg_checkout = get(s:c, 'hg_checkout', { 'f': 'vam#utils#RunShell', 'a': ['hg clone $.url $p']})
let s:c.bzr_checkout = get(s:c, 'bzr_checkout', { 'f': 'vam#utils#RunShell', 'a': ['bzr branch $.url $p']})
let s:c.svn_checkout = get(s:c, 'svn_checkout', { 'f': 'vcs_checkouts#SVNCheckout', 'a': []})

" luckily "cd && cmd" works on both: win and linux ..
let s:c.git_update = get(s:c, 'git_update', { 'f': 'vam#utils#RunShell', 'a': ['cd $p && git pull'] })
let s:c.hg_update = get(s:c, 'hg_update', { 'f': 'vam#utils#RunShell', 'a': ['hg pull -u -R $p']})
let s:c.bzr_update = get(s:c, 'bzr_update', { 'f': 'vam#utils#RunShell', 'a': ['bzr pull -d $p']})
let s:c.svn_update = get(s:c, 'svn_update', { 'f': 'vam#utils#RunShell', 'a': ['cd $p && svn update']})

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
  let directory = a:dir
  let types = {'.git' : 'git', '.hg' : 'hg', '.svn': 'svn' }
  for [k, t] in items(types)
    if isdirectory(directory.'/'.k) | let type = t | break | endif
  endfor

  if !exists('type')
    " not knowing how to update a repo is not a failure
    return 0
  endif

  let c = s:c[type . '_update']
  call call(c.f, c.a + [directory])

  if v:shell_error
    throw "Updating ".a:dir." falied. Got exit code: ".v:shell_error
  endif
  return 1
endf

" repository = {'type': git|hg|svn|bzr, 'url': .. }
fun! vcs_checkouts#Checkout(targetDir, repository)
  if a:repository.type =~ '^\%(git\|hg\|bzr\|svn\)$'
    let c = s:c[(a:repository.type) . '_checkout']
    call call(c.f, c.a + [a:repository, a:targetDir])
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
