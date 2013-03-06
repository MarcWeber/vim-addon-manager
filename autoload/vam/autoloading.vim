exec vam#DefineAndBind('s:c','g:vim_addon_manager','{}')

fun! vam#autoloading#Setup()
  let s:c.autoloading_db_file=get(s:c, 'autoloading_db_file', s:c.plugin_root_dir.'/.autoloading_db.json')
  let s:c.autoloading_db_file=expand(fnameescape(s:c.autoloading_db_file))

  let s:old_handle_runtimepaths=s:c.handle_runtimepaths

  fun! s:LoadDB(path)
    if !exists('s:db')
      if filereadable(a:path)
        let s:db = vam#ReadJSON(a:path)
      else
        let s:db = {'paths': {}}
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
    let db = s:LoadDB(s:c.autoloading_db_file)

    let new_runtime_paths = map(copy(a:opts.new_runtime_paths), 'vam#normpath(v:val)')

    if !exists('s:toscanfiles')
      let s:toscanfiles = {}
      let s:files = {}
      let s:omittedrtps = []
      let s:needs_write = 0
    endif

    let toscan = []
    let toautoload = []
    call map(copy(new_runtime_paths), 'add(has_key(db.paths, v:val) ? toautoload : toscan, v:val)')

    if !empty(toautoload) && !exists('*s:map')
      fun! s:AddRuntimePaths(paths)
        let &rtp .= ','.join(map(a:paths, 'escape(v:val, "\\,")'), ',')
      endfun

      fun! s:SourceFile(file)
        for cmd in get(s:files, a:file, [])
          execute cmd
        endfor
        call map(s:events, 'filter(v:val, "v:key isnot# a:file")')
        augroup VAMAutoloading
          for key in keys(filter(copy(s:events), 'empty(v:val)'))
            execute 'autocmd!' substitute(key, '#', ' ', '')
            unlet s:events[key]
          endfor
        augroup END
        if has('vim_starting')
          let saved_rtp = &rtp
          call s:AddRuntimePaths(s:omittedrtps)
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
        let lhs=s:hsescape(a:lhs)
        call s:AddFileCmd(a:file, a:mode.'unmap '.lhs)
        let amrargs=s:hsescape(join(map([lhs, a:mode, 0, a:file], 'string(v:val)'), ','))
        execute a:mode.'map' '<expr> <silent>' lhs 'AutoloadingMapRun('.amrargs.')'
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
      endfun

      let s:events={}

      fun! s:aue(audescr)
        for pattern in a:audescr.patterns
          let key = a:audescr.event.'#'.pattern
          if !has_key(s:events, key)
            let s:events[key]  = {a:audescr.file : 1}
            augroup VAMAutoloading
              execute 'autocmd!' a:audescr.event pattern ':call AutoloadingAueRun('.string(key).')'
            augroup END
          else
            let s:events[key][a:audescr.file] = 1
          endif
        endfor
      endfun

      fun! s:fun(fun, file)
        call s:aue({'event': 'FuncUndefined', 'file': a:file, 'patterns': [a:fun]})
      endfun

      fun! s:LoadFTFiles(files)
        if has('vim_starting')
          let saved_rtp = &rtp
          call s:AddRuntimePaths(s:omittedrtps)
        endif
        try
          for file in a:files
            execute 'source' fnameescape(file)
          endfor
        finally
          if exists('saved_rtp')
            let &rtp = saved_rtp
          endif
        endtry
      endfun

      fun! s:DefineFTEvent(event, ft, files)
        augroup VAMAutoloading
          execute 'autocmd' a:event a:ft ':call s:LoadFTFile('.string(a:files).')'
        augroup END
      endfun

      fun! s:ftp(ft, files)
        return s:DefineFTEvent('FileType', a:ft, a:files)
      endfun

      fun! s:syn(ft, files)
        return s:DefineFTEvent('Syntax', a:ft, a:files)
      endfun
    endif

    for rtp in toautoload
      let dbitem=db.paths[rtp]
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
        for [key, event] in [['ftplugins', 'FileType'], ['syntaxes', 'Syntax']]
          for [ft, files] in items(dbitem[key])
            call s:{key[:2]}(ft, files)
          endfor
        endfor
      endtry
    endfor

    if has('vim_starting')
      let s:omittedrtps += toautoload
    else
      call s:AddRuntimePaths(toautoload)
    endif

    for rtp in toscan
      let dbitem={'ftplugins': {}, 'syntaxes': {}, 'mappings': {}, 'commands': {}, 'functions': {}, 'abbreviations': {},
            \     'autocommands': {}, 'ftdetects': []}
      call map(vam#GlobInDir(rtp, '{,after/}plugin/**/*.vim'), 'extend(s:toscanfiles, {v:val : rtp})')

      for file in vam#GlobInDir(rtp, '{,after/}ftplugin/{*/,}*.vim')
        let filetype=substitute(file, '.*ftplugin/\v([^/_]+%(%(_[^/]*)?\.vim$|\/[^/]+$)@=).*', '\1', 'g')
        let file=vam#normpath(file)
        call s:addlistitem(dbitem.ftplugins, filetype, file)
      endfor

      for file in vam#GlobInDir(rtp, '{,after/}syntax/{*/,}*.vim')
        let filetype=substitute(file, '.*syntax/\v([^/]+%(\.vim$|\/[^/]+$)@=).*', '\1', 'g')
        let file=vam#normpath(file)
        call s:addlistitem(dbitem.syntaxes, filetype, file)
      endfor

      let dbitem.ftdetects=map(vam#GlobInDir(rtp, '{,after/}ftdetect/*.vim'), 'vam#normpath(v:val)')

      let db.paths[rtp]=dbitem
      let s:needs_write = 1
    endfor

    if !empty(s:toscanfiles) && !exists('*s:RecordState')
      "! fun! s:FilterMAdict(madict)
      "!   unlet a:madict.sid
      "!   return a:madict
      "! endfun

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
            if empty(madict) || madict.buffer
              continue
            endif
            "! let state.mappings[mode][lhs] = s:FilterMAdict(madict)
            let state.mappings[mode][lhs] = 1
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
          "! let state.abbreviations[mode][lhs] = s:FilterMAdict(madict)
          let state.abbreviations[mode][lhs] = 1
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
          "! let exe=matchstr(line, '\S.*', start+len(complete))
          "!-
          let state.commands[cmd]={'nargs': nargs, 'range': range, 'complete': complete, 'bang': bang}
          "! let state.commands[cmd].command = exe
        endfor

        redir => functions
          silent function /.*
        redir END
        for line in split(functions, "\n")
          if line[9] is# '<'
            " s: functions start with <SNR>
            continue
          endif
          "! let state.functions[matchstr(line, '[^(]\+', 9)]=line[stridx(line, '('):]
          "!-
          let state.functions[matchstr(line, '[^(]\+', 9)] = 1
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
            "! let augroup = line[:(idx-1)]
            let auevent=line[(idx+2):]
            let key = line
          elseif line =~# '\v^\w+$'
            "! let augroup = 0
            let auevent = line
            let key = line
          elseif line[0] is# ' '
            if !has_key(state.autocommands, key)
              let state.autocommands[key] = {'event': auevent, 'patterns': []}
              "! let state.autocommands[key].group = augroup
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
                  if !has_key(dbitem[key], mode)
                    let dbitem[key][mode]={}
                  endif
                  for [lhs, m] in items(filter(copy(newm), '!has_key(oldm, v:key)'))
                    "! let dbitem[key][mode][lhs] = extend({'file': file}, m)
                    "!-
                    let dbitem[key][mode][lhs] = file
                  endfor
                endif
              endfor
            endif
          endfor

          if newstate.commands !=# oldstate.commands
            for [cmd, props] in items(filter(copy(newstate.commands), '!has_key(oldstate.commands, v:key)'))
              let dbitem.commands[cmd]=extend({'file': file}, props)
            endfor
          endif

          if newstate.functions !=# oldstate.functions
            for [function, fargs] in items(filter(copy(newstate.functions), '!has_key(oldstate.functions, v:key)'))
              "! let dbitem.functions[function] = {'file': file, 'args': fargs}
              "!-
              let dbitem.functions[function] = file
            endfor
          endif

          if newstate.autocommands !=# oldstate.autocommands
            for [key, aprops] in items(filter(copy(newstate.autocommands), '!has_key(oldstate.autocommands, v:key)'))
              let dbitem.autocommands[key]=extend({'file': file}, aprops)
            endfor
          endif

          if has('vim_starting')
            let s:needs_write = 1
          else
            call s:WriteDB(db, s:c.autoloading_db_file)
          endif
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
            let newstate = s:RecordState()
            call s:PopulateDbFromStateDiff(file, oldstate, newstate)
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
          call s:AddRuntimePaths(s:omittedrtps)
          let s:omittedrtps = []
        endif
        if s:needs_write
          call s:WriteDB(s:db, s:c.autoloading_db_file)
          let s:needs_write = 0
        endif
        augroup VAMAutoloading
          autocmd! FuncUndefined *#*
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
          call s:AddRuntimePaths(s:omittedrtps)
        endif
        try
          for path in filter(map(copy(s:omittedrtps), 'v:val."/".fname'), 'filereadable(v:val)')
            execute 'source' fnameescape(path)
            if exists('*'.a:func)
              break
            endif
          endfor
        finally
          let &rtp = saved_rtp
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

    return call(s:old_handle_runtimepaths, [extend({'new_runtime_paths': toscan}, a:opts, 'keep')], {})
  endfun

  fun! AutoloadingInvalidateHook(info, repository, pluginDir, hook_opts)
    let db=s:LoadDB(s:c.autoloading_db_file)
    let rtp=vam#normpath(a:pluginDir)
    if has_key(db.paths, rtp)
      unlet db.paths[rtp]
    endif
    call s:WriteDB(db, s:c.autoloading_db_file)
  endfun

  let s:c.post_update_hook_functions      = ['AutoloadingInvalidateHook']+
        \get(s:c, 'post_update_hook_functions', ['vam#install#ApplyPatch'])
  let s:c.post_scms_update_hook_functions = ['AutoloadingInvalidateHook']+
        \get(s:c, 'post_scms_update_hook_functions', ['vam#install#ShowShortLog'])
endfun
" vim: et ts=8 sts=2 sw=2
