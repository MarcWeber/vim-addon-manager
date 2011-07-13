#!/bin/zsh
emulate -L zsh
#▶1 Clone vam-test-known
FOREGROUND=1 \
mkdir vam-init
vimcmd -u $VIMRC \
       --cmd 'let g:curtest="init"' \
       -c 'call vam#ActivateAddons("vam-test-known")' \
       -c 'qa!'
#▶1 Simple unpack tests
typeset -a TESTS
(( ISWINE )) || TESTS+=( git bzr )
TESTS+=( hg svn tar tgz tgz2 tbz tbz2 zip vba vgz vbz archive_name )
for t in $TESTS ; do

cat > activate-$t.in <<EOF
:call vam#ActivateAddons("vam_test_$t")
:call WriteGlob()
EOF

done
#▶1 Use cloned vam-test-known
for test in *.in ; do
    cp -r vam-init vam-$test:r
done
#▲1
cat > init.in << EOF
:call WriteGlob()
EOF
