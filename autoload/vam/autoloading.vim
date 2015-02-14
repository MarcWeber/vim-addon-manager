exec vam#DefineAndBind('s:c','g:vim_addon_manager','{}')

fun! vam#autoloading#Setup()
  let s:c.autoloading_db_file=get(s:c, 'autoloading_db_file', s:c.plugin_root_dir.'/.autoloading_db.yml')
  let s:c.autoloading_db_file=expand(fnameescape(s:c.autoloading_db_file))

  let s:old_handle_runtimepaths=s:c.handle_runtimepaths

  fun! s:LoadDB(path)
    if !exists('s:db')
      if filereadable(a:path)
        let s:db = vam#ReadJSON(a:path)
      else
        let s:db = {'plugins': {}}
      endif
    endif
    return s:db
  endfun

  fun! s:WriteDB(db, path)
    call writefile([string(a:db)], a:path)
  endfun

  fun! s:addlistitem(dict, key, item)
    if !has_key(a:dict, a:key)
      let a:dict[a:key] = [a:item]
    else
      let a:dict[a:key] += [a:item]
    endif
  endfun

  unlet s:c.handle_runtimepaths
  fun! s:c.handle_runtimepaths(opts)
    if get(a:opts, 'no_lazy_loading', 0)
      return call(s:old_handle_runtimepaths, [a:opts], {})
    endif

    let db = s:LoadDB(s:c.autoloading_db_file)

    let new_runtime_paths = map(copy(a:opts.new_runtime_paths), 'vam#normpath(v:val)')

    if !exists('s:toscanfiles')
      let s:toscanfiles = {}
      let s:files = {}
      let s:omittedrtps = []
      let s:omittedafters = []
      let s:needs_write = 0
      let s:ftfiles = {'syntax': {}, 'filetype': {}}
    endif

    let rtstatus = map(copy(new_runtime_paths), 'has_key(db.plugins, v:val) + !empty(get(db.plugins, v:val))')
    let toautoload = filter(copy(new_runtime_paths), 'rtstatus[v:key] == 2')
    let toscan = filter(copy(new_runtime_paths), '!rtstatus[v:key]')

    if !empty(toautoload) && !exists('*s:map')
      let s:loaded_files = {}

      fun! s:AddRuntimePaths(rtps, afters)
        let &rtp = join(map(copy(a:rtps), 'escape(v:val, "\\,")')
              \        +(empty(&rtp) ? [] : [&rtp])
              \        +map(copy(a:afters), 'escape(v:val, "\\,")'), ',')
      endfun

      fun! s:SourceFile(file)
        let s:loaded_files[a:file] = 1
        for cmd in get(s:files, a:file, [])
          execute cmd
        endfor
        call map(s:events, 'filter(v:val, "v:key isnot# a:file")')
        augroup VAMAutoloadingAueRun
          for key in keys(filter(copy(s:events), 'empty(v:val)'))
            execute 'autocmd!' substitute(key, '#', ' ', '')
            unlet s:events[key]
          endfor
        augroup END
        if has('vim_starting')
          let saved_rtp = &rtp
          call s:AddRuntimePaths(s:omittedrtps, s:omittedafters)
        endif
        try
          execute 'source' fnameescape(a:file)
        finally
          if exists('saved_rtp')
            let &rtp = saved_rtp
          endif
        endtry
      endfun

      fun! s:AddFileCmd(file, cmd)
        let s:files[a:file] = add(get(s:files, a:file, []), a:cmd)
      endfun

      function s:hsescape(str)
        return substitute(substitute(substitute(substitute(a:str,
              \      ' ', '<Space>',         'g'),
              \      '|', '<Bar>',           'g'),
              \     "\n", '<CR>',            'g'),
              \'\c^<\%(buffer\|silent\|expr\|special\)\@=', '<LT>', '')
      endfunction

      fun! s:map(lhs, file, mode)
        let lhs = s:hsescape(a:lhs)
        call s:AddFileCmd(a:file, a:mode.'unmap '.lhs)
        let amrargs = s:hsescape(join(map([lhs, a:mode, 0, a:file], 'string(v:val)'), ','))
        execute a:mode.'map' '<expr> <silent>' lhs 'AutoloadingMapRun('.amrargs.')'
      endfun

      function s:genTempMap(mapdescr, mode)
        if a:mapdescr.expr>1
          let rhs = printf(a:mapdescr.rhs, '"'.mode.'","'.escape(lhs, '"\').'"')
        else
          let rhs = s:hsescape(a:mapdescr.rhs)
          let rhs = substitute(rhs, '<SID>', '<SNR>'.a:mapdescr.sid.'_', 'g')
        endif
        execute a:mode.((a:mapdescr.noremap)?('nore'):('')).'map'
              \ ((a:mapdescr.silent)?('<silent>'):(''))
              \ '<special>'
              \ ((a:mapdescr.expr)?('<expr>'):(''))
              \ '<Plug>VAMAutoloadingTempMap' rhs
      endfunction

      fun! AutoloadingMapRun(lhs, mode, abb, file)
        call s:SourceFile(a:file)
        let mapdescr=maparg(a:lhs, a:mode, a:abb, 1)
        if !empty(mapdescr)
          call s:genTempMap(mapdescr, a:mode)
          return "\<Plug>VAMAutoloadingTempMap"
        endif
      endfun

      fun! s:abb(lhs, file, mode)
        let lhs=s:hsescape(a:lhs)
        call s:AddFileCmd(a:file, a:mode.'unabbrev '.lhs)
        let aarargs=s:hsescape(join(map([lhs, a:mode, 1, a:file], 'string(v:val)'), ','))
        execute a:mode.'abbrev <expr> <silent>' lhs 'AutoloadingMapRun('.aarargs.')'
      endfun

      fun! AutoloadingCmdRun(cmd, bang, range, args, file)
        call s:SourceFile(a:file)
        execute a:range.a:cmd.a:bang a:args
      endfun

      let s:compcmds = {}
      let s:nextccid = 0
      let s:recursing = 0

      fun! s:comp(ccid, a, l, p)
        let cmddescr = s:compcmds[a:ccid]
        call s:SourceFile(cmddescr.file)
        if s:recursing
          return []
        endif
        let d = {}
        let s:recursing += 1

        try
          execute 'silent normal! :'.a:l[:(a:p))]."\<C-a>\<C-\>eextend(d, {'cmdline':getcmdline()}).cmdline\n"
        catch
          let d = {}
        finally
          let s:recursing -= 1
        endtry

        if has_key(d, 'cmdline')
          return split(d.cmdline[(a:p-len(a:a)):], '\\\@<! ')
        else
          return []
        endif
      endfun

      fun! s:defcompl(cmd, cmddescr)
        let ccid = s:nextccid
        let s:nextccid += 1
        let s:compcmds[ccid] = a:cmddescr
        let sid = +(matchlist(expand('<sfile>'), '\v.*(\d+)')[1])
        " Silence possible errors if called from within s:comp() above
        call s:AddFileCmd(a:cmddescr.file, 'silent! delfunction s:_comp_'.ccid)
        execute "fun! s:_comp_".ccid."(a, l, p)\n"
              \ "    return s:comp(".ccid.", a:a, a:l, a:p)\n"
              \ "endfun"
        return 'customlist:<SNR>'.sid.'__comp_'.ccid
      endfun

      fun! s:cmd(cmd, cmddescr)
        call s:AddFileCmd(a:cmddescr.file, 'delcommand '.a:cmd)
        execute 'command' (a:cmddescr.bang ? '-bang' : '')
              \           '-nargs='.a:cmddescr.nargs
              \           (empty(a:cmddescr.range) ? '' :
              \             (a:cmddescr.range[-1:] is# 'c' ?
              \               '-count='.str2nr(a:cmddescr.range):
              \               (a:cmddescr.range is# '.' ?
              \                 '-range':
              \                 '-range='.a:cmddescr.range)))
              \           (empty(a:cmddescr.complete) ? '' :
              \             (a:cmddescr.complete[:5] is# 'custom' ?
              \               s:defcompl(a:cmd, a:cmddescr) :
              \               '-complete='.a:cmddescr.complete))
              \           a:cmd
              \           'call AutoloadingCmdRun('.string(a:cmd).', "<bang>", '.
              \               (empty(a:cmddescr.range)? '""' :
              \                 (a:cmddescr.range[-1:] is# 'c' ?
              \                   '<count>':
              \                   '"<line1>,<line2>"')).', '.
              \              '<q-args>, '.string(a:cmddescr.file).')'
      endfun

      fun! AutoloadingAueRun(key)
        for file in keys(remove(s:events, a:key))
          call s:SourceFile(file)
        endfor
        augroup VAMAutoloadingAueRun
          execute 'autocmd!' substitute(a:key, '#', ' ', '')
        augroup END
      endfun

      let s:events={}

      fun! s:aue(audescr)
        for pattern in a:audescr.patterns
          let key = a:audescr.event.'#'.pattern
          if !has_key(s:events, key)
            let s:events[key]  = {a:audescr.file : 1}
            augroup VAMAutoloadingAueRun
              execute 'autocmd' a:audescr.event pattern ':call AutoloadingAueRun('.string(key).')'
            augroup END
          else
            let s:events[key][a:audescr.file] = 1
          endif
        endfor
      endfun

      fun! s:fun(fun, file)
        call s:aue({'event': 'FuncUndefined', 'file': a:file, 'patterns': [a:fun]})
      endfun

      fun! s:LoadFTFiles(type, ft)
        if !has_key(s:ftfiles[a:type], a:ft)
          return
        endif
        if has('vim_starting')
          let saved_rtp = &rtp
          call s:AddRuntimePaths(s:omittedrtps, s:omittedafters)
        endif
        try
          for [rtp, files] in s:ftfiles[a:type][a:ft]
            for file in s:db.plugins[rtp].files.plugin
              if !has_key(s:loaded_files, file)
                call s:SourceFile(file)
              endif
            endfor
            for file in files
              call s:SourceFile(file)
            endfor
          endfor
        finally
          if exists('saved_rtp')
            let &rtp = saved_rtp
          endif
        endtry
      endfun

      augroup VAMAutoloading
        autocmd! FileType * :call s:LoadFTFiles('filetype', expand('<amatch>'))
        autocmd! Syntax   * :call s:LoadFTFiles('syntax', expand('<amatch>'))
      augroup END

      fun! s:DefineFTEvent(type, ft, files, rtp)
        let s:ftfiles[a:type][a:ft] = add(get(s:ftfiles[a:type], a:ft, []), [a:rtp, a:files])
      endfun
    endif

    for rtp in toautoload
      let dbitem=db.plugins[rtp]
      try
        for key in ['mappings', 'abbreviations']
          for [mode, value] in items(dbitem[key])
            for [lhs, file] in items(value)
              call s:{key[:2]}(lhs, file, mode)
            endfor
          endfor
        endfor
        for [cmd, cmddescr] in items(dbitem.commands)
          call s:cmd(cmd, cmddescr)
        endfor
        for audescr in values(dbitem.autocommands)
          call s:aue(audescr)
        endfor
        for [func, ffile] in items(dbitem.functions)
          call s:fun(func, ffile)
        endfor
        for [key, type] in [['ftplugins', 'filetype'], ['indents', 'filetype'], ['syntaxes', 'syntax']]
          for [ft, files] in items(dbitem[key])
            call s:DefineFTEvent(type, ft, files, rtp)
          endfor
        endfor
      endtry
    endfor

    if has('vim_starting')
      let s:omittedrtps += toautoload
      let s:omittedafters += filter(map(copy(toautoload), 'v:val."/after"'), 'isdirectory(v:val)')
    else
      call s:AddRuntimePaths(toautoload,
            \filter(map(copy(toautoload), 'v:val."/after"'), 'isdirectory(v:val)'))
    endif

    for rtp in toscan
      let toscanfiles = {}
      call map(vam#GlobInDir(rtp, '{,after/}plugin/**/*.vim'), 'extend(toscanfiles, {vam#normpath(v:val) : rtp})')
      if empty(toscanfiles)
        " No plugin files, do not bother with autoloading then
        let db.plugins[rtp] = 0
        let s:needs_write = 1
        continue
      endif
      call extend(s:toscanfiles, toscanfiles)

      let dbitem = {'ftplugins': {}, 'syntaxes': {}, 'indents': {},
            \       'mappings': {}, 'commands': {}, 'functions': {}, 'abbreviations': {},
            \       'autocommands': {}, 'ftdetects': [],
            \       'files': {'plugin': keys(toscanfiles), 'ftplugin': [], 'syntax': [], 'indent': []}}

      for file in vam#GlobInDir(rtp, '{,after/}ftplugin/{*/,}*.vim')
        let filetype=substitute(file, '.*ftplugin/\v([^/_]+%(%(_[^/]*)?\.vim$|\/[^/]+$)@=).*', '\1', 'g')
        let file=vam#normpath(file)
        call s:addlistitem(dbitem.ftplugins, filetype, file)
        call add(dbitem.files.ftplugin, file)
      endfor

      for file in vam#GlobInDir(rtp, '{,after/}indent/{*/,}*.vim')
        let filetype=substitute(file, '.*indent/\v([^/_]+%(%(_[^/]*)?\.vim$|\/[^/]+$)@=).*', '\1', 'g')
        let file=vam#normpath(file)
        call s:addlistitem(dbitem.indents, filetype, file)
        call add(dbitem.files.indent, file)
      endfor

      for file in vam#GlobInDir(rtp, '{,after/}syntax/{*/,}*.vim')
        let filetype=substitute(file, '.*syntax/\v([^/]+%(\.vim$|\/[^/]+$)@=).*', '\1', 'g')
        let file=vam#normpath(file)
        call s:addlistitem(dbitem.syntaxes, filetype, file)
        call add(dbitem.files.syntax, file)
      endfor

      let dbitem.ftdetects=map(vam#GlobInDir(rtp, '{,after/}ftdetect/*.vim'), 'vam#normpath(v:val)')

      let db.plugins[rtp] = dbitem
      let s:needs_write = 1
    endfor

    if !empty(s:toscanfiles) && !exists('*s:RecordPreState')
      fun! s:RecordPreState()
        let prestate = {'mappings': {}}
        for mode in ['n', 'x', 's', 'o', 'i', 'c', 'l']
          redir => prestate.mappings[mode]
            execute 'silent' mode.'map'
          redir END
        endfor
        redir => prestate.abbreviations
          silent abbreviate
        redir END

        " TODO
        " for mode in ['a', 'n', 'o', 'x', 's', 'i', 'c']
          " redir => prestate.menus[mode]
            " execute 'silent' mode.'menu'
          " redir END
        " endfor

        redir => prestate.commands
          silent command
        redir END

        redir => prestate.functions
          silent function /.*
        redir END

        redir => prestate.autocommands
          silent autocmd
        redir END

        return prestate
      endfun
      fun! s:PreStateToState_mappings(mappings)
        return {}
      endfun
      fun! s:PreStateToState_mappings_one(mode, mappings)
        let ret={}
        call map(map(split(a:mappings, "\n"),
              \'maparg(matchstr(v:val, ''\v\C\S+'', 3), a:mode, 0, 1)'),
              \'empty(v:val) || v:val.buffer? 0 : extend(ret, {v:val.lhs: 1})')
        return ret
      endfun
      fun! s:PreStateToState_abbreviations(abbreviations)
        let ret={}
        call map(map(split(a:abbreviations, "\n"),
              \'maparg(matchstr(v:val, ''\v\C\S+'', 3), mode, 1, 1)'),
              \'
              \ empty(v:val) || v:val.buffer
              \ ? 0
              \ : extend(ret, {v:val.mode : extend(get(ret, v:val.mode, {}), {v:val.lhs : 1})})
              \')
        return ret
      endfun
      fun! s:PreStateToState_commands(commands)
        let ret={}
        call map(map(filter(split(a:commands, "\n")[1:], 'v:val[2] isnot# "b"'),
              \'
              \ {
              \   "cmd": v:val,
              \   "bang": v:val[0] is# "!",
              \   "cnr": matchlist(v:val, "\\v(\\S+)\\ +([01*?+])\\ {4}(\\S*)", 3)[1:3]
              \ }
              \'),
              \'
              \ extend(ret, {v:val.cnr[0] : {
              \   "nargs": v:val.cnr[1],
              \   "range": v:val.cnr[2],
              \   "complete": matchstr(v:val.cmd, "^\\S\\+", 3+(max([len(v:val.cmd), 11])+1)+(1+4)+(max([len(v:val.cnr[2]), 5])+1)),
              \   "bang": v:val.bang,
              \ }})
              \')
        return ret
      endfun
      fun! s:PreStateToState_functions(functions)
        let ret={}
        call map(split(a:functions, "\n"),
              \'
              \ v:val[9] is# "<"
              \ ? 0
              \ : extend(ret, {matchstr(v:val, "[^(]\\+", 9): 1})
              \')
        return ret
      endfun
      fun! s:PreStateToState_autocommands(autocommands)
        let d={'augroup': 0, 'auevent': 0}
        let ret={}
        call map(split(a:autocommands, "\n"), '
              \v:val =~# "\\v^\\S.*\\ {2}"
              \?extend(d, {"auevent": v:val[strridx(v:val, "  ")+2 :], "key": v:val})
              \:(v:val =~# "\\v^\\w+"
              \  ?extend(d, {"auevent": v:val, "key": v:val})
              \  :(v:val[0] is# " "
              \    ?extend(ret, {
              \       d.key : get(ret, d.key, {
              \         "event": d.auevent,
              \         "patterns": add(get(get(ret, d.key, {}), "patterns", []),
              \                         matchstr(v:val, "\\v(\\.|\\S)+"))
              \       }),
              \     })
              \    : 0
              \  )
              \)
              \')
        return ret
      endfun
      fun! s:DiffingPreStateToState(oldprestate, newprestate)
        let oldstate={'mappings': {}, 'abbreviations': {}, 'menus': {}, 'functions': {}, 'commands': {}, 'autocommands': {}}
        let newstate=deepcopy(oldstate)
        for key in keys(a:oldprestate)
          if a:oldprestate[key] ==# a:newprestate[key]
            let oldstate[key]=0
            let newstate[key]=0
          else
            let oldstate[key]=s:PreStateToState_{key}(a:oldprestate[key])
            let newstate[key]=s:PreStateToState_{key}(a:newprestate[key])
          endif
        endfor

        for [mode, mappings] in items(a:oldprestate.mappings)
          if a:oldprestate.mappings[mode] !=# a:newprestate.mappings[mode]
            let oldstate.mappings[mode]=s:PreStateToState_mappings_one(mode, a:oldprestate.mappings[mode])
            let newstate.mappings[mode]=s:PreStateToState_mappings_one(mode, a:newprestate.mappings[mode])
          endif
        endfor
        return [oldstate, newstate]
      endfun

      fun! s:PopulateDbFromStateDiff(file, oldstate, newstate)
        let file=a:file
        let [oldstate, newstate]=s:DiffingPreStateToState(a:oldstate, a:newstate)
        let rtp=s:toscanfiles[file]
        let db=s:LoadDB(s:c.autoloading_db_file)
        let dbitem=db.plugins[rtp]
        for key in ['mappings', 'abbreviations']
          if newstate[key] isnot# 0
            for [mode, newm] in items(newstate[key])
              let oldm=oldstate[key][mode]
              if !has_key(dbitem[key], mode)
                let dbitem[key][mode]={}
              endif
              for [lhs, m] in items(filter(copy(newm), '!has_key(oldm, v:key)'))
                "! let dbitem[key][mode][lhs] = extend({'file': file}, m)
                "!-
                let dbitem[key][mode][lhs] = file
              endfor
            endfor
          endif
        endfor

        if newstate.commands isnot# 0
          for [cmd, props] in items(filter(copy(newstate.commands), '!has_key(oldstate.commands, v:key)'))
            let dbitem.commands[cmd]=extend({'file': file}, props)
          endfor
        endif

        if newstate.functions isnot# 0
          for [function, fargs] in items(filter(copy(newstate.functions), '!has_key(oldstate.functions, v:key)'))
            "! let dbitem.functions[function] = {'file': file, 'args': fargs}
            "!-
            let dbitem.functions[function] = file
          endfor
        endif

        if newstate.autocommands isnot# 0
          for [key, aprops] in items(filter(copy(newstate.autocommands), '!has_key(oldstate.autocommands, v:key)'))
            let dbitem.autocommands[key]=extend({'file': file}, aprops)
          endfor
        endif

        if has('vim_starting')
          let s:needs_write = 1
        else
          call s:WriteDB(db, s:c.autoloading_db_file)
        endif
      endfun

      " TODO? Use “manual” sourcing instead? See downside 5 in the 
      "       documentation.
      fun! s:SourceCmd(path)
        let file = vam#normpath(a:path)
        let saved_eventignore = &eventignore
        set eventignore+=SourceCmd
        if has_key(s:toscanfiles, file)
          let oldprestate = s:RecordPreState()
        endif
        try
          execute 'source' fnameescape(a:path)
          if has_key(s:toscanfiles, file)
            let newprestate = s:RecordPreState()
            if oldprestate !=# newprestate
              call s:PopulateDbFromStateDiff(file, oldprestate, newprestate)
            endif
          endif
        finally
          let &eventignore = saved_eventignore
        endtry
      endfun

      augroup VAMAutoloading
        autocmd! SourceCmd * nested :call s:SourceCmd(expand('<amatch>'))
      augroup END
    endif

    if !exists('*s:VimEnter')
      fun! s:VimEnter()
        if !empty(s:omittedrtps)
          call s:AddRuntimePaths(s:omittedrtps, s:omittedafters)
          let s:omittedrtps = []
        endif
        if s:needs_write
          call s:WriteDB(s:db, s:c.autoloading_db_file)
          let s:needs_write = 0
        endif
        augroup VAMAutoloading
          autocmd! FuncUndefined *#*
        augroup END
        augroup VAMAutoloadingAueRun
          autocmd! FileType
          autocmd! Syntax
        augroup END
      endfun

      fun! s:AuFuncUndefined(func)
        " Check first: it may have happened that one of the other 
        " FuncUndefined events has loaded this function
        if exists('*'.a:func)
          return
        endif
        let fname = fnamemodify(tr(a:func, '#', '/'), ':h') . '.vim'
        if !empty(s:omittedrtps)
          let saved_rtp = &rtp
          call s:AddRuntimePaths(s:omittedrtps, s:omittedafters)
        endif
        try
          for path in filter(map(copy(s:omittedrtps), 'v:val."/".fname'), 'filereadable(v:val)')
            execute 'source' fnameescape(path)
            if exists('*'.a:func)
              break
            endif
          endfor
        finally
          if exists('saved_rtp')
            let &rtp = saved_rtp
          endif
        endtry
      endfun

      if has('vim_starting')
        augroup VAMAutoloading
          autocmd! VimEnter      *   :call s:VimEnter()
          autocmd! FuncUndefined *#* :call s:AuFuncUndefined(expand('<amatch>'))
        augroup END
      else
        " Adding to runtimepath does not trigger loading plugins at this point 
        " (and also after VimEnter above). Thus no need to bother with 
        " autoloading autoload functions, autoloading ftplugins and syntaxes and 
        " so on.
        call s:VimEnter()
      endif
    endif

    return call(s:old_handle_runtimepaths, [extend({'new_runtime_paths': filter(copy(new_runtime_paths), 'rtstatus[v:key] < 2')}, a:opts, 'keep')], {})
  endfun

  fun! AutoloadingInvalidateHook(info, repository, pluginDir, hook_opts)
    let db=s:LoadDB(s:c.autoloading_db_file)
    let rtp=vam#normpath(a:pluginDir)
    if has_key(db.plugins, rtp)
      unlet db.plugins[rtp]
    endif
    call s:WriteDB(db, s:c.autoloading_db_file)
  endfun

  let s:c.post_update_hook_functions      = ['AutoloadingInvalidateHook']+
        \get(s:c, 'post_update_hook_functions', ['vam#install#ApplyPatch'])
  let s:c.post_scms_update_hook_functions = ['AutoloadingInvalidateHook']+
        \get(s:c, 'post_scms_update_hook_functions', ['vam#install#ShowShortLog'])
endfun
" TODO: clear up unused directories from the database.
" vim: et ts=8 sts=2 sw=2
