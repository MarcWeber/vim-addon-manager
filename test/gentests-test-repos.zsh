#!/bin/zsh
emulate -L zsh
#▶1 Clone vam-test-known
FOREGROUND=1 \
mkdir vam-init
vimcmd -u $VIMRC \
       --cmd 'let g:curtest="init"' \
       -c 'call vam#ActivateAddons("vam-test-known")' \
       -c 'qa!'
function addtofile()
{
    target=$1
    shift
    (( $# )) || return
    if ! test -e $1 ; then
        shift
        addtofile $target $@
        return
    fi
    if test -e $target ; then
        echo >> $target
        cat $1 >> $target
    else
        cp $1 $target
    fi
    shift
    for file in $@ ; do
        test -e $file || continue
        echo      >> $target
        cat $file >> $target
    done
}
#▶1 Simple unpack tests
typeset -a TESTS
(( ISWINE )) || TESTS+=( git bzr )
(( ISWINE )) && sed -r -i -e 's:/:\\:g' files-*.lst
TESTS+=( hg svn tar tgz tgz2 tbz tbz2 zip vba vgz vbz archive_name )
for t in $TESTS ; do

local ANAME=vam_test_$t

cat > activate-$t.in <<EOF
:call vam#ActivateAddons("$ANAME")
:call WriteGlob()
EOF
addtofile activate-$t.ok init.ok files-$t.lst

cat > install-$t.in <<EOF
:runtime! autoload/vam.vim
:InstallAddons $ANAME
:call WriteGlob()
EOF
addtofile install-$t.ok init.ok files-$t.lst

cp install-$t.in uninstall-$t.in
cat >> uninstall-$t.in << EOF
:UninstallNotLoadedAddons $ANAME
y
:call WriteGlob()
EOF
addtofile uninstall-$t.ok install-$t.ok init.ok
if test -e dependencies-$t.lst ; then
    for dep in $(< dependencies-$t.lst) ; do
        addtofile uninstall-$t.ok files-$dep.lst
    done
fi

done
#▶1 Use cloned vam-test-known
for test in *.in ; do
    cp -r vam-init vam-$test:r
done
#▲1
cat > init.in << EOF
:call WriteGlob()
EOF
