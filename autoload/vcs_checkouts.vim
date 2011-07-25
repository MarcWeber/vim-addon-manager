exec vam#DefineAndBind('s:c','g:vim_addon_manager','{}')
let s:c.shallow_clones = get(s:c,'shallow_clones',1)
let s:c.scm_extra_args = get(s:c,'scm_extra_args',{})

let s:se = s:c.scm_extra_args
" this is not proberly quoted yet thus its will change:
" using list so that we can encode ['$ $',[1,2]] (quoting values if needed)
let s:se.git = get(s:c,'git', [s:c.shallow_clones ? '--depth 1' : ''])

" this may be useful for other projects.
" Thus move checking .hg .svn etc into a different file

fun! vcs_checkouts#Update(dir)
  let directory = a:dir
  if isdirectory(directory.'/.git')
    call s:exec_in_dir([{'d': directory, 'c': 'git fetch'}])
  elseif isdirectory(directory.'/.svn')
    call s:exec_in_dir([{'d': directory, 'c': 'svn update'}])
  elseif isdirectory(directory.'/.bzr')
    call vam#utils#RunShell('bzr pull -d $', directory)
  elseif isdirectory(directory.'/.hg')
    call vam#utils#RunShell('hg pull -u -R $', directory)
  else
    " not knowing how to update a repo is not a failure
    return 0
  endif
  if v:shell_error
    throw "Updating ".a:dir." falied. Got exit code: ".v:shell_error
  endif
  return 1
endf

" repository = {'type': git|hg|svn|bzr, 'url': .. }
fun! vcs_checkouts#Checkout(targetDir, repository)
  if a:repository['type'] == 'git'
    call vam#utils#RunShell('git clone '.s:se.git[0].' $ $p', a:repository.url, a:targetDir)
  elseif a:repository['type'] == 'hg'
    call vam#utils#RunShell('hg clone $ $p', a:repository.url, a:targetDir)
  elseif a:repository['type'] == 'bzr'
    call vam#utils#RunShell('bzr branch $ $p', a:repository.url, a:targetDir)
  elseif a:repository['type'] == 'svn'
    let args=['svn checkout $ $p', a:repository.url, a:targetDir]
    for key in filter(['username', 'password'], 'has_key(a:repository, v:val)')
      let args[0].=' --'.key.' $'
      let args+=[a:repository[key]]
    endfor
    call call('vam#utils#RunShell', args)
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
