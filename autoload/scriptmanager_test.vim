
let s:plugin_root_dir = fnamemodify(expand('<sfile>'),':h:h:h')

" called by vim-addon-manager-test.sh
fun! scriptmanager_test#Test()
  let test_dir = '/tmp/vim-addon-manager-test'

  exec '!rm -fr ' test_dir
  exec '!mkdir -p ' test_dir
  exec '!cp -r'  s:plugin_root_dir test_dir

  " keep it simple:
  let g:vim_script_manager['activated_plugins']['vim-addon-manager-known-repositories'] = 1
  let plugin_sources = g:vim_script_manager['plugin_sources']

  " test mercurial
  call feedkeys("y")
  let plugin_sources['vimstuff'] = { 'type': 'hg', 'url': 'http://vimstuff.hg.sourceforge.net:8000/hgroot/vimstuff/vimstuff' }
  call scriptmanager#Activate(["vimstuff"])

  " test git
  call feedkeys("y")
  let plugin_sources['vim-addon-views'] = { 'type' : 'git', 'url' : 'git://github.com/MarcWeber/vim-addon-views.git' }
  call scriptmanager#Activate(["vim-addon-views"])

  " test subversion
  call feedkeys("y")
  let plugin_sources['vim-latex'] = { 'type': 'svn', 'url': 'https://vim-latex.svn.sourceforge.net/svnroot/vim-latex/trunk/vimfiles'}
  call scriptmanager#Activate(["vim-latex"])

endf

" scriptmanager_util#Unpack tests

" test: . = all tests
" tar$ = onnly the tar test
fun! scriptmanager_test#TestUnpack(test) abort
  let tests = {
      \  'tar':  ['autocorrect', ['README', 'archive', 'archive/autocorrect.tar', 'autocorrect.dat', 'autocorrect.vim', 'generator.rb', 'version'] ],
      \  'tar.gz': ['ack', ['archive', 'doc', 'doc/ack.txt', 'plugin', 'plugin/ack.vim', 'version']],
      \  'tgz': ['VIlisp', ['README', 'VIlisp-hyperspec.pl', 'VIlisp.vim', 'changelog', 'funnel.pl', 'lisp-thesaurus', 'make-lisp-thes.pl', 'archive', 'version']],
      \  'tar.bz2': ['DetectIndent',  ['archive', 'doc', 'doc/detectindent.txt', 'plugin', 'plugin/detectindent.vim', 'version']],
      \  'tbz2': ['xterm16', ['ChangeLog', 'archive', 'cpalette.pl', 'version', 'xterm16.ct', 'xterm16.schema', 'xterm16.txt', 'xterm16.vim']],
      \  'vim_ftplugin': ['srec1008', ['archive', 'archive/srec.vim', 'ftplugin', 'ftplugin/srec.vim', 'version']],
      \  'vba': ['Templates_for_Files_and_Function_Groups',  ['archive', 'archive/file_templates.vba', 'plugin', 'plugin/file_templates.vim', 'templates', 'templates/example.c', 'version', 'templates/example.h']],
      \  'vba.gz': ['gitolite', ['archive', 'ftdetect', 'ftdetect/gitolite.vim', 'syntax', 'syntax/gitolite.vim', 'version']],
      \  'vba.bz2': ['winmanager1440',['archive', 'doc', 'doc/tags', 'doc/winmanager.txt', 'plugin', 'plugin/start.gnome', 'plugin/start.kde', 'plugin/winfileexplorer.vim', 'plugin/winmanager.vim', 'plugin/wintagexplorer.vim', 'version']]
      \  }

  let tmpDir = scriptmanager_util#TempDir("vim-addon-manager-test")

  call scriptmanager2#LoadKnownRepos()

  for [k,v] in items(tests)
    if k !~ a:test | continue | endif
    call scriptmanager_util#RmFR(tmpDir)
    let dict = g:vim_script_manager['plugin_sources'][v[0]]
    call scriptmanager2#Checkout(tmpDir, dict)
    let files = split(glob(tmpDir.'/**'),"\n")
    " replace \ by / on win and remove tmpDir prefix
    call map(files, 'substitute(v:val,'.string('\').',"/","g")['.(len(tmpDir)+1).':]')
    call sort(files)
    call sort(v[1])
    if v[1] != files
      echoe "test failure :".k
      echoe 'expected :'.string(v[1])
      echoe 'got : '.string(files)
      debug echoe 'continue'
    endif
  endfor
endf
