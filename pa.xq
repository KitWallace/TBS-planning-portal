import module namespace pa = "http://kit.wallace.co.uk/lib/pa" at "lib/pa.xqm";
import module namespace pal = "http://kitwallace.co.uk/lib/pal" at "lib/pal.xqm";
import module namespace log = "http://kitwallace.me/log" at "/db/lib/log.xqm";
import module namespace poly = "http://kitwallace.co.uk/lib/poly" at "/db/lib/poly.xqm";
import module namespace url = "http://kitwallace.me/url" at "/db/lib/url.xqm";


let $context := url:get-context()
let $log:= log:log-request("tbs","pa")

let $group := $pa:group
let $apps := if ($context/_signature= ("application","map","fullmap","analysis"))
             then collection($pa:applications)/application
             else if($context/_signature = "application/*") 
             then pa:get-application($context/application) 
             else if ($context/_signature = "search")
             then pa:search-applications($context)
             else ()
             
let $login := if (pal:user()) then xmldb:login("/db/apps/tbs","tbs","edgerton") else ()
let $s := util:declare-option("exist:serialize","method=xhtml media-type=text/html")

return
<html>
<head>
    <meta charset="UTF-8"/>
    <title>Bishopston Planning Portal</title>
    <meta name="viewport" content="width=device-width, initial-scale=1"/>
    <link rel="shortcut icon" type="image/png" href="/tbs/assets/tbs_icon.png"/>

    <link rel="stylesheet" type="text/css" href="/tbs/assets/screen.css" media="screen" ></link>  
    <link rel="stylesheet" type="text/css" href="/tbs/assets/mobile.css" media="only screen and (max-device-width: 480px)" ></link> 
    <style type="text/css">
       {$group/style/text()}   
    </style>
    <script type="text/javascript" src="/tbs/javascript/sorttable.js"></script> 
    <script type="text/javascript" src="https://ajax.googleapis.com/ajax/libs/jquery/1.7.1/jquery.min.js"></script>
    <script src="https://maps.googleapis.com/maps/api/js?key={$pa:googlekey}"></script>
    {if ($context/_signature= ("map","fullmap","application/*")  or $context/_signature="search" and $context/target=("map","fullmap"))
     then ( 
            pa:markers($apps),
            if ($group/area)
            then let $area := doc(concat("/db/apps/tbs/areas/",$group/area,".xml"))//area
                 return poly:area-polygons($area)
            else (),
           <script type="text/javascript">draggable=false;</script>,
           <script type="text/javascript" src="/tbs/javascript/map.js"></script> 
          )
      else ()
     }
     {if ($context/_signature="application/*/edit")
     then (<script src="/javascript/tinymce/js/tinymce/tinymce.min.js"></script>,
     <script>tinymce.init({{ selector:'textarea', branding: false,  plugins: [
             "link image lists "], relative_urls : 0,
             remove_script_host : 0}});</script>
       )
       else ()}
 <!-- Global site tag (gtag.js) - Google Analytics -->
<script async="async" src="https://www.googletagmanager.com/gtag/js?id=UA-119995624-1"></script>
<script>
  window.dataLayer = window.dataLayer || [];
  function gtag(){{dataLayer.push(arguments);}}
  gtag('js', new Date());

  gtag('config', 'UA-119995624-1');
</script>


</head>
<body>
<div>
{if (not ($context/_signature = "fullmap" or $context/target = "fullmap") )
 then
<div>
 {if ($group/icon) then <a target="_blank" href="{$group/url}"><img class="icon" src="{$group/icon}"/></a> else ()}
 {if ($group/logo) then <a href="{$pa:root}map"><img class="logo" src="{$group/logo}"/></a> else ()}

   <div class="menu">
     <a class="button" href="{$pa:root}map">Map</a> &#160;
     <a class="button" href="{$pa:root}application">List</a> &#160;
     <a class="button" href="{$pa:root}analysis">Analysis</a> &#160;
     <a class="button" href="{$pa:root}glossary">Glossary</a> &#160;
     <a class="button" href="{$pa:root}help">Help</a> &#160;
     {if (pal:user())
     then <a class="button" href="{$pa:root}admin/menu">Admin</a>
     else ()
     }
     {if ($context/_signature= ("application","map","search"))
     then
     <form id="search" action="{$pa:root}search" method="post"  style="display:inline" > 
         Pending <input type="checkbox" name="current">{if ($context/current) then attribute checked{"checked"} else ()}</input>   
         <input type="text" name="q" size="20" value="{$context/q}"/>
         <input type="hidden" name="target" value="{($context/target,$context/_signature)[1]}"/>
         <input type="submit" value="Search"/>
     </form>
     else ()
     }
  </div>
</div>
else ()
}
{if ($context/_signature="application/*")  
 then pa:application-page($apps)
 else if ($context/_signature="application")  
 then pa:applications-page($apps)
 else if ($context/_signature="map")
 then  pa:map-page()
 else if ($context/_signature="fullmap")
 then  pa:full-map-page($context)
 else if ($context/_signature="analysis")
 then  pa:analysis($apps)
 else if ($context/_signature="help")
 then  pa:help-page()
 else if ($context/_signature="glossary")
 then  pa:glossary()
 else if ($context/_signature="search")
 then pa:search-page($apps, $context) 
 else if ($context/admin)
 
 (: admin tasks :)
 then if ($context/admin="menu")
 then  pa:admin-page()
 else if ($context/admin="register-form") 
 then pal:register-form()
 else if ($context/admin="register")
 then pal:register()
 else if ($context/admin="admin-help")
 then pa:admin-help()
 else if ($context/admin="login-form")
 then pal:login-form(false())
 else if ( $context/admin="login")
 then pal:do-login()
 else if ( $context/admin="logout" and pal:user())
 then pal:do-logout()
 else if ( $context/admin="register-form")
 then pal:register-form()
 else if ( $context/admin="link-article-form")
 then pa:link-article-form()
 else if ( $context/admin="link-article")
 then pa:link-article()
 else if ($context/admin="refresh-all" and pal:user())
 then let $update := pa:refresh-applications()
      return
         response:redirect-to(xs:anyURI(concat($pa:base,$pa:root,"application")))
 else if ($context/admin="schedule-refresh" and pal:user())
 then pa:schedule-refresh()
 else if ($context/admin="cancel-refresh" and pal:user())
 then pa:cancel-refresh()

 else if ($context/admin="create-form" and pal:user())
 then pa:create-form()
 else if ($context/admin="create" and pal:user())
 then pa:add-application()
 else ()
 
 (: refresh :)
 else if ($context/_signature="application/*/refresh" and pal:user())
 then pa:refresh-page($context/application)
 (: edit  :)
 else if ($context/_signature="application/*/edit" and pal:user())
 then pa:edit-application($context/application)
 else if ($context/_signature="application/*/update" and $context/mode="update"  and pal:user())
 then let $update := pa:update-application($context/application)
      return response:redirect-to(xs:anyURI(concat($pa:base,$pa:root,"application/",$context/application)))
 else if ($context/_signature="application/*/update" and $context/mode="cancel")     
 then pa:application-page(pa:get-application($context/application))

 else ()
}
</div>

</body>
</html>
  