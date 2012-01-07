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
TESTS+=( hg svn tar tgz tgz2 tbz tbz2 zip vba vmb vgz vbz archive_name )
TESTS+=( mis mhg )
for t in $TESTS ; do
local ANAME=vam_test_$t
#▶2 activate
cat > activate-$t.in <<EOF
:call vam#ActivateAddons("$ANAME")
:call WriteGlob()
EOF
addtofile activate-$t.ok init.ok files-$t.lst
#▶2 activate-vimrc
cat > activate-vimrc-$t.vim << EOF
call vam#ActivateAddons("$ANAME")
EOF
cat > activate-vimrc-$t.in << EOF
:call WriteGlob()
EOF
cp activate-$t.ok activate-vimrc-$t.ok
#▶2 install
cat > install-$t.in <<EOF
:runtime! autoload/vam.vim
:InstallAddons $ANAME
:call WriteGlob()
EOF
addtofile install-$t.ok init.ok files-$t.lst
#▶2 uninstall
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
#▲2
done
#▶1 Update
UPDATETGZ2HEADER="\
:let desc=copy(g:vim_addon_manager.plugin_sources.vam_test_tgz2)
:let desc.version='0.1.8'
:let desc.url=desc.url[:-5].'-nodoc.tar.bz2'
:let patch={'vam_test_tgz2': desc}"
#▶2 Update activate plugin
T=update-tgz2
cp activate-tgz2.in $T.in
cat >> $T.in << EOF
$UPDATETGZ2HEADER
:UpdateAddons
y
:call WriteGlob()
EOF
addtofile $T.ok install-tgz2.ok init.ok files-tgz2-updated.lst
#▶2 Update not activated plugin
T=update-tgz2-not_active
cp install-tgz2.in $T.in
cat >> $T.in << EOF
$UPDATETGZ2HEADER
:UpdateAddons vam_test_tgz2
:call WriteGlob()
EOF
addtofile $T.ok install-tgz2.ok init.ok files-tgz2-updated.lst
#▶2 Be sure that not active plugin is not updated
T=noupdate-tgz2-not_active
cp install-tgz2.in $T.in
cat >> $T.in << EOF
$UPDATETGZ2HEADER
:UpdateAddons
y
:call WriteGlob()
EOF
addtofile $T.ok install-tgz2.ok install-tgz2.ok
#▶2 Check do_diff: 1
T=update-tgz2-dodiff
cp activate-tgz2.in $T.in
cat >> $T.in << EOF
:let desc=copy(g:vim_addon_manager.plugin_sources.vam_test_tgz2)
:let desc.version='0.1.8'
:let desc.archive_name=matchstr(desc.url, '\v[^/]+$')
:let desc.url=desc.url[:-5].'-2.tgz'
:let patch={'vam_test_tgz2': desc}
:let file=g:vim_addon_manager.plugin_root_dir."/vam_test_tgz2/plugin/frawor.vim"
:let g:vim_addon_manager.do_diff=1
:execute "edit ".fnameescape(file)
:%s/^"/#!
:write!
:set autoread
:UpdateAddons
y
:call WriteGlob()
:edit!
qaq
:g/^"/yank A
:call WriteFile(split(@a, "\n"))
EOF
addtofile $T.ok install-tgz2.ok <(cat install-tgz2.ok | \
                       perl -pe '$_.="$1.orig\n"if/^(.*plugin.frawor\.vim)$/') \
                comments-tgz2-dodiff.lst
# addtofile $T.ok install-tgz2.ok install-tgz2.ok comments-tgz2-dodiff.lst
#▶2 Check do_diff: 0
T=update-tgz2-nodiff
cat update-tgz2-dodiff.in | grep -v 'do_diff' > $T.in
addtofile $T.ok install-tgz2.ok install-tgz2.ok comments-tgz2-nodiff.lst
#▶1 Use cloned vam-test-known
for test in *.in ; do
    cp -r vam-init vam-$test:r
done
#▲1
cat > init.in << EOF
:call WriteGlob()
EOF
#▶1 Add `:source addmessages.vim'
for f in *.in ; do
    cat >> $f <<< $':source addmessages.vim\n'
done
#▲1
# vim: fmr=▶,▲ fenc=utf-8 et ts=4 sts=4 sw=4 ft=zsh cms=#%s
