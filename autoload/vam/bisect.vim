
exec vam#DefineAndBind('s:c','g:vim_addon_manager','{}')

fun! vam#bisect#StepBad(vim, plain, addons, vimrc_tmp) abort
  let cmd_items = copy(a:vim)
  if a:plain
    call extend(cmd_items, ["-u", "NONE", "-U", "NONE", "-N"])
  else
    let vimrc_contents = readfile($MYVIMRC)
    call writefile(['let g:vam_plugin_whitelist = '.string(a:addons)]+ vimrc_contents, a:vimrc_tmp)
    call extend(cmd_items, ["-u", a:vimrc_tmp])
  endif

  call extend(cmd_items, ["--cmd", "command -bar -nargs=0 OKVAMBisect  call writefile(['ok'], ".string(a:vimrc_tmp).")|qa!"])
  call extend(cmd_items, ["--cmd", "command -bar -nargs=0 BADVAMBisect call writefile(['bad'], ".string(a:vimrc_tmp).")|qa!"])
  call extend(cmd_items, ["-c", "echom 'VAM bisect running. Run your test and either of OKVAMBisect, BADVAMBisect to quit'"])

  " call system(join(map(cmd_items,'shellescape(v:val)')," "))
  " take care about %, use VAMs functions?

  if !vam#install#confirm('running vim with addons '.string(a:addons).' plain: '.a:plain)
    throw "user abort"
  endif
  exec '!'.join(map(cmd_items,'shellescape(v:val, 1)'), ' ')
  let r = readfile(a:vimrc_tmp)
  if r[0] == "ok"
    return 0
  elseif r[0] == "bad"
    return 1
  else
    throw "You used neither OKVAMBisect nor BADVAMBisect to exit vim!"
  endif
endfun

" ... must be cache
fun! vam#bisect#List(vim_executable, skip_initial, addons, force_addons, ...) abort
  let cache = a:0 > 0 ? a:1 : {}

  if !exists('s:vimrc_tmp')
    let s:vimrc_tmp = tempname()
  endif

  " do we have a problem at all?
  let test      = 'let bad = vam#bisect#StepBad(a:vim_executable, 0, addons + a:force_addons, s:vimrc_tmp)'
  let testPlain = 'let bad = vam#bisect#StepBad(a:vim_executable, 1, addons + a:force_addons, s:vimrc_tmp)'

  let addons = a:addons

  if !a:skip_initial
    let addons = a:addons
    exec test
    if !bad
      throw "Bisect failed: test passed with all initial plugins activated. Are you user you have a problem?"
    endif
  endif

  " from now on we can assume that the addons which are passed fail in some way

  if len(addons) == 0
    " try .vimrc and plain
    " test plain only once:
    if has_key(cache, 'bisect_plain_result') | return s:bisect_plain_result | endif
    " test .vimrc
    exec testPlain
    if bad
      return {'problem_found': 1, 'message': 'The problem even occurs without your .gvimrc, .vimrc or ~/.vim. Probably its your vim installation?'}
    else
      let cache.bisect_plain_result = {'problem_found': 0, 'message': 'Problem was not found - nothing left to test. Are you sure you have a problem?'}
      return cache.bisect_plain_result
    endif
  endif

  if len(addons) == 1
    let addons = a:addons
    " one plugin left, make sure its not the user's .vimrc causing the problem:
    let r = vam#bisect#List(a:vim_executable, 1, [], a:force_addons, cache)
    if r.problem_found
      return r
    else
      return {'problem_found': 1, 'message':  'The plugin '.addons[0].' or one of its dependencies is likely to cause the problem'}
    endif
  endif

  " try left half of plugins:
  let addons = a:addons[0:len(a:addons)/2-1]
  exec test
  if bad
    " left half causes problem, recurse
    return vam#bisect#List(a:vim_executable, 1, addons, a:force_addons, cache)
  else
    " right side should contain issue, verify it
    let addons = a:addons[len(a:addons)/2:-1]
    exec test
    if bad
      let r = vam#bisect#List(a:vim_executable, 1, addons, a:force_addons, cache)
      if r.problem_found
        return r
      else
        throw "unexpected"
      endif
    else
      " neither left nor right side cause problem. Thus a combination of
      " the plugins on both sides is causing the issue!
      " neither right nor left side contains problem, a combination of
      " plugins found in left/right must be causing the problem
      return {'problem_found': 1, 'message': 'a combination of plugins is causing your issue. Addon list :' .string(a:addons).". If you find this message you may ask VAM devs to continue this implementation. Right now you're on you own - you have to continue manually. The argument force_addons may be of help"}
      " TODO continue this way:
      " TODO: cache system and user's .vimrc result
      "
      " let left_half  = a:addons[0:len(a:addons)/2-1]
      " let right_half = a:addons[len(a:addons)/2:-1]
      " " fix left_half
      " let r = vam#bisect#Bisect(a:vim_executable, right_half, left_half)

      " " fix right_half
      " let r = vam#bisect#Bisect(a:vim_executable, left_half, right_half)
    endif
  endif
endfun

" argument1: ['vim'] or ['gvim','--nofork']
" rerun vim bisecting the plugin list to find out which plugin might be
" causing trouble you're experiencing
fun! vam#bisect#Bisect(...)
  if a:0
    let vim_executable = copy(a:000)
  else
    let vim_executable = [v:progname, has('gui_running')? '-g' : '-v']
  endif
  " It does not harm running non-gui vim with --nofork
  let vim_executable += ['--nofork']
  let addons = keys(s:c.activated_plugins)
  try
    let r = vam#bisect#List(vim_executable, 0, addons, [])
  endtry
  let g:vim_addon_bisect_result = r
  call vam#Log(r.message)
endfun

fun! vam#bisect#BisectCompletion(A, L, P, ...)
  let list = ['vim','gvim']
  return list
endfun

" vim: et ts=8 sts=2 sw=2
