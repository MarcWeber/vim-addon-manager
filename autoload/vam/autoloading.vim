exec vam#DefineAndBind('s:c','g:vim_addon_manager','{}')

fun! vam#autoloading#Setup()
  let s:c.autoloading_db_file=get(s:c, 'autoloading_db_file', s:c.plugin_root_dir.'/.autoloading_db.json')
  let s:c.autoloading_db_file=expand(fnameescape(s:c.autoloading_db_file))

  let s:old_handle_runtimepaths=s:c.handle_runtimepaths

  fun! s:LoadDB(path)
    if filereadable(a:path)
      return vam#ReadJSON(a:path)
    else
      return {
            \'paths': {},
            \'ftplugins': {},
            \'syntaxes': {},
            \'mappings': {},
            \'abbreviations': {},
            \'commands': {},
            \'functions': {},
            \'autocommands': {},
          \}
    endif
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
    let db = s:LoadDB(s:c.autoloading_db_file)

    let new_runtime_paths = map(copy(a:opts.new_runtime_paths), 'vam#normpath(v:val)')

    if !exists('s:toscanfiles')
      let s:toscanfiles = {}
      let s:files = {}
      let s:omittedrtps = []
    endif

    let toscan = []
    let toautoload = []
    call map(copy(new_runtime_paths), 'add(has_key(db.paths, v:val) ? toautoload : toscan, v:val)')

    if !empty(toautoload) && !exists('*s:map')
      fun! s:SourceFile(file)
        for cmd in get(s:files, a:file)
          execute cmd
        endfor
        call map(s:events, 'filter(v:val, "v:val isnot# a:file")')
        augroup VAMAutoloading
          for key in keys(filter(copy(s:events), 'empty(v:val)'))
            execute 'autocmd!' substitute(key, '#', ' ', '')
            unlet s:events[key]
          endfor
        augroup END
        execute 'source' fnameescape(a:file)
      endfun

      fun! s:AddFileCmd(file, cmd)
        let s:files[a:file] = add(get(s:files, a:file, []), a:cmd)
      endfun

      fun! s:GetSID(file)
        redir => plugins
        silent scriptnames
        redir END
        let sids = reverse(map(split(plugins, "\n"), '[str2nr(v:val), v:val[stridx(v:val, ":")+2:]]'))
        let found = 0
        for [sid, file] in sids
          if a:file is# vam#normpath(name)
            let found = 1
            break
          endif
        endfor
        if !found
          throw 'Script ID not found'
        endif
      endfun

      fun! AutoloadingMapRun(lhs, file)
        call s:SourceFile(a:file)
        let sid = s:GetSID(a:file)
        let lhs = substitute(a:lhs, '<SID>', '<SNR>'.sid.'_', 'g')
        return eval('"'.escape(a:lhs, '\"<').'"')
      endfun

      function s:hsescape(str)
        return substitute(substitute(substitute(substitute(a:str,
              \      ' ', '<Space>',         'g'),
              \      '|', '<Bar>',           'g'),
              \     "\n", '<CR>',            'g'),
              \'\c^<\%(buffer\|silent\|expr\|special\)\@=', '<LT>', '')
      endfunction

      fun! s:map(mapdescr, mode)
        let lhs=s:hsescape(a:mapdescr.lhs)
        call s:AddFileCmd(a:mapdescr.file, a:mode.'unmap '.lhs)
        let amrargs=s:hsescape(join(map([lhs, a:mapdescr.file], 'string(v:val)'), ','))
        execute a:mode.'map' '<expr>' lhs 'AutoloadingMapRun('.amrargs.')'
      endfun

      function s:genTempMap(mapdescr, mode)
        if a:mapdescr.expr>1
          let rhs=printf(a:mapdescr.rhs, '"'.mode.'","'.escape(lhs, '"\').'"')
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

      fun! AutoloadingAbbRun(lhs, mode, file)
        call s:SourceFile(a:file)
        let mapdescr=maparg(a:lhs, a:mode, 1, 1)
        if !empty(mapdescr)
          call s:genTempMap(mapdescr, a:mode)
          return "\<Plug>VAMAutoloadingTempMap"
        endif
      endfun

      fun! s:abb(mapdescr, mode)
        let lhs=s:hsescape(a:mapdescr.lhs)
        call s:AddFileCmd(a:mapdescr.file, a:mode.'unabbrev '.lhs)
        let aarargs=s:hsescape(join(map([lhs, a:mode, a:mapdescr.file], 'string(v:val)'), ','))
        execute a:mode.'abbrev <expr> <silent>' lhs 'AutoloadingAbbRun('.aarargs.')'
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
        for file in remove(s:events, a:key)
          call s:SourceFile(file)
        endfor
        augroup VAMAutoloading
          execute 'autocmd!' substitute(a:key, '#', ' ', '')
        augroup END
      endfun

      let s:events={}

      fun! s:aug(audescr)
        for pattern in a:audescr.patterns
          let key = a:audescr.event.'#'.pattern
          if !has_key(s:events, key)
            let s:events[key]  = [a:audescr.file]
            augroup VAMAutoloading
              execute 'autocmd!' a:audescr.event pattern ':call AutoloadingAueRun('.string(key).')'
            augroup END
          else
            let s:events[key] += [a:audescr.file]
          endif
        endfor
      endfun
    endif

    fun! s:fun(fun, file)
      call s:aug({'event': 'FuncUndefined', 'file': a:file, 'patterns': [a:fun]})
    endfun

    for rtp in toautoload
      let dbitem=db.paths[rtp]
      try
        for key in ['mappings', 'abbreviations']
          for [mode, value] in items(dbitem[key])
            for desc in values(value)
              call s:{key[:2]}(desc, mode)
            endfor
          endfor
        endfor
        for [cmd, cmddescr] in items(dbitem.commands)
          call s:cmd(cmd, cmddescr)
        endfor
        for audescr in values(dbitem.autocommands)
          call s:aug(audescr)
        endfor
        for [func, fdescr] in items(dbitem.functions)
          call s:fun(func, fdescr.file)
        endfor
      endtry
    endfor

    if has('vim_starting')
      let s:omittedrtps += toautoload
    else
      let &rtp .= ','.join(map(toautoload, 'escape(v:val, "\\,")'), ',')
    endif

    for rtp in toscan
      let dbitem={'ftplugins': {}, 'syntaxes': {}, 'mappings': {}, 'commands': {}, 'functions': {}, 'abbreviations': {},
            \     'autocommands': {}, 'ftdetects': []}
      call map(vam#GlobInDir(rtp, '{,after/}plugin/**/*.vim'), 'extend(s:toscanfiles, {v:val : rtp})')

      for file in vam#GlobInDir(rtp, '{,after/}ftplugin/{*/,}*.vim')
        let filetype=substitute(file, '.*ftplugin/\v([^/_]+%(%(_[^/]*)?\.vim$|\/[^/]+$)@=).*', '\1', 'g')
        let file=vam#normpath(file)
        call s:addlistitem(dbitem.ftplugins, filetype, file)
        call s:addlistitem(db.ftplugins, filetype, file)
      endfor

      for file in vam#GlobInDir(rtp, '{,after/}syntax/{*/,}*.vim')
        let filetype=substitute(file, '.*syntax/\v([^/]+%(\.vim$|\/[^/]+$)@=).*', '\1', 'g')
        let file=vam#normpath(file)
        call s:addlistitem(dbitem.syntaxes, filetype, file)
        call s:addlistitem(db.syntaxes, filetype, file)
      endfor

      let dbitem.ftdetects=map(vam#GlobInDir(rtp, '{,after/}ftdetect/*.vim'), 'vam#normpath(v:val)')

      let db.paths[rtp]=dbitem
    endfor

    call s:WriteDB(db, s:c.autoloading_db_file)

    if !empty(s:toscanfiles) && !exists('*s:RecordState')
      fun! s:FilterMAdict(madict)
        return filter(a:madict, 'v:key isnot# "sid"')
      endfun

      fun! s:RecordState()
        let state={'mappings': {}, 'abbreviations': {}, 'menus': {}, 'functions': {}, 'commands': {}, 'autocommands': {}}

        for mode in ['n', 'x', 's', 'o', 'i', 'c', 'l']
          redir => mappings
            execute 'silent' mode.'map'
          redir END
          let state.mappings[mode]={}
          for line in split(mappings, "\n")
            let lhs=matchstr(line, '\S\+', 3)
            let madict=maparg(lhs, mode, 0, 1)
            if madict.buffer
              continue
            endif
            let state.mappings[mode][lhs]=s:FilterMAdict(madict)
          endfor
          unlet mappings
        endfor

        redir => abbreviations
          silent abbrev
        redir END
        for line in split(abbreviations, "\n")
          let mode=line[0]
          let lhs=matchstr(line, '\S\+', 3)
          let madict=maparg(lhs, mode, 1, 1)
          if empty(madict) || madict.buffer
            continue
          endif
          if !has_key(state.abbreviations, mode)
            let state.abbreviations[mode]={}
          endif
          let state.abbreviations[mode][lhs]=s:FilterMAdict(madict)
        endfor
        unlet abbreviations

        " TODO
        " for mode in ['a', 'n', 'o', 'x', 's', 'i', 'c']
          " redir => {mode}menus
            " execute 'silent' mode.'menu'
          " redir END
        " endfor

        redir => commands
          silent command
        redir END
        for line in split(commands, "\n")[1:]
          if line[2] is# 'b'
            continue
          endif
          let bang=(line[0] is# '!')
          let [cmd, nargs, range]=matchlist(line, '\v(\S+)\ +([01*?+])\ {4}(\S*)', 3)[1:3]
          "         ┌ bang field              ┌ nargs field
          "         │ ┌ command field         │     ┌ range field
          let start=3+(max([len(cmd), 11])+1)+(1+4)+(max([len(range), 5])+1)
          let complete=matchstr(line, '^\S\+', start)
          let exe=matchstr(line, '\S.*', start+len(complete))
          let state.commands[cmd]={'nargs': nargs, 'range': range, 'complete': complete, 'command': exe, 'bang': bang}
        endfor

        redir => functions
          silent function /.*
        redir END
        for line in split(functions, "\n")
          if line[9] is# '<'
            " s: functions start with <SNR>
            continue
          endif
          let state.functions[matchstr(line, '[^(]\+', 9)]=line[stridx(line, '('):]
        endfor
        unlet functions

        redir => autocommands
          silent autocmd
        redir END
        let augroup=0
        let auevent=0
        for line in split(autocommands, "\n")
          if line =~# '\v^\S.*\ {2}'
            let idx=strridx(line, '  ')
            let augroup=line[:(idx-1)]
            let auevent=line[(idx+2):]
            let key=augroup.'#'.auevent
          elseif line =~# '\v^\w+$'
            let augroup=0
            let auevent=line
            let key='#'.auevent
          elseif line[0] is# ' '
            if !has_key(state.autocommands, key)
              let state.autocommands[key]={'group': augroup, 'event': auevent, 'patterns': []}
            endif
            " XXX Pattern must be left escaped
            let state.autocommands[key].patterns+=[matchstr(line, '\v(\\.|\S)+')]
          endif
        endfor

        return state
      endfun

      fun! s:PopulateDbFromStateDiff(file, oldstate, newstate)
        let file=a:file
        let oldstate=a:oldstate
        let newstate=a:newstate
        let rtp=s:toscanfiles[file]
        let db=s:LoadDB(s:c.autoloading_db_file)
        let dbitem=db.paths[rtp]
        if newstate !=# oldstate
          for key in ['mappings', 'abbreviations']
            if newstate[key] !=# oldstate[key]
              for [mode, newm] in items(newstate[key])
                let oldm=get(oldstate[key], mode, {})
                if oldm !=# newm
                  if !has_key(db[key], mode)
                    let db[key][mode]={}
                  endif
                  if !has_key(dbitem[key], mode)
                    let dbitem[key][mode]={}
                  endif
                  for [lhs, m] in items(filter(copy(newm), '!has_key(oldm, v:key)'))
                    let db[key][mode][lhs]=extend({'rtp': rtp, 'file': file}, m)
                    let dbitem[key][mode][lhs]=db[key][mode][lhs]
                  endfor
                endif
              endfor
            endif
          endfor

          if newstate.commands !=# oldstate.commands
            for [cmd, props] in items(filter(copy(newstate.commands), '!has_key(oldstate.commands, v:key)'))
              let db.commands[cmd]=extend({'rtp': rtp, 'file': file}, props)
              let dbitem.commands[cmd]=db.commands[cmd]
            endfor
          endif

          if newstate.functions !=# oldstate.functions
            for [function, fargs] in items(filter(copy(newstate.functions), '!has_key(oldstate.functions, v:key)'))
              let db.functions[function]={'rtp': rtp, 'file': file, 'args': fargs}
              let dbitem.functions[function]=db.functions[function]
            endfor
          endif

          if newstate.autocommands !=# oldstate.autocommands
            for [key, aprops] in items(filter(copy(newstate.autocommands), '!has_key(oldstate.autocommands, v:key)'))
              let db.autocommands[key]=extend({'rtp': rtp, 'file': file}, aprops)
              let dbitem.autocommands[key]=db.autocommands[key]
            endfor
          endif

          call s:WriteDB(db, s:c.autoloading_db_file)
        endif
      endfun

      fun! s:SourceCmd(path)
        let file = vam#normpath(a:path)
        let saved_eventignore = &eventignore
        set eventignore+=SourceCmd
        if has_key(s:toscanfiles, file)
          let oldstate = s:RecordState()
        endif
        try
          execute 'source' fnameescape(a:path)
          if has_key(s:toscanfiles, file)
            let newstate=s:RecordState()
            call s:PopulateDbFromStateDiff(file, oldstate, newstate)
          endif
        finally
          let &eventignore=saved_eventignore
        endtry
      endfun

      augroup VAMAutoloading
        autocmd! SourceCmd * nested :call s:SourceCmd(expand('<amatch>'))
      augroup END
    endif

    if !empty(s:omittedrtps) && !exists('*s:AddOmittedRuntimepaths')
      fun! s:AddOmittedRuntimepaths()
        let &rtp .= ','.join(map(s:omittedrtps, 'escape(v:val, "\\,")'), ',')
        let s:omittedrtps = []
      endfun

      " Adding to runtimepath does not trigger loading plugins at this point 
      " (and also when !has('vim_starting') above). Thus no need to bother with 
      " autoloading autoload functions, autoloading ftplugins and syntaxes and 
      " so on.
      " TODO Check how it is likely that needed autoload function is requested 
      " before VimEnter and probably fix this case.
      " TODO Check whether FileType/Syntax events are triggered before or after 
      " VImEnter.
      " It looks like bothering with both functions and filetypes will be 
      " needed, but events to be used to maintain this could be removed after 
      " VimEnter.
      augroup VAMAutoloading
        autocmd! VimEnter * :call s:AddOmittedRuntimepaths()
      augroup END
    endif

    return call(s:old_handle_runtimepaths, [extend({'new_runtime_paths': toscan}, a:opts, 'keep')], {})
  endfun

  fun! AutoloadingInvalidateHook(info, repository, pluginDir, hook_opts)
    let db=s:LoadDB(s:c.autoloading_db_file)
    let rtp=vam#normpath(a:pluginDir)
    if has_key(db.paths, rtp)
      unlet db.paths[rtp]
      for key in ['ftplugins', 'syntaxes']
        if has_key(db[key], rtp)
          unlet db[key][rtp]
        endif
      endfor
      for key in ['commands', 'functions', 'autocommands']
        call filter(db[key], 'v:val.rtp is# rtp')
      endfor
      for key in ['mappings', 'abbreviations']
        for v in values(db[key])
          call filter(v, 'v:val.rtp is# rtp')
        endfor
      endfor
    endif
    call s:WriteDB(db, s:c.autoloading_db_file)
  endfun

  let s:c.post_update_hook_functions      = ['AutoloadingInvalidateHook']+
        \get(s:c, 'post_update_hook_functions', ['vam#install#ApplyPatch'])
  let s:c.post_scms_update_hook_functions = ['AutoloadingInvalidateHook']+
        \get(s:c, 'post_scms_update_hook_functions', ['vam#install#ShowShortLog'])
endfun
" vim: et ts=8 sts=2 sw=2
