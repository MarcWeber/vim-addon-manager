#!/bin/sh

case "$1" in
  test)
  ;;
  *)
    echo "this tests installation of various plugins"
    echo "usage: vim-addon-manager-test.sh test"
    exit 1
  ;;
esac

set -e -x

root=$(dirname $0)
test_dir='/tmp/vim-addon-manager-test'

[ -e $test_dir ] && rm -fr $test_dir || true
mkdir -p $test_dir

cp -r $root $test_dir/vim-addon-manager

cat >> $test_dir/.vimrc << EOF
set nocompatible
set runtimepath+=${test_dir}/vim-addon-manager
call sample_vimrc_for_new_users#Load()

let opts = {'auto_install' : 1 }

" test mercurial
" test git
" test subversion
call vam#ActivateAddons(["Translit3","vim-addon-views","vim-latex"], opts)

function CheckAll()
   let res = [
   \ exists(':Tr3Command') > 0,
   \ exists('g:vim_views_config'),
   \ exists('*AddSyntaxFoldItem')
   \ ]
   echoe string(res)
   call writefile(res, '${test_dir}/result.txt')
endfun

EOF

# yes necessary for enabling known repositories and
# continuing after nasty "press enter to continue lines .."
test_dir='/tmp/vim-addon-manager-test'
yes | vim  -u $test_dir/.vimrc -U /dev/null -c ':call CheckAll()|qa!'

echo "should be an aray cotaining 1 values only. 0 means failure"
cat ${test_dir}/result.txt
