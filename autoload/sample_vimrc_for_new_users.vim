" kept recoding the same things over and over again.
" So I write what I think is useful to you here.
"
" How to use?
" Either copy paste contents into your .vimrc (omitting the Load function)
" or call the load function


" these markers { { { enable folding. see modeline at the bottom
" You don't have to close them if you append the folding level.

" set nocompatible should be default. This should be the first line:
set nocompatible


" You should have this in your .vimrc: 
" (The {{ { starts a fold.
" type zR to open all or za to open one fold only
" zM folds everything again

" enable filetype, plugin and syntax support {{{1
" This means 
filetype indent plugin on | syn on

" allow buffers to go in background without saving etc.
set hidden

" useful mappings: {{{1

" open this file fast so that you can take notes below the line "finish" and
" add more mappings:
noremap \c :e ~/.vimrc<cr>

" :w! is always bad to type. So create your own mapping for it. Example:
noremap \w :w!<cr>

" you may want to remove the <c-d> if you have many files opened
" This switches buffers
" Note: :b foo  will also select some-foo-text.txt file if it was opened :)
noremap \b :b<space><c-d>

" being able to open the help fast is always fine.
" note that you can use tab / shift -tab to select next / previous match
" also glob patterns are allowed. Eg :h com*func<tab>
noremap \h :h<space>

" open one file, use tab and shift-tab again if there are multiple files
" after using this mapping the command line should have started showing
" :e **/*  . Eg use :e **/*fil*txt to match file.txt in any subdir
noremap \e :e<space>**/*

" open multiple files at once. Eg add .txt to open all .txt files
" Using :bn @: you can cycle them all
" :bn = :bnext  @: repeats last command
noremap \n :n<space>**/*

" open a filetype file. Those files are sourced by Vim to setup filetype
" specific mappings
noremap \ft :exec 'e ~/.vim/ftplugin/'.&filetype.'_you.vim'<cr>

" foreign plugin vim-addon-manager {{{1

" commenting this code because I assume you already have it in your ~/.vimrc:

  " tell Vim where to find the autoload function:
"  set runtimepath+=~/vim-plugins/vim-addon-manager

" Activate the addons called 'JSON', 'name1', 'name2'
" This adds them to runtimepath and ensures that plugin/* and after/plugin/*
" files are sourced. JSON is not that important. It highlights the
" NAME-addon-info.txt files. Probably you want to substitude nameN by plugins
" such as snipMate, tlib etc.

" call scriptmanager#Activate(['JSON',"tmru","matchit.zip","vim-dev-plugin","name1","name2"])
" JSON: syntax highlighting for the *info* files
" tmru: list of most recentely used files
" matchit.zip: make % (match to mathing items such as opening closing parenthesis) even smarter
" vim-dev-plugin: smarter omni completion and goto autoload function for VimL scripts

" foreign plugins tlib {{{1

" this is from tlib. I highly recommend having a look at that library.
" Eg its plugin tmru (most recently used files) provides the command
" TRecentlyUsedFiles you can map to easily:
noremap \r :TRecentlyUsedFiles<cr>

" disable some plugins. Maybe you don't want all..
" (Maybe this step is no longer necessary. Tom Link split the library of the
" plugins. So you have to activate the plugins individually istead of
" disabling those you don't want.
let loaded_cmdlinehelp=1
let loaded_concordance=1
let loaded_evalselection=1
let loaded_glark=1
let loaded_hookcursormoved=1
let loaded_linglang=1
let loaded_livetimestamp=1
let loaded_localvariables=1
let loaded_loremipsum=1
let loaded_my_tinymode=1
let loaded_netrwPlugin=1
let loaded_pim=1
let loaded_quickfixsigns=1
let loaded_scalefont=1
let loaded_setsyntax=1
let loaded_shymenu=1
let loaded_spec=1
let loaded_tassert=1
let loaded_tbak=1
let loaded_tbibtools=1
let loaded_tcalc=1
let loaded_tcomment=1
let loaded_techopair=1
let loaded_tgpg=1
let loaded_tlog=1
let loaded_tmarks=1
let loaded_tmboxbrowser=1
let loaded_tmru=1
let loaded_tortoisesvn=1
let loaded_tregisters=1
let loaded_tselectbuffer=1
let loaded_tselectfile=1
let loaded_tsession=1
let loaded_tskeleton=1
let loaded_tstatus=1
let loaded_ttagcomplete=1
let loaded_ttagecho=1
let loaded_ttags=1
"let loaded_ttoc=1
let loaded_viki=1
let loaded_vikitasks=1



" dummy func to enabling you to load this file after adding the top level {{{1
" dir to runtimepath using :set runtimpeth+=ROOT
fun! sample_vimrc_for_new_users#Load()
  " no code. If this function is called this file is sourced
endf

finish

DON'T MISS THESE {{{1

c-x c-f : file completion
c-x c-l : line completion
c-n     : kind of keyword completion - completes everything found in all opened buffers.
          So maybe even consider openining many files uing :n **/*.ext
all: :h ins-completion


movements:

vimtutor tells you to use hjkl. But the speedup using Vim comes using the
appropriate movement command - which is seldomly hjkl.

Skim :h motion.txt

use search / ? to place cursor. Remember that typing a word is not always the
              most efficient way. Eg try /ys t this. And you'll get excatly
              one match in the whole document.

c-o c-i : jump list history

g;      : where did I edit last (current buffer) - you can repeat it

Learn about w vs W. Try it CURSOR_HERE.then.type.it (same for e,E)

f,F,t,T : move to char or just before it forward / backward current line. (A
          must)

How to get O(1) access to your files you're editing at the moment {{{1

Yes :b name is fine, cause it matches HeHiname.ext. Still too much to type.
Usually you work with only a set of buffers. Open them in tabs. Add something
like this to your .vimrc so that you can switch buffers using m-1 m-2 etc:

  " m-X key jump to tab X
  for i in range(1,8)
    exec 'map <m-'.i.'> '.i.'gt'
  endfor

  " faster novigation in windows:
  for i in ["i","j","k","l","q"]
    exec 'noremap <m-s-'.i.'> <c-w>'.i
  endfor

The ways to optimize code navigation are endless. Watch yourself.
If you think something takes too long - optimize it.


MY COMMENTS ABOUT VIM AND ITS USAGE {{{1
========================================
Vim is ignoring this text after finish.


I like Vim cause its that fast and easy to extend.
I also learned that VimL is a nice language. It was ahead of time when it
was invented. However today it can be considered limiting in various ways.
Eg you don't want to write parsers in it. Its too slow for those use cases.
Yet its powerful enough to make everydays work easier - even competitive to
bloated IDEs. Example plugins you should know about:

- tlib library

- snipmate (or xptemplate): Insert text snippets. Its not only about speed.
  Snippets are a nice way to organize your memos.

- matchit: match everything, eg matching xml tags, fun -> return -> endfun
  statements (same for for, while etc)

- The_NERD_tree: directory tree in Vim. You can easily hit the limits of
  Vim/VimL here whene opening large directories it takes a way too long :-(
  Yet you may find it useful.

- commenting plugins

- ... (You want a plugin added here?)

What you should know about:
- :h motion.txt (skim it once)
- Vim keeps history as tree.
- :h quickfix (load compiler output into an error list)
- how to use tags - because this (sometimes fuzzzy) thing
  is still fast to setup and works very well for many use cases.
- Vim can assist you in spelling


most important mappings / commands:
g;  = jump back in list of last edited locations
<c-o> <c-i> = jump back and forth in location list
<c-^> = toggle buffers

q:, ?:, /: : Open mini buffer to browse or edit command or search history
             You can open this from command line using <c-f>!
... I could keep writing for 2 hours now at least.


I'm also aware of Emacs emulating most important editing features of Vim.
Eg there is the vimpulse plugin for Emacs. So I know that I should use the
tool which is best for a given task. This can be Vim for coding. But for debugging
you may prefer Emacs or a bloated IDE such as Eclipse, Netbeans, IDEA (which all have 
vim like keybindgs!).

What are the limitations causing greatest impact to software developers using Vim?
- no async communication support unless you depend on client-server feature
  which requires X. This means Vim will hang until an operation has finished
  when interfacing with external tools.
  Impact: People tried writing debugger features. But all solutions are kind
  of doomed unless Vim gets a nice async communication interface.
  There is a patch: http://github.com/bartman/vim/wiki/_pages. But I'm not
  sure its complete yet
  
- Many coding helpers should not have been written in VimL. They should have
  been written in a proper language so that all open source editors can
  benefit from their features. An Example is the broken PHP completion which
  doesn't even complete static member functions like A::foo();

  Examples how this can be done better:
  * vim-addon-scion (Haskell development helper app is written in Haskell. Vim
    is only a coding editor backend)
  * codefellow (same for Scala).

Vim can be one of the fastest editors you'll start to love (and hate for some
of the shortcomings)


" additional resources - how to continue learning about Vim? {{{1
The way to start learning Vim:
vimtutor

additional advanced info:
http://github.com/dahu/LearnVim

Vim Wiki:
http://vim.wikia.com

join #vim (irc.freenode.net)

join the mailinglist (www.vim.org -> community)

Tell me to add additional resources here


" this modeline tells vim to enable folding {{{1
" vim: fdm=marker 
