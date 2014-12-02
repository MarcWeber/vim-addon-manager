" usage example:
"
" call nix#ExportPluginsForNix({'path_to_nixpkgs': '/etc/nixos/nixpkgs', 'names': ["vim-addon-manager", "vim-addon-nix"], 'cache_file': 'cache'})

fun! nix#ToNixAttrName(s) abort
  return a:s
endf

fun! nix#ToNixName(s) abort
  return substitute(a:s, ':', '-', 'g')
endf

fun! s:System(...)
  let args = a:000
  let r = call call('vam#utils#System', args)
  if r is 0
    throw "command ".join(args, '').' failed'
  else
    return r
  endif
endf

" without deps
fun! nix#NixDerivation(path_to_nixpkgs, name, repository) abort
  let n_a_name = nix#ToNixAttrName(a:name)
  let n_n_name = nix#ToNixName(a:name)
  let type = get(a:repository, 'type', '')
  let created_notice = " # created by nix#NixDerivation"

  if type == 'git'
    " should be using shell abstraction ..
    echo 'fetching '. a:repository.url
    let s = s:System(a:path_to_nixpkgs.'/pkgs/build-support/fetchgit/nix-prefetch-git $', a:repository.url)
    let rev = matchstr(s, 'git revision is \zs[^\n\r]\+\ze')
    let sha256 = matchstr(s, 'hash is \zs[^\n\r]\+\ze')

    return join([
          \ '  "'.n_a_name.'" = buildVimPlugin {'.created_notice,
          \ '    name = "'.n_n_name.'";',
          \ '    src = fetchgit {',
          \ '      url = "'. a:repository.url .'";',
          \ '      rev = "'.rev.'";',
          \ '      sha256 = "'.sha256.'";',
          \ '    };',
          \ '    dependencies = ['.join(map(get(a:repository, 'dependencies', []), "'\"'.nix#ToNixAttrName(v:val).'\"'")).'];',
          \ '  };',
          \ '',
          \ ], "\n")

  elseif type == 'hg'
    " should be using shell abstraction ..
    echo 'fetching '. a:repository.url
    let s = s:System(a:path_to_nixpkgs.'/pkgs/build-support/fetchgit/nix-prefetch-git $', a:repository.url)
    let rev = matchstr(s, 'git revision is \zs[^\n\r]\+\ze')
    let sha256 = matchstr(s, 'hash is \zs[^\n\r]\+\ze')

    return join([
          \ '  "'.n_a_name.'" = buildVimPlugin {'.created_notice,
          \ '    name = "'.n_n_name.'";',
          \ '    src = fetchgit {',
          \ '      url = "'. a:repository.url .'";',
          \ '      rev = "'.rev.'";',
          \ '      sha256 = "'.sha256.'";',
          \ '    };',
          \ '    dependencies = ['.join(map(get(a:repository, 'dependencies', []), "'\"'.nix#ToNixAttrName(v:val).'\"'")).'];',
          \ '  };',
          \ '',
          \ ], "\n")

  elseif type == 'archive'
    let sha256 = split(s:System('nix-prefetch-url $ 2>/dev/null', a:repository.url), "\n")[0]
    return join([
          \ '  "'.n_a_name.'" = buildVimPlugin {'.created_notice,
          \ '    name = "'.n_n_name.'";',
          \ '    src = fetchurl {',
          \ '      url = "'. a:repository.url .'";',
          \ '      name = "'. a:repository.archive_name .'";',
          \ '      sha256 = "'.sha256.'";',
          \ '    };',
          \ '    buildInputs = [ unzip ];',
          \ '    dependencies = ['.join(map(get(a:repository, 'dependencies', []), "'\"'.v:val.'\"'")).'];',
          \ '    meta = {',
          \ '       url = "http://www.vim.org/scripts/script.php?script_id='.a:repository.vim_script_nr.'";',
          \ '    };',
          \ '  };',
          \ '',
          \ ], "\n")
  else
    throw a:name.' TODO: implement source '.string(a:repository)
  endif
endf

" also tries to handle dependencies
fun! nix#AddNixDerivation(path_to_nixpkgs, derivations, name, ...) abort
  if has_key(a:derivations, a:name) | return | endif
  let repository = a:0 > 0 ? a:1 : {}

  if repository == {}
    call vam#install#LoadPool()
    let list = matchlist(a:name, 'github:\([^/]*\)\%(\/\(.*\)\)\?$')
    if len(list) > 0
      if '' != list[2]
        let repository = { 'type': 'git', 'url': 'git://github.com/:'.list[1].'/'.list[2] }
      else
        let repository = { 'type': 'git', 'url': 'git://github.com/'.list[1].'/vim-addon-'.list[1] }
      endif
    else
      let repository = get(g:vim_addon_manager.plugin_sources, a:name, {})
      if repository == {}
        throw "repository ".a:name." unkown!"
      end
    endif
  endif

  " check for dependencies
  let info = vam#ReadAddonInfo(vam#AddonInfoFile(vam#PluginDirFromName(a:name), a:name))
  let dependencies = keys(get(info, 'dependencies', {}))
  for dep in dependencies
    call nix#AddNixDerivation(a:path_to_nixpkgs, a:derivations, dep)
  endfor

  if len(dependencies) > 0
    let repository.dependencies = dependencies
  endif
  let a:derivations[a:name] = nix#NixDerivation(a:path_to_nixpkgs, a:name, repository)
endf

fun! nix#TopNixOptsByParent(parents)
  if (a:parents == [])
    return {'ind': '  ', 'next_ind': '    ', 'sep': "\n"}
  else
    return {'ind': '', 'next_ind': '', 'sep': ' '}
  endif
endf

fun! nix#ToNix(x, parents, opts_fun) abort
  let opts = call(a:opts_fun, [a:parents])
  let next_parents = [a:x] + a:parents
  let seps = a:0 > 1 ? a:2 : []

  let ind = get(opts, 'ind', '')
  let next_ind = get(opts, 'next_ind', ind.'  ')
  let sep = get(opts, 'sep', ind.'  ')

  if type(a:x) == type("")
    return "''". substitute(a:x, '[$]', '$$', 'g')."''"
  elseif type(a:x) == type({})
    let s = ind."{".sep
    for [k,v] in items(a:x)
      let s .= '"'.k.'" = '.nix#ToNix(v, next_parents, a:opts_fun).";".sep
      unlet k v
    endfor
    return  s.ind."}"

    " let s = ind."{\n"
    " for [k,v] in items(a:x)
    "   let s .= next_ind . nix#ToNix(k).' = '.nix#ToNix(v, next_ind)."\n"
    "   unlet k v
    " endfor
    " return  s.ind."}\n"
  elseif type(a:x) == type([])
    let s = ind."[".sep
    for v in a:x
      let s .= next_ind . nix#ToNix(v, next_parents, a:opts_fun)."".sep
      unlet v
    endfor
    return s.ind."]"
  endif
endf


" with dependencies
" opts.names: list of any
"     - string
"     - dictionary having key name or names
" This is so that plugin script files can be loaded/ merged
fun! nix#ExportPluginsForNix(opts) abort
  let path_to_nixpkgs = a:opts.path_to_nixpkgs
  let cache_file = get(a:opts, 'cache_file', '')

  let names = []
  for x in a:opts.names
    if type(x) == type('')
      call add(names, x)
    elseif type(x) == type({}) && has_key(x, 'name')
      call add(names, x.name)
    elseif type(x) == type({}) && has_key(x, 'names')
      call extend(names, x.names)
    else
    endif
    unlet x
  endfor

  let derivations = (cache_file == '' || !filereadable(cache_file)) ? {} : eval(readfile(cache_file)[0])
  let failed = {}
  for name in names
    try
      call nix#AddNixDerivation(path_to_nixpkgs, derivations, name)
    catch /.*/
      echom 'failed : '.name.' '.v:exception
      let failed[name] = v:exception
    endtry
  endfor
  echom join(keys(failed), ", ")
  echom string(failed)

  if cache_file != ''
    call writefile([string(derivations)], cache_file)
  endif

  enew
  for k in sort(keys(derivations))
    call append('$', split(derivations[k],"\n"))
  endfor

  " for VAM users output vam.pluginDictionaries which can be fed to
  " vim_customizable.customize.vimrc.vam.pluginDictionaries
  call append('$', ["", "", "", '# vam.pluginDictionaries'])

  let ns = []
  for x in a:opts.names
    if type(x) == type("")
      call add(ns, nix#ToNixAttrName(x))
    elseif type(x) == type({})
      if has_key(x, 'name')
        call add(ns, extend({'name': nix#ToNixAttrName(x.name)}, x, "keep"))
      elseif has_key(x, 'names')
        call add(ns, extend({'names': map(copy(x.names), 'nix#ToNixAttrName(v:val)')}, x, "keep"))
      else
        throw "unexpected"
      endif
    else
      throw "unexpected"
    endif
    unlet x
  endfor

  call append('$', split(nix#ToNix(ns, [], 'nix#TopNixOptsByParent'), "\n"))

  " failures:
  for [k,v] in items(failed)
    call append('$', ['# '.k.', failure: '.v])
    unlet k v
  endfor
endf
