<?php

// I just tried to make this downloadeer work.
// Probably there are many ways to improve it.

ob_start();

define('TMP', '/tmp/vam-downloader');
define('HISTORY_FILE', 'previous_downloads.txt');

define('NAME_CACHE_FILE', 'name_cache');
define('RECREATE_CACHE_HOURS', 48 * 2);

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


function vimrc($names, $silent){
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
  " : "
"
)."


\" use either windows or linux location - whichever exists
exec 'set runtimepath+='.filter([\$HOME.'/.vim', \$HOME.'/vimfiles'],'isdirectory(v:val)')[0].'/vim-addons/vim-addon-manager'
call vam#".$c."(".json_encode($names).", {'auto_install' : 1})
";
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
  exec 2>&1
  exec > log.txt
  mkdir -p .vim/vim-addons
  PATH=/var/run/current-system/sw/bin
  git clone --depth 1 git://github.com/MarcWeber/vim-addon-manager.git .vim/vim-addons/vim-addon-manager
  # git clone --depth 1 git://github.com/MarcWeber/vim-addon-manager-known-repositories.git .vim/vim-addons/vim-addon-manager-known-repositories

  export HOME=$dir

  vim -u ~/_vimrc-fetch -U NONE -N -c "qa!" &>/dev/null

  mv .vim vimfiles

  zip -r vam.zip *
';
echo $cmd;
  system("$cmd 2>&1");
  downloadFile( $dir.'/vam.zip', $name = 'vam.zip');
  system('rm -fr '.$dir);
  exit();
}

if (isset($_GET['plugin_info'])){
  $a = name_cache();
  $s = implode("\n", $a[base64_decode($_GET['plugin_info'])]);

  if (strpos($s, "deprecated") != false){
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
  foreach($names as &$n){
    if (preg_match('/^(VAM|vim-addon-manager|VAM-kr|vim-addon-manager-known-repositories)$/', $n)){
      $errors[] = $n.' will be included automatically, retry';
    }
    $n = preg_replace('/[[\]\'"]/', '', $n);
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
  <title>VAM for Windows Downloader</title>
    <meta name="robots" content="index,nofollow" />
    <meta http-equiv="content-type" content="text/html; charset=utf-8" />
</head>
<body>

<h1>VAM downloader for Windows users</h1>

Installing git, mercurial, zip commands can be tedious on windows.
This page let's you download VAM and its plugins.

<form method="post">
Put in "V I M" (mind the spaces, spam protection): <br/>
<input type="text" name="spam_protection" value="value"> <br/>

The plugin names you want separated by , or space (VAM-kr and VAM will be included always):<br/>
Yes, from now one '"[] will be stripped so pasting a list is fine, also. This
way you can update everyhting at once easily.<br/>
<input type="text" name="names" value="tlib vim-addon-commenting"><br/>

<input type="submit" name="go" value="download zip"><br/>
Be patient. Fetching repositories by mercurial, svn or git can take some time.

</form>

If you have trouble contact Marc Weber by email (marco-oweber ATT gmx.de)
or on irc.freenode.net (#vim).

<br/>
<br/>
<br/>
<br/>
<br/>

This site back again - sorry for the long downtime - I'm don't get payed for this.

<a href="<?php echo HISTORY_FILE; ?>">previous downloads</a>

<?php

function known_names(){
  if (!file_exists(NAME_CACHE_FILE) || (( (time() - filemtime(NAME_CACHE_FILE)) / 60 / 60) > RECREATE_CACHE_HOURS)){
    echo "\n<br/>updating name cache ..<br/>\n";
    ob_end_flush();
    flush();
    $dir = TMP.'/'.rand(1000,9999);
    system('mkdir -p '.$dir.'; chmod -R 777 '.$dir);

     file_put_contents($dir.'/_vimrc-fetch', vimrc2());
    $cmd = '
  dir='.$dir.'
  cd $dir
  exec 2>&1
  exec > log.txt
  mkdir -p .vim/vim-addons
  PATH=/var/run/current-system/sw/bin
  git clone --depth 1 git://github.com/MarcWeber/vim-addon-manager.git .vim/vim-addons/vim-addon-manager
  export HOME=$dir

  vim -u ~/_vimrc-fetch -U NONE -N -c "qa!" &>/dev/null
    ';
    system("$cmd");
    file_put_contents(NAME_CACHE_FILE, file_get_contents($dir.'/names'));
    system('rm -fr $dir');
  }
 $s = '';
 foreach(name_cache() as $key => $v){
   $s .= '<a target="n" href="?plugin_info='.base64_encode($key).'" >'._htmlentities($key).'</a>, ';
 }
 return $s;
}

echo '<br/><br/><br/><strong>This list of known plugin names is updated every '.RECREATE_CACHE_HOURS.' hours:</strong><br/>';
echo known_names();

?>

</body>
</html>
