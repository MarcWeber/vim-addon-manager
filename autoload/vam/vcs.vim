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

fun! vam#vcs#GitCheckoutFixDepth(repository, targetDir)
  " older git versions don't support shallow clone, check by reading --help
  " output
  "
  " Neither does google code support it (yet)
  let use_shallow_clone = s:c.scms.git.supports_shallow_clone

  if (use_shallow_clone is# 'auto')
    unlet use_shallow_clone
    let use_shallow_clone = g:is_win ? 1 : (executable('git') && stridx(system('git help --man clone'), '--depth')!=-1)
  endif
  let use_shallow_clone = use_shallow_clone && a:repository.url !~? 'code\.google\.com'

  let git_checkout='git clone --recursive '.(use_shallow_clone ? '--depth 1' : '').' $.url $p'
  return vam#utils#RunShell(git_checkout, a:repository, a:targetDir)
endf

let s:scm_defaults={
      \  'git': {'clone': ['vam#vcs#GitCheckoutFixDepth', []],
      \         'update': ['vam#utils#RunShell', ['cd $p && git pull'        ]],
      \          'wdrev': ['vam#utils#System',   ['git --git-dir=$p/.git rev-parse HEAD']],
      \            'log': ['vam#utils#System',   ['git --git-dir=$2p/.git log $1 $[3]..$[4]', '--pretty=format:%s%n']],
      \           'supports_shallow_clone': 'auto',
      \          },
      \   'hg': {'clone': ['vam#utils#RunShell', ['hg clone $.url $p'        ]],
      \         'update': ['vam#utils#RunShell', ['hg pull -u -R $p'         ]],
      \          'wdrev': ['vam#utils#System',   ['hg log --template $ -R $p -r .', '{rev}']],
      \            'log': ['vam#vcs#MercurialLog', []],},
      \  'bzr': {'clone': ['vam#utils#RunShell', ['bzr branch $.url $p'      ]],
      \         'update': ['vam#utils#RunShell', ['bzr pull -d $p'           ]],
      \          'wdrev': ['vam#utils#System',   ['bzr revno --tree $p'      ]],
      \            'log': ['vam#vcs#RunWithIncrementedRev', ['bzr log --short $p -r $[]..$[]']],},
      \  'svn': {'clone': ['vam#vcs#SVNCheckout',[]],
      \         'update': ['vam#utils#RunShell', ['svn update $p'            ]],
      \          'wdrev': ['vam#vcs#SVNWdrev',   []],
      \            'log': ['vam#vcs#RunWithIncrementedRev', ['svn log $p -r $[]:$[]']],},
      \'darcs': {'clone': ['vam#utils#RunShell', ['darcs get --lazy $.url $p']],
      \         'update': ['vam#utils#RunShell', ['darcs pull --all --repodir $p'  ]],
      \          'wdrev': ['vam#vcs#DarcsWdrev', []],
      \            'log': ['vam#vcs#DarcsLog',   []],},
      \'_bundle': {'update': ['vam#vcs#UpdateBundle', []],},
    \}
let s:c.scms=get(s:c, 'scms', {})
call map(filter(copy(s:c.scms), 'has_key(s:scm_defaults, v:key)'), 'extend(v:val, s:scm_defaults[v:key], "keep")')
call extend(s:c.scms, s:scm_defaults, 'keep')
call map(copy(s:c.scms), 'extend(v:val, {"dir": ".".v:key})')
let s:c.scms.darcs.dir='_darcs'

fun! vam#vcs#RunWithIncrementedRev(...)
  let args=copy(a:000)
  let args[-2]+=1
  return call('vam#utils#System', args)
endfun

fun! vam#vcs#MercurialLog(targetDir, oldVersion, newVersion)
  " Note: this will show nothing if oldVersion is not an ancestor of 
  "       a newVersion. Mercurial should not update with the above command in 
  "       this case though.
  return call('vam#utils#System', ['hg log --template $ -R $p -r $', '{desc}\n', a:targetDir,
        \                          a:oldVersion.'..'.a:newVersion.' and not '.a:oldVersion])
endfun

fun! vam#vcs#DarcsLog(targetDir, oldVersion, newVersion)
  return call('vam#utils#System', ['darcs log --repodir $p --last=$', a:targetDir, a:newVersion-a:oldVersion])
endfun

fun! vam#vcs#DarcsWdrev(targetDir)
  let result=vam#utils#System('darcs show repo --repodir $p', a:targetDir)
  return substitute(result, '\v.*\n\s*Num\ Patches\:\ (\d+).*', '\1', '')
endfun

fun! vam#vcs#SVNWdrev(targetDir)
  let result=vam#utils#System('svn info $p', a:targetDir)
  return substitute(result, '\v.{-}\nRevision\:\ (\d+).*', '\1', '')
endfun

fun! s:WriteBundleDir(targetDir, url, archive)
  call mkdir(a:targetDir.'/._bundle')
  call writefile([a:url, a:archive], a:targetDir.'/._bundle/opts', 'b')
endfun

fun! vam#vcs#UrlFromRepository(repository)
  let [dummystr, protocol, user, domain, port, path; dummylst]=
              \matchlist(a:repository.url, '\v^%(([^:]+)\:\/\/)?'.
              \                               '%(([^@/:]+)\@)?'.
              \                                '([^/:]*)'.
              \                               '%(\:(\d+))?'.
              \                                '(.*)$')
  if domain is? 'github.com'
    let url='https://'.domain.'/'.substitute(path, '\v^[:/]|\.git$', '', 'g').'/zipball/master'
    let archive='master.zip'
  elseif domain is? 'bitbucket.org'
    let url='https://'.domain.path.'/get/default.zip'
    let archive='default.zip'
  elseif domain is? 'git.devnull.li'
    let url='http://'.domain.path.'/snapshot/master.tar.gz'
    let archive='master.tar.gz'
  else
    throw 'Don’t know how to get bundle from '.domain
  endif
  return {'archive': archive, 'url': url}
endfun

fun! vam#vcs#GetBundle(repository, targetDir)
  let x = vam#vcs#UrlFromRepository(a:repository)
  call vam#install#Checkout(a:targetDir, {'type': 'archive', 'url': x.url, 'archive_name': x.archive})
  call s:WriteBundleDir(a:targetDir, url, archive)
  return 0
endfun

fun! vam#vcs#UpdateBundle(targetDir)
  let [url, archive]=readfile(a:targetDir.'/._bundle/opts', 'b')
  call vam#utils#RmFR(a:targetDir)
  call vam#install#Checkout(a:targetDir, {'type': 'archive', 'url': url, 'archive_name': archive})
  call s:WriteBundleDir(a:targetDir, url, archive)
  return 0
endfun

fun! s:TryCmd(...)
  try
    return call('vam#utils#RunShell', a:000)
  catch
    return 1
  endtry
endfun
fun! s:TryCmdSilent(...)
  silent return call('s:TryCmd', a:000)
endfun

fun! vam#vcs#GitCheckout(repository, targetDir)
  if executable('git')
    return vam#vcs#GitCheckoutFixDepth(a:repository, a:targetDir)
  elseif executable('hg') && !s:TryCmdSilent('hg help gexport')
    call vam#Log('Trying to checkout git source '.a:repository.url.' using mercurial.', 'None')
    return s:TryCmd('hg clone $ $p', ((a:repository.url[:2] is# 'git')?
          \                               (a:repository.url):
          \                               ('git+'.a:repository.url)),
          \                          a:targetDir)
  elseif executable('bzr') && !s:TryCmdSilent('bzr help git')
    call vam#Log('Trying to checkout git source '.a:repository.url.' using bazaar.', 'None')
    return s:TryCmd('bzr branch $.url $p', a:repository, a:targetDir)
  else
    call vam#Log('Trying to checkout git source '.a:repository.url." using site bundles.\n".
          \      'Please consider installing git or mercurial with hg-git extension', 'WarningMsg')
    return vam#vcs#GetBundle(a:repository, a:targetDir)
  endif
endfun

fun! vam#vcs#MercurialCheckout(repository, targetDir)
  if executable('hg')
    return vam#utils#RunShell('hg clone $.url $p', a:repository, a:targetDir)
  else
    call vam#Log('Trying to checkout mercurial source '.a:repository.url." using site bundles.\n".
          \      'Please consider installing git or mercurial with hg-git extension', 'WarningMsg')
    return vam#vcs#GetBundle(a:repository, a:targetDir)
  endif
endfun

fun! vam#vcs#SVNCheckout(repository, targetDir)
  let args=['svn checkout $.url $3p', a:repository, a:repository.url, a:targetDir]
  for key in filter(['username', 'password'], 'has_key(a:repository, v:val)')
    let args[0].=' --'.key.' $'
    let args+=[a:repository[key]]
  endfor
  call call('vam#utils#RunShell', args)
endfun

fun! vam#vcs#SubversionCheckout(repository, targetDir)
  " Both mercurial and bazaar are slow in this case because they request full 
  " changeset history from the server, while subversion does not.
  if executable('svn')
    return vam#vcs#SVNCheckout(a:repository, a:targetDir)
  elseif executable('hg') && !s:TryCmdSilent('hg help svn')
    call vam#Log('Trying to checkout subversion source '.a:repository.url." using mercurial.\n".
          \      'You may consider installing svn as using mercurial is slower', 'WarningMsg')
    return s:TryCmd('hg clone $.url $p', a:repository, a:targetDir)
  elseif executable('bzr') && !s:TryCmdSilent('bzr help svn')
    call vam#Log('Trying to checkout subversion source '.a:repository.url." using bazaar.\n".
          \      'You may consider installing subversion as using bazaar is slower', 'WarningMsg')
    return s:TryCmd('bzr branch $.url $p', a:repository, a:targetDir)
  endif
  return 1
endfun

" Accepts VCS root
" Returns a 4-tuple (status, old revision, new revision, scms.* dictionary)
fun! vam#vcs#Update(dir)
  for [scm, sdescr] in items(s:c.scms)
    if isdirectory(a:dir.'/'.(sdescr.dir))
      break
    endif
    unlet sdescr
  endfor

  if !exists('sdescr')
    return ['unknown', 0, 0, 0]
  endif

  if has_key(sdescr, 'wdrev')
    let w=sdescr.wdrev
    let wdrev=call(w[0], get(w, 1, [])+[a:dir], get(w, 2, {}))
  else
    let wdrev=0
  endif
  let c=sdescr.update
  if call(c[0], c[1] + [a:dir], get(c, 2, {}))
    call vam#Log('Updating '.a:dir.' failed. The :AddonInfo command may tell you about a new upstream source. If in doubt move the plugin directory somewhere else, install it from scratch and check the differences')
    return ['failed', wdrev, 0, sdescr]
  endif

  if exists('wdrev') && wdrev isnot 0
    let newwdrev=call(w[0], get(w, 1, [])+[a:dir], get(w, 2, {}))
    if newwdrev is 0
      return ['possibly updated', wdrev, 0, sdescr]
    elseif wdrev isnot# newwdrev
      return ['updated', wdrev, newwdrev, sdescr]
    else
      return ['up-to-date', wdrev, newwdrev, sdescr]
    endif
  else
    return ['possibly updated', 0, 0, sdescr]
  endif
endfun

" repository = {'type': git|hg|svn|bzr, 'url': .. }
fun! vam#vcs#Checkout(targetDir, repository)
  if has_key(s:c.scms, a:repository.type)
    let c=s:c.scms[a:repository.type].clone
    if call(c[0], get(c, 1, [])+[a:repository, a:targetDir], get(c, 2, {}))
      throw "Failed to checkout addon to ".a:targetDir."."
    endif
  else
    " Keep old behavior: no throw for unknown repository type
    return
  endif
  if !isdirectory(a:targetDir)
    throw "Failure. Plugin directory ".a:targetDir." should have been created but does not exist."
  endif
  return 1
endfun

" vim: et ts=8 sts=2 sw=2
