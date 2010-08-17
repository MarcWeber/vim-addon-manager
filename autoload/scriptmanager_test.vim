
let s:plugin_root_dir = fnamemodify(expand('<sfile>'),':h:h:h')

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
