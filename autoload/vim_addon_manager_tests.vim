" scriptmanager_util#Unpack tests

" test: . = all tests
" tar$ = onnly the tar test
fun! vim_addon_manager_tests#Tests(test) abort
  let tests = {
      \  'tar':  ['autocorrect', ['/tmp/vim-addon-manager-test/README', '/tmp/vim-addon-manager-test/archive', '/tmp/vim-addon-manager-test/archive/autocorrect.tar', '/tmp/vim-addon-manager-test/autocorrect.dat', '/tmp/vim-addon-manager-test/autocorrect.vim', '/tmp/vim-addon-manager-test/generator.rb', '/tmp/vim-addon-manager-test/version'] ],
      \  'tar.gz': ['ack', ['/tmp/vim-addon-manager-test/archive', '/tmp/vim-addon-manager-test/doc', '/tmp/vim-addon-manager-test/doc/ack.txt', '/tmp/vim-addon-manager-test/plugin', '/tmp/vim-addon-manager-test/plugin/ack.vim', '/tmp/vim-addon-manager-test/version']],
      \  'tgz': ['VIlisp', ['/tmp/vim-addon-manager-test/VIlisp-2.3', '/tmp/vim-addon-manager-test/VIlisp-2.3/README', '/tmp/vim-addon-manager-test/VIlisp-2.3/VIlisp-hyperspec.pl', '/tmp/vim-addon-manager-test/VIlisp-2.3/VIlisp.vim', '/tmp/vim-addon-manager-test/VIlisp-2.3/changelog', '/tmp/vim-addon-manager-test/VIlisp-2.3/funnel.pl', '/tmp/vim-addon-manager-test/VIlisp-2.3/lisp-thesaurus', '/tmp/vim-addon-manager-test/VIlisp-2.3/make-lisp-thes.pl', '/tmp/vim-addon-manager-test/archive', '/tmp/vim-addon-manager-test/version']],
      \  'tar.bz2': ['DetectIndent',  ['/tmp/vim-addon-manager-test/archive', '/tmp/vim-addon-manager-test/doc', '/tmp/vim-addon-manager-test/doc/detectindent.txt', '/tmp/vim-addon-manager-test/plugin', '/tmp/vim-addon-manager-test/plugin/detectindent.vim', '/tmp/vim-addon-manager-test/version']],
      \  'tbz2': ['xterm16', ['/tmp/vim-addon-manager-test/ChangeLog', '/tmp/vim-addon-manager-test/archive', '/tmp/vim-addon-manager-test/cpalette.pl', '/tmp/vim-addon-manager-test/version', '/tmp/vim-addon-manager-test/xterm16.ct', '/tmp/vim-addon-manager-test/xterm16.schema', '/tmp/vim-addon-manager-test/xterm16.txt', '/tmp/vim-addon-manager-test/xterm16.vim']],
      \  'vim_ftplugin': ['srec1008', ['/tmp/vim-addon-manager-test/archive', '/tmp/vim-addon-manager-test/archive/srec.vim', '/tmp/vim-addon-manager-test/ftplugin', '/tmp/vim-addon-manager-test/ftplugin/srec.vim', '/tmp/vim-addon-manager-test/version']],
      \  'vba': ['Templates_for_Files_and_Function_Groups',  ['/tmp/vim-addon-manager-test/archive', '/tmp/vim-addon-manager-test/archive/file_templates.vba', '/tmp/vim-addon-manager-test/plugin', '/tmp/vim-addon-manager-test/plugin/file_templates.vim', '/tmp/vim-addon-manager-test/templates', '/tmp/vim-addon-manager-test/templates/example.c', '/tmp/vim-addon-manager-test/version', '/tmp/vim-addon-manager-test/templates/example.h']],
      \  'vba.gz': ['gitolite', ['/tmp/vim-addon-manager-test/archive', '/tmp/vim-addon-manager-test/ftdetect', '/tmp/vim-addon-manager-test/ftdetect/gitolite.vim', '/tmp/vim-addon-manager-test/syntax', '/tmp/vim-addon-manager-test/syntax/gitolite.vim', '/tmp/vim-addon-manager-test/version']],
      \  'vba.bz2': ['winmanager1440',['/tmp/vim-addon-manager-test/archive', '/tmp/vim-addon-manager-test/doc', '/tmp/vim-addon-manager-test/doc/tags', '/tmp/vim-addon-manager-test/doc/winmanager.txt', '/tmp/vim-addon-manager-test/plugin', '/tmp/vim-addon-manager-test/plugin/start.gnome', '/tmp/vim-addon-manager-test/plugin/start.kde', '/tmp/vim-addon-manager-test/plugin/winfileexplorer.vim', '/tmp/vim-addon-manager-test/plugin/winmanager.vim', '/tmp/vim-addon-manager-test/plugin/wintagexplorer.vim', '/tmp/vim-addon-manager-test/version']]
      \  }

  let tmpDir = "/tmp/vim-addon-manager-test"

  call scriptmanager2#LoadKnownRepos()

  for [k,v] in items(tests)
    if k !~ a:test | continue | endif
    call scriptmanager_util#RmFR(tmpDir)
    let dict = g:vim_script_manager['plugin_sources'][v[0]]
    call scriptmanager2#Checkout(tmpDir, dict)
    let files = split(glob(tmpDir.'/**'),"\n")
    if v[1] != files
      echoe "test failure :".k
      echoe 'expected :'.string(v[1])
      echoe 'got : '.string(files)
      debug echoe 'continue'
    endif
  endfor
endf
