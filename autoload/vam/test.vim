
let s:plugin_root_dir = fnamemodify(expand('<sfile>'),':h:h:h')

" called by vim-addon-manager-test.sh
fun! vam#test#Test()
  let test_dir = '/tmp/vim-addon-manager-test'

  exec '!rm -fr ' test_dir
  exec '!mkdir -p ' test_dir
  exec '!cp -r'  s:plugin_root_dir test_dir

  " keep it simple:
  let g:vim_addon_manager['activated_plugins']['vim-addon-manager-known-repositories'] = 1
  let plugin_sources = g:vim_addon_manager['plugin_sources']

  " test mercurial
  call feedkeys("y")
  let plugin_sources['vimstuff'] = { 'type': 'hg', 'url': 'http://vimstuff.hg.sourceforge.net:8000/hgroot/vimstuff/vimstuff' }
  call vam#ActivateAddons(["vimstuff"])

  " test git
  call feedkeys("y")
  let plugin_sources['vim-addon-views'] = { 'type' : 'git', 'url' : 'git://github.com/MarcWeber/vim-addon-views.git' }
  call vam#ActivateAddons(["vim-addon-views"])

  " test subversion
  call feedkeys("y")
  let plugin_sources['vim-latex'] = { 'type': 'svn', 'url': 'https://vim-latex.svn.sourceforge.net/svnroot/vim-latex/trunk/vimfiles'}
  call vam#ActivateAddons(["vim-latex"])

endf

" vam#utils#Unpack tests

" test: . = all tests
" tar$ = onnly the tar test
fun! vam#test#TestUnpack(test) abort
  let tests = {
      \  'tar':  ['autocorrect', ['README', 'archive', 'archive/autocorrect.tar', 'autocorrect.dat', 'autocorrect.vim', 'generator.rb', 'version'] ],
      \  'tar.gz': ['ack', ['archive', 'archive/ack.tar.gz', 'doc', 'doc/ack.txt', 'plugin', 'plugin/ack.vim', 'version']],
      \  'tgz': ['VIlisp', ['README', 'VIlisp-hyperspec.pl', 'VIlisp.vim', 'changelog', 'funnel.pl', 'lisp-thesaurus', 'make-lisp-thes.pl', 'archive', 'archive/VIlisp.2.3.tgz', 'version']],
      \  'tar.bz2': ['DetectIndent',  ['archive', 'archive/detectindent-1.0.tar.bz2', 'doc', 'doc/detectindent.txt', 'plugin', 'plugin/detectindent.vim', 'version']],
      \  'tbz2': ['xterm16', ['ChangeLog', 'archive', 'archive/xterm16-2.43.tbz2', 'cpalette.pl', 'version', 'xterm16.ct', 'xterm16.schema', 'xterm16.txt', 'xterm16.vim']],
      \  'vim_ftplugin': ['srec1008', ['archive', 'archive/srec.vim', 'ftplugin', 'ftplugin/srec.vim', 'version']],
      \  'vba': ['Templates_for_Files_and_Function_Groups',  ['archive', 'archive/file_templates.vba', 'plugin', 'plugin/file_templates.vim', 'templates', 'templates/example.c', 'version', 'templates/example.h']],
      \  'vba.gz': ['gitolite', ['archive', 'archive/gitolite.vba.gz', 'ftdetect', 'ftdetect/gitolite.vim', 'syntax', 'syntax/gitolite.vim', 'version']],
      \  'vba.bz2': ['winmanager1440',['archive', 'archive/winmanager.vba.bz2', 'doc', 'doc/tags', 'doc/winmanager.txt', 'plugin', 'plugin/start.gnome', 'plugin/start.kde', 'plugin/winfileexplorer.vim', 'plugin/winmanager.vim', 'plugin/wintagexplorer.vim', 'version']]
      \  }

  let tmpDir = vam#utils#TempDir("vim-addon-manager-test")

  call vam#install#LoadPool()

  for [k,v] in items(tests)
    if k !~ a:test | continue | endif
    call vam#utils#RmFR(tmpDir)
    let dict = g:vim_addon_manager['plugin_sources'][v[0]]
    call vam#install#Checkout(tmpDir, dict)
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

" tests that creating and applying diffs when updating archive plugins (found
" on www.vim.org) works as expected.
fun! vam#test#TestUpdate(case) abort
  call vam#install#LoadPool()
  let tmpDir = vam#utils#TempDir("vim-addon-manager-test")
  let plugin_name = "www_vim_org_update_test"
  let plugin_source_file = tmpDir.'/'.plugin_name.'.vim'
  let installDir = vam#PluginDirByName(plugin_name)
  let installCompareDir = vam#PluginDirByName(plugin_name.'-1.0') 
  silent! unlet  g:vim_addon_manager['activated_plugins'][plugin_name]
  for dir in [tmpDir, installDir, installCompareDir]
    if isdirectory(dir) | call vam#utils#RmFR(dir) | endif
  endfor
  call mkdir(tmpDir.'/plugin','p')

  let file_v1          = ["version 1.0", "1", "2", "3", "4", "5" ]
  let file_v1_patched  = ["version 1.0", "1", "2", "3", "4", "patched" ]
  let file_v2          = ["version 2.0", "1", "2", "3", "4", "5" ]
  let file_v2_patched  = ["version 2.0", "1", "2", "3", "4", "patched" ] 


  let file_v2_conflict          = ["version 2.0", "1", "2", "3", "4", "conflicting line" ]

  " install v1
  call writefile( file_v1, plugin_source_file, 1)
  let g:vim_addon_manager['plugin_sources'][plugin_name] = {'type': 'archive', 'url': 'file://'.plugin_source_file, 'version' : '1.0' , 'script-type': 'plugin' }
  exec 'ActivateAddons '.plugin_name

  " patch
  call writefile( file_v1_patched, installDir.'/plugin/'.plugin_name.'.vim', 1)

  if a:case == "normal"

    " update to v2
    call writefile( file_v2, plugin_source_file, 1)
    let g:vim_addon_manager['plugin_sources'][plugin_name] = {'type': 'archive', 'url': 'file://'.plugin_source_file, 'version' : '2.0' , 'script-type': 'plugin' }
    exec 'UpdateAddons '.plugin_name

    " verify that the patch is still present
    if file_v2_patched != readfile( installDir.'/plugin/'.plugin_name.'.vim', 1)
      echoe "test failed"
    endif

  elseif a:case == "conflict"
    " manual test: diff file should be kept
    " update to v2 conflict
    call writefile( file_v2_conflict, plugin_source_file, 1)
    let g:vim_addon_manager['plugin_sources'][plugin_name] = {'type': 'archive', 'url': 'file://'.plugin_source_file, 'version' : '2.0' , 'script-type': 'plugin' }
    exec 'UpdateAddons '.plugin_name
  else
    throw "unknown case"

  endif
endfun
" vim: et ts=8 sts=2 sw=2
