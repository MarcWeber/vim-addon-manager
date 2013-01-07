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
      let a:dict[a:key]=[a:item]
    else
      let a:dict[a:key]+=[a:item]
    endif
  endfun

  unlet s:c.handle_runtimepaths
  fun! s:c.handle_runtimepaths(opts)
    let db=s:LoadDB(s:c.autoloading_db_file)

    let new_runtime_paths=map(copy(a:opts.new_runtime_paths), 'vam#normpath(v:val)')

    if !exists('s:toscan')
      let s:toscan=[]
      let s:toautoload=[]
      let s:toscanfiles={}
    endif

    call map(copy(new_runtime_paths), 'add(has_key(db.paths, v:val) ? s:toautoload : s:toscan, v:val)')

    for rtp in s:toscan
      let dbitem={'ftplugins': {}, 'syntaxes': {}, 'mappings': {}, 'commands': {}, 'functions': {}, 'abbreviations': {},
            \     'autocommands': {}, 'ftdetects': []}
      call map(vam#GlobInDir(rtp, 'plugin/**/*.vim'), 'extend(s:toscanfiles, {v:val : rtp})')

      for file in vam#GlobInDir(rtp, 'ftplugin/{*/,}*.vim')
        let filetype=substitute(file, '.*ftplugin/\v([^/_]+%(%(_[^/]*)?\.vim$|\/[^/]+$)@=).*', '\1', 'g')
        let file=vam#normpath(file)
        call s:addlistitem(dbitem.ftplugins, filetype, file)
        call s:addlistitem(db.ftplugins, filetype, file)
      endfor

      for file in vam#GlobInDir(rtp, 'syntax/{*/,}*.vim')
        let filetype=substitute(file, '.*syntax/\v([^/]+%(\.vim$|\/[^/]+$)@=).*', '\1', 'g')
        let file=vam#normpath(file)
        call s:addlistitem(dbitem.syntaxes, filetype, file)
        call s:addlistitem(db.syntaxes, filetype, file)
      endfor

      let dbitem.ftdetects=map(vam#GlobInDir(rtp, 'ftdetect/*.vim'), 'vam#normpath(v:val)')

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
          let [cmd, param, range]=matchlist(line, '\v(\S+)\ +([01*?+])\ {4}(\S*)', 3)[1:3]
          "         ┌ bang field              ┌ nargs field
          "         │ ┌ command field         │     ┌ range field
          let start=3+(max([len(cmd), 11])+1)+(1+4)+(max([len(range), 5])+1)
          let completion=matchstr(line, '\S\+', start)
          let exe=matchstr(line, '\S.*', start+len(completion))
          let state.commands[cmd]={'param': param, 'range': range, 'completion': completion, 'command': exe}
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
          elseif line =~# '\v^\w+$'
            let augroup=0
            let auevent=line
          endif
          let state.autocommands[(augroup is 0 ? '': augroup.'#').auevent]={'group': augroup, 'event': auevent}
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

      fun! s:SourcePlugin(path)
        let file=vam#normpath(a:path)
        let saved_eventignore=&eventignore
        set eventignore+=SourceCmd
        if has_key(s:toscanfiles, file)
          let oldstate=s:RecordState()
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
        autocmd! SourceCmd * nested :call s:SourcePlugin(expand('<amatch>'))
      augroup END
    endif

    return call(s:old_handle_runtimepaths, [a:opts], {})
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
