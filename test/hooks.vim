let s:F={}
function s:F.hook_fun(info, repository, pluginDir, opts)
    let pdir=fnamemodify(a:pluginDir, ':h:t').'/'.
                \fnamemodify(a:pluginDir, ':t')
    call WriteFile('info: '.string(sort(items(a:info))),
                \  'repo: '.string(sort(items(a:repository))),
                \  'pdir: '.string(pdir),
                \  'opts: '.string(a:opts))
endfunction
function s:F.pihook(...)
    call WriteFile('Hook: post-install')
    return call(s:F.hook_fun, a:000, {})
endfunction
function s:F.puhook(...)
    call WriteFile('Hook: post-update')
    return call(s:F.hook_fun, a:000, {})
endfunction
function s:F.Puhook(...)
    call WriteFile('Hook: pre-update')
    return call(s:F.hook_fun, a:000, {})
endfunction
function s:F.pUhook(...)
    call WriteFile('Hook: post-scms-update')
    return call(s:F.hook_fun, a:000, {})
endfunction
function Hook(hook, ...)
    call WriteFile('Plugin hook: '.a:hook)
    return call(s:F.hook_fun, a:000, {})
endfunction
let g:vim_addon_manager.post_install_hook_functions=[s:F.pihook]
let g:vim_addon_manager.post_update_hook_functions=[s:F.puhook]
let g:vim_addon_manager.pre_update_hook_functions=[s:F.Puhook]
let g:vim_addon_manager.post_scms_update_hook_functions=[s:F.pUhook]
call vam#ActivateAddons('vam_test_tgz2')
UpdateActivatedAddons
let desc=copy(g:vim_addon_manager.plugin_sources.vam_test_tgz2)
let desc.version='0.1.8'
let desc.url=desc.url[:-5].'-nodoc.tar.bz2'
let patch={'vam_test_tgz2': desc}
UpdateActivatedAddons
call vam#ActivateAddons('vam_test_hook')
let desc=copy(g:vim_addon_manager.plugin_sources.vam_test_hook)
let desc.version='new'
let desc.url=desc.url[:-5].'-copy.tar.bz2'
let patch.vam_test_hook=desc
UpdateActivatedAddons
