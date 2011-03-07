fun! scriptmanager#Activate(...) abort
  " historical. Call vam#ActivateAddons instead
  " This codes renames old name scriptmanager#Activate to@vam#ActivateAddons
  " for you. I'd like to ask the uer. But not all are using shells so the
  " question can get lost.
  let cmd='%s@scriptmanager#Activate(@vam#ActivateAddons(@g | %s/\<vim_script_manager\>/vim_addon_manager/g'
  let files = filter([$HOME."/.vimrc",$HOME.'/_vimrc'], 'filereadable(v:val)')
  if len(files) == 1
    echohl WarningMsg
    echomsg "scriptmanager#Actiavte and g:vim_script_manager were renamed to vam#ActivateAddons and g:vim_addon_manager."
    echohl None
    if confirm("Replace given names in ".files[0]."?", "&No\n&Yes")==2
      exec 'e '.fnameescape(files[0])
      exec cmd | w
    endif
  else
    echo "open your the file calling scriptmanager#Activate and run: ".cmd." . Rename happened for consistency"
  endif
  call call(function('vam#ActivateAddons'),a:000)
endf

fun! scriptmanager#DefineAndBind(...)
  echoe "fix your code!, scriptmanager#DefineAndBind was renamed to vam#DefineAndBind(. Drop this function to find the usage location faster!"
  return call(function('vam#DefineAndBind'),a:000)
endf
