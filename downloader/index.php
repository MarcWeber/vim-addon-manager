<?php

putenv('PATH=/var/run/current-system/sw/bin');

set_time_limit(60*15);

ob_start();

define('TMP', '/tmp/vam-downloader');
define('HISTORY_FILE', 'previous_downloads.txt');

define('NAME_CACHE_FILE', 'name_cache');
define('RECREATE_CACHE_HOURS', 48 * 2);


$windows = (isset($_POST['target_os']) && $_POST['target_os']) == 'windows';

function name_cache(){
  $a = json_decode(file_get_contents(NAME_CACHE_FILE), true);
  ksort($a);
  return $a;
}

function _htmlentities($s){
	return htmlentities($s, ENT_QUOTES, "UTF-8" );
}

function downloadFile( $fullPath, $name = '' ){

  if ($name == '')
    $name = basename($fullPath);

  // Must be fresh start
  if( headers_sent() )
    die('Headers Sent');

  // Required for some browsers
  if(ini_get('zlib.output_compression'))
    ini_set('zlib.output_compression', 'Off');

  // File Exists?
  if( file_exists($fullPath) ){

    // Parse Info / Get Extension
    $fsize = filesize($fullPath);
    $path_parts = pathinfo($name);
    $ext = strtolower($path_parts["PATHINFO_EXTENSION"]);

    // Determine Content Type
    switch ($ext) {
      case "pdf": $ctype="application/pdf"; break;
      case "exe": $ctype="application/octet-stream"; break;
      case "zip": $ctype="application/zip"; break;
      case "doc": $ctype="application/msword"; break;
      case "xls": $ctype="application/vnd.ms-excel"; break;
      case "ppt": $ctype="application/vnd.ms-powerpoint"; break;
      case "gif": $ctype="image/gif"; break;
      case "png": $ctype="image/png"; break;
      case "jpeg":
      case "jpg": $ctype="image/jpg"; break;
      default: $ctype="application/force-download";
    }

    header("Pragma: public"); // required
    header("Expires: 0");
    header("Cache-Control: must-revalidate, post-check=0, pre-check=0");
    header("Cache-Control: private",false); // required for certain browsers
    header("Content-Type: $ctype");
    header("Content-Disposition: attachment; filename=\"".$name."\";" );
    header("Content-Transfer-Encoding: binary");
    header("Content-Length: ".$fsize);
    ob_clean();
    flush();
    readfile( $fullPath );

  } else
    throw new Exception("File $fullPath Not Found");
} 

function vimrc_win_hack(){
global $windows;
return $windows ? "
  \" for windows users, see https://github.com/MarcWeber/vim-addon-manager/issues/111
  fun MyPluginDirFromName(name)
    let dir = vam#DefaultPluginDirFromName(a:name)
    return substitute(dir,'%','_', 'g')
  endf
  let g:vim_addon_manager['plugin_dir_by_name'] = 'MyPluginDirFromName'
": '';
}

function vimrc($names, $silent){
global $windows;
$c = $silent ? 'install#Install' : 'ActivateAddons';
return "
set nocompatible
filetype indent plugin on | syn on
set hidden

let g:vim_addon_manager = {}
".(
  $silent ? "
  redir! > log-vim.txt
  let g:vim_addon_manager.dont_source = 1
  let g:vim_addon_manager.auto_install = 1
  let g:vim_addon_manager.log_to_buf = 1

  \" activation is disabled manually enabling VAM-kr
  exec 'set runtimepath+='.filter([\$HOME.'/.vim', \$HOME.'/vimfiles'],'isdirectory(v:val)')[0].'/vim-addons/vim-addon-manager-known-repositories'
  " : "")."

".vimrc_win_hack()."

\" use either windows or linux location - whichever exists
exec 'set runtimepath+='.filter([\$HOME.'/.vim', \$HOME.'/vimfiles'],'isdirectory(v:val)')[0].'/vim-addons/vim-addon-manager'
call vam#".$c."(".json_encode($names).", {'auto_install' : 1})
";
}

function wrap_vimrc($s){
  return '
try
'.$s.'
catch /.*/
  call writefile([v:exception], "/tmp/vam-error")
endtry
  ';
}

function vimrc2(){
  return vimrc(array(), true)
  .'
  let info = {}
  for n in vam#install#KnownAddons(0)
   let repo = get(g:vim_addon_manager["plugin_sources"],n,{})
   if repo != {}
     let info[n] = vam#DisplayAddonInfoLines(n, repo)
   endif
  endfor

fun! Encode(thing, ...)
  let nl = a:0 > 0 ? (a:1 ? "\\n" : "") : ""
  if type(a:thing) == type("")
    return \'"\'.escape(a:thing,\'"\\\').\'"\'
  elseif type(a:thing) == type({}) && !has_key(a:thing, \'json_special_value\')
    let pairs = []
    for [Key, Value] in items(a:thing)
      call add(pairs, Encode(Key).\':\'.Encode(Value))
      unlet Key | unlet Value
    endfor
    return "{".nl.join(pairs, ",".nl)."}"
  elseif type(a:thing) == type(0)
    return a:thing
  elseif type(a:thing) == type([])
    return \'[\'.join(map(copy(a:thing), "Encode(v:val)"),",").\']\'
  else
    throw "unexpected new thing: ".string(a:thing)
  endif
endf

  call writefile( [Encode(info)], "names")
  ';
}

function aszip($names){
global $windows;

set_time_limit(60*60);

file_put_contents(HISTORY_FILE, date('Y-m-d H:m:s').'|'.json_encode($names)."\n", FILE_APPEND | LOCK_EX );
$dir = TMP.'/'.rand(1000,9999);
system('mkdir -p '.$dir.'; chmod -R 777 '.$dir);
# mkdir($dir, '', true);
file_put_contents($dir.'/_vimrc', vimrc($names, false));
file_put_contents($dir.'/_vimrc-fetch', vimrc($names, true));
$cmd = '
  dir='.$dir.'
  cd $dir
  exec > log.txt
  exec 2>&1
  set -x
  mkdir -p .vim/vim-addons
  export PATH=/var/run/current-system/sw/bin
  git clone --depth 1 git://github.com/MarcWeber/vim-addon-manager.git .vim/vim-addons/vim-addon-manager
  ( cd  vim-addon-manager; git chekout HEAD~20; )
  # git clone --depth 1 git://github.com/MarcWeber/vim-addon-manager-known-repositories.git .vim/vim-addons/vim-addon-manager-known-repositories

  export HOME=$dir

  yes | vim -u ~/_vimrc-fetch -U NONE -N -c "qa!" &>/dev/null
	echo done >> /tmp/done

  '.($windows ? 'mv .vim vimfiles' : 'mv _vimrc .vimrc').'

  zip -r vam.zip * .vim*
';
  system("$cmd 2>&1");
  downloadFile( $dir.'/vam.zip', $name = 'vam.zip');
  system('rm -fr '.$dir);
  exit();
}

if (isset($_GET['plugin_info'])){
  $a = name_cache();
  $s = implode("\n", $a[base64_decode($_GET['plugin_info'])]);

  if (strpos($s, "deprecated:") != false){
    echo "PAY ATTENTION TO THE deprecated NOTICE!";
  }

  echo '<pre>';
  echo _htmlentities($s);
  echo '</pre>';
  
  
echo '
</body>
</html>
';
exit();
}

if (isset($_POST['names'])){
 if ($_POST['spam_protection'] != 'V I M'){
   echo 'you failed - SPAM protection. Reread instructions';
   exit();
 } else {
  $names = preg_split('/[ ,]+/', $_POST['names']);
  $errors = array();
  $name_cache = name_cache();
  foreach($names as &$n){
    if (preg_match('/^(VAM|vim-addon-manager|VAM-kr|vim-addon-manager-known-repositories)$/', $n)){
      $errors[] = $n.' will be included automatically, retry';
    }
    $n = preg_replace('/[[\]\'"]/', '', $n);
    if (!isset($name_cache[$n]) && !preg_match('/^(github|git|hg):/', $n))
      $errors[] = 'name '.$n.' unkown. Check against list at the bottom of main page';
  }
  if (count($errors) > 0){
    foreach($errors as $err){
      echo $err.'<br/>';
    }
    exit();
  } else {
    aszip($names);
  }
 }
}

?>

<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
   "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html>
<head>
  <title>VAM for Windows Downloader & VAM pool viewer</title>
    <meta name="robots" content="index,nofollow" />
    <meta http-equiv="content-type" content="text/html; charset=utf-8" />
</head>
<body>

<style type="text/css" media="all">
  .links a {
    text-decoration: none;
    color: #000;
  }

  .hide_link {
     font-size: small;
     color: #CCC !important;
  }

</style>


<h1>VAM downloader for Windows users</h1>

<div>
Installing git, mercurial, zip commands can be tedious on windows.
This page let's you download VAM and its plugins.
</div>

<h2>HOWTO</h2>
<p>
Fill in the form, then copy the _vimrc and vimfiles into your user directory. https using self signed certificate is supported.
</p>

<form method="post">
Put in "V I M" (mind the spaces, spam protection): <br/>
<input type="text" name="spam_protection" value="value"> <br/>

The plugin names you want separated by , or space (VAM-kr and VAM will be included always):<br/>
Yes, from now one '"[] will be stripped so pasting a list is fine, also. This
way you can update everyhting at once easily.<br/>
<input type="text" name="names" value="tlib vim-addon-commenting"><br/>

target operating system:<br/>
<label for="windows">Windows</label><input id="windows" type="radio" name="target_os" value="windows" checked="checked"><br/>
<label for="linux">Linux [1]</label><input id="linux" type="radio" name="target_os" value="linux"><br/>

<input type="submit" name="go" value="download zip"><br/>
Be patient. Fetching repositories by mercurial, svn or git can take some time.<br/>
[1] Linux users may want to use the <a href="https://raw.github.com/MarcWeber/vim-addon-manager/master/doc/vim-addon-manager-getting-started.txt">sample code (section 2)</a>.


</form>

<b>
	If you have trouble contact Marc Weber by email (marco-oweber ATT gmx.de)
	or on irc.freenode.net (#vim).
</b>

<br/>
<br/>
<br/>
<br/>
<br/>

<a href="<?php echo HISTORY_FILE; ?>">previous downloads</a>

<br/>
You want to say thanks? Goto <a href="http://www.vim.org">http://www.vim.org</a> and visit some of the sponsors ..

<?php

function known_names(){
  if (!file_exists(NAME_CACHE_FILE) || (( (time() - filemtime(NAME_CACHE_FILE)) / 60 / 60) > RECREATE_CACHE_HOURS)){
    echo "\n<br/>updating name cache ..<br/>\n";
    ob_end_flush();
    flush();
    $dir = TMP.'/'.rand(1000,9999);
    echo system('mkdir -p '.$dir.'; chmod -R 777 '.$dir);
   if (!is_dir($dir)){
		echo "error creating $dir\n";
		exit();
	}

     file_put_contents($dir.'/_vimrc-fetch', wrap_vimrc(vimrc2()));
    $cmd = '
  dir='.$dir.'
  cd $dir
  exec > log.txt
  exec 2>&1
  set -x
  export PATH=/var/run/current-system/sw/bin
  mkdir -p .vim/vim-addons
  git clone --depth 1 git://github.com/MarcWeber/vim-addon-manager.git .vim/vim-addons/vim-addon-manager
  export HOME=$dir
  yes | vim -u ~/_vimrc-fetch -U NONE -N -c "qa!" &>/dev/null
    ';
    system("$cmd");
    file_put_contents(NAME_CACHE_FILE, file_get_contents($dir.'/names'));
    system('rm -fr $dir');
  }
 $s = '<div class="links"> You can click on these links: </br>';
 foreach(name_cache() as $key => $v){
  $dep =  (strpos(implode("\n", $v), "deprecated:") != false);
   $s .= 
	'<a class="'.($dep ? "hide_link" : '').'" target="n" href="?plugin_info='.base64_encode($key).'" >'
	. _htmlentities($key)
	.'</a>'
	.', ';
 }
 $s .= "</div>";
 return $s;
}

echo '<br/><br/><br/><strong>This list of known plugin names is updated every '.RECREATE_CACHE_HOURS.' hours:</strong><br/>';
echo known_names();

?>

</body>
</html>
