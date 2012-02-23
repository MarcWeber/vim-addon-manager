" minimal useful unbiased recommended .vimrc: http://vim.wikia.com/wiki/Example_vimrc


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
" specific mappings. Eg use it for defining commands / mappings which apply
" for python or perl files only
" eg command -buffer DoStuff call DoStuff()
" or map <buffer> \dostuff :call DoStuff()<cr>
noremap \ft :exec 'e ~/.vim/after/ftplugin/'.&filetype.'_you.vim'<cr>

" when pasting code you may want to enable paste option so that Vim doesn't
" treat the pasted text like typed text. Typed text casues vim to to repeating
" comments and change indentation - when pasting you don't want this.
noremap \ip :set invpaste<bar>echo &paste ? 'pasting is on' : 'pasting is off'

" for windows: make backspace work. Doesn't hurt on linux. This should be
" default!
set bs=2

" foreign plugin vim-addon-manager {{{1

" commenting this code because I assume you already have it in your ~/.vimrc:

  " tell Vim where to find the autoload function:
"  set runtimepath+=~/vim-plugins/vim-addon-manager

" Activate the addons called 'JSON', 'name1', 'name2'
" This adds them to runtimepath and ensures that plugin/* and after/plugin/*
" files are sourced. JSON is not that important. It highlights the
" NAME-addon-info.txt files. Probably you want to substitude nameN by plugins
" such as snipMate, tlib etc.

" call vam#ActivateAddons(['JSON',"tmru","matchit.zip","vim-dev-plugin","name1","name2"])
" JSON: syntax highlighting for the *info* files
" tmru: list of most recentely used files
" matchit.zip: make % (match to mathing items such as opening closing parenthesis) even smarter
" vim-dev-plugin: smarter omni completion and goto autoload function for VimL scripts

" foreign plugins tlib {{{1

" this is from tlib. I highly recommend having a look at that library.
" Eg its plugin tmru (most recently used files) provides the command
" TRecentlyUsedFiles you can map to easily:
noremap \r :TRecentlyUsedFiles<cr>

" simple glob open based on tlib's List function (similar to TCommand or fuzzy
" plugin etc)

" don't ask me why glob() from Vim is that slow .. :(
" one reason is that it doesn't follow symlinks (unless you pass -L to find)
fun! FastGlob(glob)
  let g = '^'.a:glob.'$'
  let replace = {'**': '.*','*': '[^/\]*','.': '\.'}
  let g = substitute(g, '\(\*\*\|\*\|\.\)', '\='.string(replace).'[submatch(1)]','g')
  let cmd = 'find | grep -e '.shellescape(g)
  " let exclude = a:exclude_pattern == ''? '' : ' | grep -v -e '.shellescape(a:exclude_pattern)
  " let cmd .= exclude
  return system(cmd)
endf
noremap \go :exec 'e '. fnameescape(tlib#input#List('s','select file', split(FastGlob(input('glob pattern, curr dir:','**/*')),"\n") ))<cr>

" sometimes when using tags the list is too long. filtering it by library or
" such can easily be achived by such code: {{{'
    fun! SelectTag(regex)
      let tag = eval(tlib#input#List('s','select tag', map(taglist(a:regex), 'string([v:val.kind, v:val.filename, v:val.cmd])')))
      exec 'e '.fnameescape(tag[1])
      exec tag[2]
    endf
    command!-nargs=1 TJump call SelectTag(<f-args>)

" }}}
" select a buffer from list
command! SelectBuf exec 'b '.matchstr( tlib#input#List('s', 'select buffer', tlib#cmd#OutputAsList('ls')), '^\s*\zs\d\+\ze')
noremap! \sb :SelectBuf<cr>

" dummy func to enabling you to load this file after adding the top level {{{1
" dir to runtimepath using :set runtimpeth+=ROOT
fun! sample_vimrc_for_new_users#Load()
  " no code. If this function is called this file is sourced
  " As alternative this can be used:
  " runtime autoload/sample_vimrc_for_new_users.vim
endf

" create directory for files before Vim tries writing them:
augroup CREATE_MISSING_DIR_ON_BUF_WRITE
  au!
  autocmd BufWritePre * if !isdirectory(expand('%:h')) | call mkdir(expand('%:h'),'p') | endif
augroup end

finish
Vim is ignoring this text after finish.

DON'T MISS THESE {{{1

Each vim boolean setting can be off or on. You can invert by invNAME. Example:
enable setting:  :set swap 
disable setting: :set noswap 
toggle setting:  :set invswap
Settings can be found easily by :h '*chars*'<c-d>

== typing characters which are not on your keyboard ==
digraphs: type chars which are untypable, for example:
c-k =e  : types € (see :h digraph)

== completions ==
c-x c-f : file completion
c-x c-l : line completion
c-n     : kind of keyword completion - completes everything found in all opened buffers.
          So maybe even consider openining many files uing :n **/*.ext
          (if you're a nerd get vim-addon-completion and use the camel case buffer completion found in there)
all: :h ins-completion

== most important movement keys ==
hjkl - as experienced user you'll notice that you don't use them that often.
So you should at least know about the following and have a look at :h motion.txt
and create your own by mappings

how to reach insert mode:
| is cursor location

    O
I  i|a  A
    o

important movements and their relation:

       gg                       
     <c-u>                      H (top line window)

-      k                        
0    h | l   $                  M
<cr>   j
     <c-v>
                                L
       G


movements:

use search / ? to place cursor. Remember that typing a word is not always the
              most efficient way. Eg try /ys t this. And you'll get excatly
              one match in the whole document.

c-o c-i : jump list history

g;      : where did I edit last (current buffer) - you can repeat it

Learn about w vs W. Try it CURSOR_HERE.then.type.it (same for e,E)

f,F,t,T : move to char or just before it forward / backward current line. (A
          must)

be faster: delete then goto insert mode:
C: deletes till end of line
c a-movement-action: deletes characters visited while moving

more movements:
(, ): move by sentence
[[, ]], {, } : more blockwise movements which are often helpful
...

This script may also have its usage: Jump to charater location fast:
http://www.vim.org/scripts/script.php?script_id=3437

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

Bindings in command line are shitty?
yes - remap them - or use "emacscommandline" plugin which does this for you.
or use q: (normal mode) or c-f in commandline



== indentation, spaces, tabs ==
Tab: default behavior of vim is: add &tabstop spaces unless expandtab is not
set. You can always insert real tabs by <c-v><tab>. However tabstob should be
treated as display setting. Use sw setting and c-t, c-d instead.

c-t: increase indentation
c-d: decrease indentation
c-f: auto indent current line (requires indentation setup)
:setlocal sw=4: use 4 spacse for indentation
:setlocal expandtab: expand tab to spaces (default)
>3j . .  increase indentation of 3 lines and repeat two times
:setlocal tabstop: a tab is viewed as how many spaces in a file?

:set list  : displays spaces and tabs

project specific settings: see vim-addon-local-vimrc



MY COMMENTS ABOUT VIM AND ITS USAGE {{{1
========================================


I like Vim cause its that fast and easy to extend.
I also learned that VimL is a nice language. It was ahead of time when it
was invented. However today it can be considered limiting in various ways.
Eg you don't want to write parsers in it. Its too slow for those use cases.
Yet its powerful enough to make everydays work easier - even competitive to
bloated IDEs. Example plugins you should know about:

- tlib library (and all of Tom's plugins

- snipmate (or xptemplate): Insert text snippets. Its not only about speed.
  Snippets are a nice way to organize your memos.

- matchit: match everything, eg matching xml tags, fun -> return -> endfun
  statements (same for for, while etc)

- The_NERD_tree: directory tree in Vim. You can easily hit the limits of
  Vim/VimL here whene opening large directories it takes a way too long :-(
  Yet you may find it useful.

- commenting plugins

- vim-addon-local-vimrc (project specific settings)

- ... (You want a plugin added here?)

What you should know about:
- :h motion.txt (skim it once)
- Vim keeps history as tree. (g+ g- mappings)
- :h quickfix (load compiler output into an error list)
- how to use tags - because this (sometimes fuzzzy) thing
  is still fast to setup and works very well for many use cases.
- Vim can assist you in spelling


most important mappings / commands:
g;  = jump back in list of last edited locations
<c-o> <c-i> = jump back and forth in location list
<c-^> = toggle buffers
c-w then one of v s w q t h j k l (z) : move cursor, split windows, quit buffer

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

  Possible known ways to work around it?

        - vim-addon-async (depends on client-server but works very well)

        - implement windows version of this patch
          http://github.com/bartman/vim.git (which still can be improved a lot)
          and make it it poll file handlers when not typing. Implement a shell 
          like interface. doc: http://github.com/bartman/vim/wiki/_pages
                         
        - There is a patch which let's you start a shell in Vim. I don't think
          it got updated (which is linux only)                                
          http://www.wana.at/vimshell/        
          (Maybe cygwin or such ?) - I never tried it.

        - vimshell (www.vim.org). You have to get a dell or such. I think this
          could satisfy you.                                                  
          (vcs: http://github.com/Shougo/vimshell)

        - screen (see other mail)
          c-a S splits the window
          c-a tab switches focus 
                                
          if you run interpreter this way: tcl | tee log
                                                        
          you may have a chance getting errors into quickfix or such
                                                                    
          (requires cygwin or such - I never tried it on Windows ?) 

          use Emacs and vimpulse (I hate to say it)

  
- Many coding helpers should not have been written in VimL. They should have
  been written in a proper language so that all open source editors can
  benefit from their features. An Example is the broken PHP completion which
  doesn't even complete static member functions like A::foo();

  Examples how this can be done better:
  * vim-addon-scion (Haskell development helper app is written in Haskell. Vim
    is only a coding editor backend)
  * codefellow (same for Scala).
  * eclim (Eclipse features exposed to Vim And Vim backend implementation)

Vim can be one of the fastest editors you'll start to love (and hate for some
of the shortcomings)


" additional resources - how to continue learning about Vim? {{{1
The way to start learning Vim:
vimtutor

additional advanced info:
http://github.com/dahu/LearnVim

Vim Wiki:
http://vim.wikia.com
Checkout its sample .vimrc: http://vim.wikia.com/wiki/Example_vimrc

join #vim (irc.freenode.net)

join the mailinglist (www.vim.org -> community)

Tell me to add additional resources here


" this modeline tells vim to enable folding {{{1
" vim: fdm=marker 
