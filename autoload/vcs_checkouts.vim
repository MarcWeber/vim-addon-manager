" Other functions were not mentioned in documentation
for s:f in ['GitCheckout', 'MercurialCheckout', 'SubversionCheckout']
    let s:old='vcs_checkouts#'.s:f
    let s:new='vam#vcs#'.s:f
    execute "function! ".s:old."(...)\n".
                \"call vam#Log('".s:old." is deprecated. Use ".s:new."')\n".
                \"return call('".s:new."', a:000)\n".
                \"endfunction"
endfor
unlet s:f s:old s:new
