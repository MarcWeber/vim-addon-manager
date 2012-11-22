" See test/README.txt about how to run this
if !exists('g:curtest') | echoe 'bad usage' | finish |endif

let addons=map(range(4), '"vam-addon-".v:val')
for addon in addons
    let addpath=g:vim_addon_manager.plugin_root_dir.'/'.addon.'/plugin'
    call mkdir(addpath, 'p')
    call writefile(['let g:v'.addon[-1:].'=1'], addpath.'/plugin.vim')
endfor
call vam#ActivateAddons(addons)

let $MYVIMRC=$TESTDIR.'/'.g:curtest.'-vimrc'
call writefile(readfile(fnamemodify($TESTDIR, ':h').'/vimrc', 'b')+
            \  ['call vam#ActivateAddons('.string(addons).')'],
            \  $MYVIMRC)

while getchar(1)
    call getchar(0)
endwhile
call feedkeys('YYYYYYYY', 't')
redir => g:messages
execute 'AddonsBisect '.v:progname.' --cmd let\ g:noexe=1 --cmd let\ g:curtest='.string(g:curtest).' -c if\ exists("g:v2")|BADVAMBisect|else|OKVAMBisect|endif'
redir END
let msglines=split(g:messages, "\n")
call WriteFile(filter(msglines[:-2], 'v:val =~ "\\v^E\\d+\\:"')+msglines[-1:])
qa!
