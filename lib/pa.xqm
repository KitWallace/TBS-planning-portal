module namespace pa = "http://kit.wallace.co.uk/lib/pa";
import module namespace pal = "http://kitwallace.co.uk/lib/pal" at "../lib/pal.xqm";
import module namespace content="http://exist-db.org/xquery/contentextraction"
    at "java:org.exist.contentextraction.xquery.ContentExtractionModule";
declare namespace h = "http://www.w3.org/1999/xhtml";
declare variable $pa:base := "http://pp.bishopstonsociety.org.uk";
(: without REST declare variable $pa:base := "http://kitwallace.co.uk/tbs/pa.xq"; :)
declare variable $pa:dbroot := "/db/apps/tbs/"; 
declare variable $pa:root := "/Planning/"; 
(: without REST declare variable $pa:root := "?_path=";   :)
declare variable $pa:googlekey  := "google-mapp-api-key";
declare variable $pa:bcc-path := "https://planningonline.bristol.gov.uk";
declare variable $pa:months :=
	("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct","Nov", "Dec");
declare variable $pa:recommendations := ("","OBJECT","SUPPORT","NEUTRAL");
declare variable $pa:group := doc(concat($pa:dbroot,"/data/tbs.xml"))/group;
declare variable $pa:applications :=concat($pa:dbroot,"new-applications");
declare variable $pa:date-format := "[D01]-[M01]-[Y03]";
declare variable $pa:update-job := "bcc-refresh";

declare function pa:format-date($date) {
   if ($date castable as xs:date)
   then format-date($date,$pa:date-format)
   else $date
};

declare function pa:get-group-index($group){
   collection("/db/apps/tbs/data")/applications[@id=$group]
};

declare function pa:get-application($keyval) {
 collection($pa:applications)/application[keyval=$keyval]
};

declare function pa:application-views($keyval) {
  count(collection(concat($pa:dbroot,"logs"))//logrecord[contains(@queryString,$keyval)])
};

(: application parsing functions :)
declare function pa:parse-date($date) {
  let $parts := tokenize($date," ")
  return 
  if (count($parts) = 4)  (: leading dayname  :)
  then let $month := index-of($pa:months,$parts[3])
       let $month := if ($month  < 10) then concat("0",$month) else $month
       return string-join(($parts[4],$month,$parts[2]),"-")
  else if (count($parts)= 3)
  then let $month := index-of($pa:months,$parts[2])
       let $month := if ($month  < 10) then concat("0",$month) else $month
       return string-join(($parts[3],$month,$parts[1]),"-")
  else ()
};

declare function pa:geocode ($location) {
if (exists($location) and $location !="")
then
let $location := escape-uri($location,false())
let $url := concat("https://maps.googleapis.com/maps/api/geocode/xml?address=",$location,"&amp;key=",$pa:googlekey)
let $response := doc($url)/GeocodeResponse
return 
   if ($response/status="OK")
   then 
      let $result := $response/result[1]
      let $address := $result/formatted_address/string()
      let $latitude := $result/geometry/location/lat/string()
      let $longitude := $result/geometry/location/lng/string()
      return
         element geocode {
             element address {$address},
             element latitude {$latitude},
             element longitude {$longitude}
         }
   else $response/status
 else ()
};
 
declare function pa:span($page,$name) {
    normalize-space($page//h:span[@class=$name])
};

declare function pa:td($page,$name) {
    normalize-space($page//h:tr[normalize-space(h:th)=$name]/h:td)
};

declare function pa:get($keyval,$page) {
   let $url := pa:bcc-link($keyval,$page)
   let $page := httpclient:get(xs:anyURI($url),false(),())
   return $page
};

declare function pa:comment-id($doc-path) {
   substring-before(substring-after($doc-path,"/online-applications/files/"),"/pdf")
};

declare function pa:comments($app,$pdfs) {
(:new ones only but all are counted 

   problem since no  documents if finished - count be taken from the saved comments instead
   
:)
let $url := pa:bcc-link($app/keyval,"documents")
let $page := httpclient:get(xs:anyURI($url),true(),())
let $table := $page//h:table[@id="Documents"]
let $rows:= $table//h:tr[h:td[3]="Public Comment"]
let $comment-list := 
        for $comment at $i in $rows
        let $address := substring-before($comment/h:td[5],"-")
        let $support := contains($comment/h:td[5],"SUPPORT")
        let $object := contains($comment/h:td[5],"OBJECT")
        let $doc-path := $comment/h:td[6]/h:a/@href/string()
        return 
          element entry {
             element id {pa:comment-id($doc-path)},
             element doc-path {$doc-path},
             element date {pa:parse-date($comment/h:td[2])},
             element address {$address},
             if ($support) then element support {} 
             else if ($object) then element object {}
             else ()
          }
 let $comments :=
        for $entry in $comment-list
        where not ($app/comments/comment/id =$entry/id) and $pdfs
        return
           let $comment-url := concat($pa:bcc-path,$entry/doc-path)
           let $submission :=  try { pa:parse-pdf($comment-url)}
                               catch * {element submission {element comments {"Unable to process the comment document"}}}
           return 
               element comment {
                   $entry/*,
                   $submission/customer,
                   $submission/comments
               }
return
  if ($rows) 
  then 
    element result {
      element comment-analysis {
           element supporters {count($comment-list[support])},
           element objectors {count($comment-list[object])}
      },
      $comments
   }
  else 
    element result {
      element comment-analysis {
           element supporters {0},
           element objectors {0}
      }
   }
};

declare function pa:extract-summary($application) {
 let $keyval := $application/keyval
 let $summary := pa:get($keyval,"summary")//h:table[@id="simpleDetailsTable"]
 let $dates := pa:get($keyval,"dates")//h:table[@id="simpleDetailsTable"]
 let $details := pa:get($keyval,"details")//h:table[@id="applicationDetails"]
 let $address := pa:td($summary,"Address")
 let $lat-long := pa:geocode($address)
 return
   element summary {
       $keyval,
       element extraction_dateTime{current-dateTime()},
       element reference {pa:td($summary,"Reference")},
       element proposal {pa:td($summary,"Proposal")},
       element status {pa:td($summary,"Status")},
       element address {$address},
       $lat-long/latitude,
       $lat-long/longitude,
       element validation-date {pa:parse-date(pa:td($dates,"Application Validated Date"))},
       element neighbour-expiry-date {pa:parse-date(pa:td($dates,"Neighbour Consultation Expiry Date"))},
       element standard-expiry-date {pa:parse-date(pa:td($dates,"Standard Consultation Expiry Date"))},
       element determination-date {pa:parse-date(pa:td($dates,"Determination Deadline"))},
       element application-type {pa:td($details,"Application Type")},
       element decision {pa:td($details,"Decision")},
       element decision-issue-date {pa:parse-date(pa:td($dates,"Decision Issued Date"))}
      }
};

declare function pa:bcc-link($keyval,$page) {
    concat ($pa:bcc-path,"/online-applications/applicationDetails.do?activeTab=",$page,"&amp;keyVal=",$keyval)
};
(: https://planningonline.bristol.gov.uk/online-applications/applicationDetails.do?activeTab=summary&keyVal=PCIM9ZDNII700 :)

declare function pa:gmap-link($address) {
   concat ("https://www.google.co.uk/maps/place/",replace($address," ","+"))
   };
   
declare function pa:parse-pdf($url) {
let $binary-doc := httpclient:get(xs:anyURI($url),false(),())
return if ($binary-doc/@statusCode !="200") 
then element submission {
     element url {$url},
     element status {$binary-doc/@statusCode/string()}
    } 
else
let $converted-doc := content:get-metadata-and-content($binary-doc/httpclient:body)
let $customer-details := $converted-doc//h:div[@class="page"][1]/h:p[starts-with(.,"Customer Details")]
let $comment-details := $converted-doc//h:div[@class="page"][1]/h:p[starts-with(.,"Comment Details")]
let $comment-rest := $comment-details/following-sibling::*
let $details := substring-before(substring-after($comment-details,"Stance"),"Comment")
return 
element submission {
   element date-stored {current-dateTime()},
   element url {$url},
   element details {$details},
   if (matches($details,"object","i")) then element object {}
   else if (matches($details,"support","i")) then element support {}
   else (),

   element comments {
           element h:p {substring-after($comment-details,"Comment:")},
           $comment-rest,
           for $page in subsequence($converted-doc//h:div[@class="page"],2)
           for $p in $page/h:p
           where $p !=""
           return $p
           },
    element customer {
         element name {substring-before(substring-after($customer-details,"Name:"),"Address:")},
         element address {substring-after($customer-details,"Address:")}
         }
 }
};

(: refesh applications :)

declare function pa:refresh-application($app) {
    let $summary := pa:extract-summary($app)
    let $comments:= pa:comments($app,true())
    let $update := if ($summary/reference) then update replace $app/summary with $summary else ()
    let $capdate := update replace $app/comment-analysis with $comments/comment-analysis
    let $cupate:= if ($comments/comment) then update insert $comments/comment into $app/comments else ()
    return true()
};

declare function pa:refresh-applications() {
   for $app in collection($pa:applications)/application
   where not($app/summary/status = ("Decided","Withdrawn"))
   return pa:refresh-application($app)
};
  
declare function pa:schedule-refresh() {
   let $interval := "0 0 23 * * ?" (: run at 11pm every day :)
   let $remove-old := scheduler:delete-scheduled-job($pa:update-job) 
   let $schedule := scheduler:schedule-xquery-cron-job(concat($pa:dbroot,"scheduled-update.xq") ,$interval, $pa:update-job)
   return true()
};
declare function pa:cancel-refresh() {
   scheduler:delete-scheduled-job($pa:update-job) 
};

declare function pa:job-status() {
   let $jobs := scheduler:get-scheduled-jobs()
   let $update-job := $jobs//scheduler:job[@name=$pa:update-job]
   return
     <span>{if ($update-job//state = "NORMAL") then "scheduled" else "not scheduled"} </span>
};

declare function pa:edit-application($keyval) {
let $app := pa:get-application($keyval)
let $summary := $app/summary
let $local := $app/local
return
  <div>  
    <form action="{$pa:root}application/{$keyval}/update" method="post">
      <table>
         <tr><th>Reference</th><td>{$summary/reference/string()}</td></tr>
         <tr><th>Address</th><td>{$summary/address/string()}</td></tr>
         <tr><th>Proposal</th><td>{$summary/proposal/string()}</td></tr>
         <tr><th>TBS Commentary</th>
             <td><textarea name="comment" rows="20" cols="100">
                {$local/comment/*}
             </textarea></td></tr>
         <tr><th>Location override</th><td>Latitude <input type="text" name="latitude" size="12" value="{$summary/latitude}"/>
                                  Longitude <input type="text" name="longitude" size="12" value="{$summary/longitude}" /> 
         </td></tr>
         <tr><th>TBS position</th>
             <td> 
               <select name="recommendation" >
                {for $r in $pa:recommendations
                 return element option {
                          if ($r = $local/recommendation)
                          then attribute selected {"selected"}
                          else (),
                          $r
                         }
                }
               </select>
            </td>
         </tr>
         <tr><th/><td><input type="submit" name="mode" value="update"/> <input type="submit" name="mode" value="cancel"/></td></tr>
      </table>
    </form>
  </div>
 };
 
 declare function pa:update-application($keyval) {
     let $app := pa:get-application($keyval)
     let $recommendation := element recommendation{ request:get-parameter("recommendation",())}
     let $comment := element comment {util:parse-html(request:get-parameter("comment",()))}
     let $latitude := request:get-parameter("latitude",())
     let $longitude := request:get-parameter("longitude",())
     let $local := 
          element local {
             $app/local/created-by,
             element keyval {$keyval},
             element recommendation {$recommendation},
             $comment,
             if ($latitude != "")
             then element latitude {$latitude}
             else (),
             if ($longitude !="")
             then element longitude {$longitude}
             else ()
         }
     let $update := update replace $app/local with $local       
     return $local
 };

 declare function pa:create-form() {
 <div>
   <p>Create a new application by entering  the keyVal or a link to the planning application which contains the keyVal. </p>
   <p>You may need to search <a target="_blank" class="external" href="http://planningonline.bristol.gov.uk/online-applications/">Bristol City Council Planning Online</a>
     using the reference number</p>
   <form  action="{$pa:root}admin/create" method="post">
     <input type="text" name="planningurl" size="120"/>
     <input type="submit" value="Create"/>
   </form>
  </div>
 };
 
 declare function pa:add-application(){
   let $input := request:get-parameter("planningurl",())
   let $keyval := 
         if (contains($input,"keyVal="))
         then let $rest := substring-after($input,"keyVal=")
              return if(contains($rest,"&amp;")) then substring-before($rest,"&amp;") else $rest
         else if (string-length($input)=15)
         then $input
         else ()
    let $exists := pa:get-application($keyval)
    let $inportal := exists (pa:get($keyval,"summary")//h:table[@id="simpleDetailsTable"])
    return
      if ($keyval and not ($exists) and $inportal)
      then 
         let $app := element application{
                  element keyval {$keyval},
                  element local {
                      element created-By {pal:user()},
                      element creation-dt {current-dateTime()}
                  },
                  element summary {},
                  element comment-analysis {},
                  element comments {}
              }
         let $store := xmldb:store($pa:applications,concat($keyval,".xml"),$app)
         let $app := pa:get-application($keyval)
         let $extract := pa:refresh-application($app)
         return response:redirect-to(xs:anyURI(concat($pa:base,$pa:root,"application/",$app/keyval,"/edit")))
      else 
    <div>
    <h3>Cannot add new application</h3>
    <div>
      Input : {$input} <br/>
      KeyVal: {$keyval} <br/>
      Error: 
      {if (empty($keyval)) then 
      "keyval missing or invalid"
      else if ($exists)
      then "this application already exists"
      else if (not ($inportal))
      then "no such application on BCC Planning site"
      else "other error"
      }
      </div>
      <a href="{$pa:root}admin/create-form">Try again</a>
    </div>
 };

(:  page rendering functions :)

declare function pa:rec-colour($text) {
     let $s := upper-case($text)
     return
     if ($s="SUPPORT") then "green"
     else if ($s="OBJECT") then "red"
     else if ($s="NEUTRAL") then "blue"
     else "black"
};

declare function pa:markers($apps){
<script type="text/javascript">
var markers = [
   { string-join(
        for $app at $i in $apps
        let $local := $app/local
        let $summary := $app/summary
        let $latitude := ($local/latitude,$summary/latitude)[1]
        let $longitude := ($local/longitude,$summary/longitude)[1]
        let $position := if (exists($local/recommendation) and $local/recommendation != "")
                        then $local/recommendation/string()
                        else 
                            let $group := $pa:group
                            let $group-comment := $app/comments/comment[starts-with(address,$group/response-address)]
                            return 
                                if($group-comment)
                                   then if ($group-comment/support)
                                   then "SUPPORT"
                                   else if ($group-comment/object)
                                   then "OBJECT"
                                   else "NEUTRAL"
                                  
                               else ""

        return 
           if ($latitude)
           then
    
        let $colour := pa:rec-colour($position)
        let $description := 
          <div>
               <h3><a href="{$pa:root}application/{$app/keyval}">{$summary/reference/string()}</a> : <bold style="color: {$colour}">{$position}</bold></h3>
               <p>{$summary/address/string()}</p>
               <p>{replace(normalize-space($summary/proposal),"'","\\'")}</p>
            </div>
           let $sd :=  util:serialize($description,"method=xhtml media-type=text/html indent=no") 
        let $icon :=       
          if ($position="SUPPORT")
          then "http://maps.google.com/mapfiles/ms/icons/green-dot.png"
          else if ($position="OBJECT")
          then "http://maps.google.com/mapfiles/ms/icons/red-dot.png"
          else if ($position="NEUTRAL")
          then "http://maps.google.com/mapfiles/ms/icons/blue-dot.png"
          else "http://maps.google.com/mapfiles/ms/icons/yellow-dot.png"
        return
        
           concat("['",$summary/address,"',",
                  $latitude/string(),",",$longitude/string(),
                  ",'",$sd,"','",$icon,"']") 
       else ()
   ,",&#10;")
     }
   ];
</script>
};


declare function pa:application-table($apps){

<table class="sortable" >
 <tr><th>Reference</th><th width="8%">Validation date</th><th>Address</th><th>Proposal</th><th># Comments</th><th>TBS submission</th><th width="8%">TBS submission date</th><th>Status</th><th width="8%">Status date</th></tr>
 {let $group := $pa:group
  for $app in $apps
  let $summary := $app/summary
  let $comments:= $app/comments
  let $status := $summary/status
  let $local:= $app/local
  let $group-comment := $comments/comment[starts-with(address,$group/response-address)]
  let $position := if ($local/recommendation != "")
                   then $local/recommendation
                   else  if ($group-comment)
                             then                                     
                                  if ($group-comment/support)
                                  then "SUPPORT"
                                  else if ($group-comment/object)
                                  then "OBJECT"
                                  else "NEUTRAL"
                             else ""
  order by $summary/validation-date descending
  return
   <tr > 
      <td><a href="{$pa:root}application/{$app/keyval}">{$summary/reference/string()}</a></td>
      <td sorttable_customkey="{$summary/validation-date}">{pa:format-date($summary/validation-date)}</td>
      <td>{$summary/address/string()}</td>
      <td><b>{$summary/application-type/string()}</b> : {$summary/proposal/string()}</td>
      <td>{count($comments/comment)}</td>
      <td style="color:{pa:rec-colour($position)}"> {$position} </td>
      <td sorttable_customkey="{($group-comment/date)[1]}">
           {if ($group-comment) 
           then pa:format-date(($group-comment/date)[1])
           else "          "
           }</td>
      <td>{ if ($status="Decided")
            then let $success :=  contains($summary/decision,"BE ISSUED") or contains($summary/decision,"GRANTED")
                 let $failure :=  contains($summary/decision,"REFUSED") or  contains($summary/decision,"Withdrawn")
                 return
                   <div><span>{attribute style {concat("color:",if($success) then "green" else if ($failure) then "red" else "black")}, $status}</span>
                        <br/> {$summary/decision/string()}
                   </div>
            else $status/string()}</td>  
      {let $date :=
           if ($status="Decided")
           then $summary/decision-issue-date/string()
           else if (contains($status,"Pending"))
           then $summary/determination-date/string()
           else ()
       return 
           <td sorttable_customkey="{$date}">{pa:format-date($date)}</td>
           }
      </tr>
    }
</table>
};

declare function pa:show-comment($comment) {
   <div>
       <h4>{if ($comment/customer/name != "")
            then <span>{$comment/customer/name/string()}&#160;{$comment/name/string()} {$comment/address/string()} </span>
            else <span>Unknown</span>
            }
             &#160;
            {if ($comment/object) 
              then <span style="color:red">OBJECT</span> 
              else if ($comment/support) 
              then <span style="color:green">SUPPORT</span> 
              else ()}
             </h4>
          <div class="comment">{$comment/comments}</div>
  </div>
};
declare function pa:show-group-comment($group,$comment) {
   <div>
       <h4>{$comment/customer/name/string()}&#160;
             {if ($comment/object) 
              then <span style="color:red">OBJECT</span> 
              else if ($comment/support) 
              then <span style="color:green">SUPPORT</span> 
              else ()}
        </h4>
         {if ($group/include-response)
          then <div class="comment">{$comment/comments}</div>
          else <div class="comment">see above</div>
         }
  </div>
};

declare function pa:show-application($app) {
    let $local := $app/local
    let $summary := $app/summary
    let $comments:= $app/comments
    let $group := $pa:group
    let $keyval := $app/keyval
    let $n-comments := count($comments/comment)
    let $group-comment := $comments/comment[starts-with(address,$group/response-address)]
    let $public-comments := $comments/comment except $group-comment
    let $latitude := ($local/latitude,$summary/latitude)[1]
    let $longitude := ($local/longitude,$summary/longitude)[1]
    let $position := if ($local/recommendation != "")
                        then $local/recommendation
                        else if ($group-comment)
                             then if ($group-comment/support)
                                  then "SUPPORT"
                                  else if ($group-comment/object)
                                  then "OBJECT"
                                  else "NEUTRAL"
                             else ""
    let $number := substring-before($summary/address," ")   
    let $number := if (contains($number,"-")) then substring-before($number,"-") else $number
    let $GRSref := if (contains($summary/address,"Gloucester Road"))
                   then concat("http://thegloucesterroadstory.org/TheRoad/road/GR/number/",$number,"/history")
                   else ()
    let $articles :=  doc("/db/apps/tbs/data/articles.xml")//article[keyval=$keyval]
    return
     <div>
     <h2>Application Details</h2>
      <table class="left_col">
         <tr><th>Reference</th><td>{$summary/reference/string()}</td></tr>
         <tr><th>Address</th><td>{$summary/address/string()} &#160;
         {if ($latitude) 
         then (<br/>,<span><a target="_blank" class="external" href="https://www.google.com/maps?q=&amp;layer=c&amp;cbll={$latitude},{$longitude}">Street View</a></span>)
         else ()
         }
         {if ($GRSref)
         then (<br/>,<span><a class="external" target="_blank" href="{$GRSref}">Gloucester Road Story </a></span>)
         else ()
        }</td></tr>
           <tr><th>Proposal</th><td>{$summary/proposal/string()}</td></tr>
         <tr><th>Validated</th><td>{pa:format-date($summary/validation-date)}</td></tr> 
         <tr><th>Type</th><td>{$summary/application-type/string()}</td></tr>
         <tr><th>Status</th><td>{$summary/status/string()}</td></tr>
          {if ($summary/neighbour-expiry-date !="") then <tr><th>Neighbour Consultation Expiry</th>
              <td>{pa:format-date($summary/neighbour-expiry-date)}</td></tr> else ()}
         {if ($summary/standard-expiry-date !="") then <tr><th>Standard Consultation Expiry</th>
              <td>{pa:format-date($summary/standard-expiry-date)}</td></tr> else ()}
         <tr><th>Determination Deadline</th>
               <td>{pa:format-date($summary/determination-date)}</td></tr>
         {if($summary/decision !="") then <tr><th>Decision</th><td>{$summary/decision/string()}</td></tr> else ()}
         {if($summary/decision-issue-date != "") 
          then <tr><th>Decision Issued</th>
                   <td>{pa:format-date($summary/decision-issue-date)}</td></tr> else ()}
         
         {if (pal:user()) 
         then <tr><th>Last refreshed</th><td>{format-dateTime($summary/extraction_dateTime,$pa:date-format)} &#160;
               <span><a href="{$pa:root}application/{$keyval}/refresh">Refresh Data from BCC</a>&#160;
                     <a href="{$pa:root}application/{$keyval}/edit">Edit</a>
               </span> 
               </td>
              </tr>
          else ()
          }
        <tr><th>BCC Planning Portal</th><td><a class="external" target="_blank" href="{pa:bcc-link($keyval,"summary")}">Application</a></td></tr>
       
        {if ($n-comments > 0) 
        then  let $missing-n := $n-comments -  count($comments/comment/support) -count($comments/comment/object)
              return 
                <tr>
                 <th>Public Comments</th>
                 <td>Supporters: {count($comments/comment/support)}&#160;Objectors: {count($comments/comment/object)}&#160; {if ($missing-n>0) then concat("Unstated: ",$missing-n) else ()}&#160; Total: {$n-comments}</td></tr> else () }
          <tr><th>No. of Page Views</th><td>{pa:application-views($keyval)}</td></tr>
        {if ($articles)
        then <tr><td>TBS articles</td>
                 <td><ul>{for $article in $articles 
                          return <li>{pa:format-date(substring($article/datetime,1,10))} : <a target="_blank" href="{$article/url}">{$article/title/string()}</a></li>}</ul></td></tr>
        else ()
        }
       </table>
        <div  class="left_col">
             <h3>{$group/abbrev/string()} response: 
                <span style="color:{pa:rec-colour($position)}">{$position}</span>
             </h3> 
                  <p> 
                  {if (exists($group-comment)) 
                   then concat("Recommendation submitted ",pa:format-date(($group-comment/date)[1]))
                   else ()
                   }
                   </p>
                  {$local/comment/*}
        </div>
       

         {if ($public-comments or $group-comment)
         then 
         <div class="comment_col">
            <h3>Public Comments</h3>
              {if ($group-comment) 
              then pa:show-group-comment($group,$group-comment)
              else ()
              }
              {for $comment in $comments/comment except $group-comment
               order by $comment/date descending
               return pa:show-comment($comment)
              }
         </div>
         
         else ()
         }
    </div>         
};

declare function pa:search-applications($context) {
       let $q := $context/q
       let $current := $context/current   
       let $apps := collection($pa:applications)/application 
       let $apps1 := 
           if (exists($current))
           then $apps[not(summary/status = ("Decided","Withdrawn"))]
           else $apps  
  
       for $app in $apps1
       where matches(concat($app/summary,$app/local),$q,"i")
       return $app
};

(: page constructors :)

declare function pa:applications-page($apps) {
    pa:application-table($apps)

};
declare function pa:application-page($app) {
  <div> 
        <div class="text">{pa:show-application($app)}</div>
        <div id="map_canvas"  class="small_map"></div>
  </div>
};
declare function pa:map-page() {
<div>
    <div>
 <!--       <span><a class="button" href="{$pa:root}fullmap">Full Size Map</a> </span>  -->
        <span>SUPPORT <img src="http://maps.google.com/mapfiles/ms/icons/green-dot.png"/></span>
       <span>OBJECT <img src="http://maps.google.com/mapfiles/ms/icons/red-dot.png"/></span>
       <span>NEUTRAL <img src="http://maps.google.com/mapfiles/ms/icons/blue-dot.png"/></span>
       <span>No Opinion<img src="http://maps.google.com/mapfiles/ms/icons/yellow-dot.png"/></span>
      </div>
      <div id="map_canvas" class="big_map" tabindex="-1"  >
     
     </div>
 </div>
 };
 
 declare function pa:full-map-page($context) {
<div>
      <div>
       <span><a class="button" href="{$pa:root}map">Map</a> </span>
       <span>SUPPORT <img src="http://maps.google.com/mapfiles/ms/icons/green-dot.png"/></span>
       <span>OBJECT <img src="http://maps.google.com/mapfiles/ms/icons/red-dot.png"/></span>
       <span>NEUTRAL <img src="http://maps.google.com/mapfiles/ms/icons/blue-dot.png"/></span>
       <span>No Opinion<img src="http://maps.google.com/mapfiles/ms/icons/yellow-dot.png"/></span>
       <form id="search" action="{$pa:root}search" method="post"  style="display:inline" > 
       Pending <input type="checkbox" name="current">{if ($context/current) then attribute checked{"checked"} else ()}</input>   
         <input type="text" name="q" size="20" value="{$context/q}"/>
         <input type="hidden" name="target" value="{($context/target,$context/_signature)[1]}"/>
         <input type="submit" value="Search"/>
     </form>
      </div> 
      <div id="map_canvas" class="bigger_map" tabindex="-1"  >
     
     </div>
 </div>
 };
 
 declare function pa:admin-page() {
 <div>    
    <h3>Site administration</h3>
     <ul>
     {if (pal:user())
     then  
     (<li>{pal:user()/string()} Logged in. <a href="{$pa:root}admin/logout">Logout</a></li>,
      <li><a href="{$pa:root}admin/admin-help">Admin help</a></li>,
      <li><a href="{$pa:root}admin/create-form">Create new Application</a></li>,
      <li>Refresh task  {pa:job-status()}. 
          {if(pa:job-status()="scheduled")
           then <a href="{$pa:root}admin/cancel-refresh">Cancel Refresh task </a> 
           else <a href="{$pa:root}admin/schedule-refresh">Start Refresh task </a> 
          }
     </li>,
     <li><a href="{$pa:root}admin/refresh-all">Manually refresh all</a></li>,
     <li><a href="{$pa:root}admin/link-article-form">Link to TBS article</a></li>,
     <li><a href="{$pa:base}/tbs/logs/log.xml">Raw Log</a></li> 
     )
     else
     (
      <li><a href="{$pa:root}admin/login-form">Login</a></li>,
      <li><a href="{$pa:root}admin/register-form">Register</a></li>
     )
     }
    </ul>  
 </div>
 
 };
 
 declare function pa:refresh-page($keyval) {
     let $app := pa:get-application($keyval)
     let $refresh := 
         if ($app) 
         then pa:refresh-application($app)
         else ()
      return 
      if ($refresh) 
             then  response:redirect-to(xs:anyURI(concat($pa:base,$pa:root,"application/",$keyval)))
             else <div>Failed to update <a href="{$pa:root}application/{$keyval}">{$keyval} </a></div>
 };
 
 declare function pa:search-page($apps,$context) {
   let $target := $context/target
   return
  <div>
   {if ($target="map")
   then pa:map-page()
   else if ($target="fullmap")
   then pa:full-map-page($context)
   else if($apps) 
   then pa:application-table($apps)
   else <div>No Matching Applications. </div>
   }
 </div> 
 };
 
 declare function pa:admin-help() {
<div>
    <div>These notes describe the admin functions on the TBS planning portal </div>
    <h3>Registering</h3>
    <ul>
        <li>To register as an admin user, complete the registration form.  This requires knowledge of a secret word which will be communicated to you separately. </li>
    </ul>
    <h3>Adding a new application</h3>
    <ul>
        <li>To add a new application, this site needs to know the value of the keyVal for the applicaton on the <a href="{$pa:bcc-path}">BCC Planning portal</a>. 
            This is to be found at the end of the URL which retrieves a page such as the documents eg:
            <br/>http://planningonline.bristol.gov.uk/online-applications/applicationDetails.do?activeTab=summary&amp;keyVal=P4JNPRDNL8S00
        </li>
        <li>It has not so far possible to get this value from the planning reference number eg 18/00969/F .  A suitable URL is included in the email response from the Planning system 
            when a submission is made, or you can use the search facility on the Planning Portal to locate the URL (but be aware that the first page does not contain this value.
        </li>
        <li>when you have the keyVal or a URL containing the keyVal, go to the form to add a new application and paste this text into the form. When the form is submitted, the details will be extracted from the planning system (may take a minute or so) and you can then edit the entry in our database.
        </li>
    </ul>
    <h3>Editing our application data</h3>
      <ul>

        <li>The planning portal keeps and allows editing of data additional to that extracted from the Planning Portal. This includes:
            <ul>
                <li>The decision of the TBS to this application.  This may be SUPPORT, OBJECT, NEUTRAL or undecided.</li>
                <li>Commentary on this application.  This may be the same as the submission made to BCC (although that submission will be included in the list of extracted comments) or it may extend or supplement that submission with illustions or photographs, or to comment on the application process or decision.  Whatever text is entered here, the formal submission through the planning portal is still required.</li>
                <li>Latitude /Longitude: the computed location can be incorrect.  A better postion could be located using eg Google Maps and entered here to override the computed postion.</li>
           </ul>
        </li>  
        <li>You can edit any application by finding it on the list or map and viewing te application details, where you will find an edit button (if you are logged in)</li>
    </ul>
    <h3>Keeping the site up-to-date</h3>
    <ul>
        <li>The site runs a job to refresh the database every day at 23.00.  This refesh is limited to applications which have not been closed or withdrawn. If this fails for some reason, the job may have to be restarted by the Sysop (Chris).</li>
        <li>In addition, this job may be run manually but this should not really be needed</li>
        <li>Each application can also be separately refreshed. This may be required if an application is reopened after appeal.</li>
        
    </ul>
    
    <h3>Linking</h3>
    <ul>
      <li>The page for an application has a url such as http://pp.bishopstonsociety.org.uk/Planning/application/OU2CFQDNG2A00  This is the link to use when referencing an application on the TBS site or to use in email communication.</li>
    </ul>
    <h3>Known issues</h3>
    <ul>
        <li>Extraction of the text of comments is imperfect.  Spaces are often dropped in the text of all comments. Some documents are not parsed correctly.  This seems to be where the submbission has be sent in separately as a letter or email rather than submitted online.</li>
        
    </ul>
</div>
 };
 
 declare function pa:help-page() {
<div>
    <p>Welcome to the Bishopston Planning Portal, our innovative interactive tool presenting details
        of the main planning applications in our area lodged recently with Bristol City Council as
        the local planning authority. </p>
    <h3>Map</h3>
    <ul>
        <li>The Google map shows (crudely) the boundaries of the Bishopston area we typically work
            in, though some planning applications outside the immediate area that impinge on us also
            appear. </li>
        <li>Click on a pin, using the legend provided, to find the address and basic details of
            the planning application.</li>
        <li>Click on the reference number to access the full details of the application.</li>
    </ul>
    <h3>List</h3>
    <ul>
        <li>Recent planning applications are listed here in tabular format, initially in descending order of validation date, ie the date the application was checked and validated by BCC </li>
        <li>Applications can be sorted into a different order using the up/down buttons in each
            column heading. </li>
         <li>Click on the reference number to access the full details of the application.</li>
    </ul>
    <h3>Search</h3>
    <ul>
        <li>You can search the applications using the search entry on the List or Map page.  For example you may want to find applications in a street or with a particulalr feature.</li>
        <li>You can also limit the map or list to pending applications i.e those not yet decided.</li>
    </ul>
    <h3>Application details </h3>
    <ul>
        <li>You can access the application details by clicking on the Application reference number on either a map icon or an entry in the list of applications.</li>
        <li>Lots more details are provided on the application details screen, including a close-up
            map, the current status of the application, our comments, and those made by the public. </li>
        <li>You can use the link provided to reach all the official documents for the application on
            <a class="external" target="_blank" href="http://planningonline.bristol.gov.uk/online-applications/">Bristol City Council Planning Online</a>. You can also submit your own comments via this web
            site. </li>
    </ul>
    <h3>Scope and maintenance</h3>
    <ul>
        <li>This portal covers planning applications which have been noted by TBS in our area since October 2017. </li>
        <li>The definitive source of data is the <a class="external" target="_blank" href="http://planningonline.bristol.gov.uk/online-applications/">Bristol City Council Planning Online</a> </li>
        <li>The data is updated every day.</li>
    </ul>
    <h3>About TBS comments &amp; recommendations</h3>
    <ul>
        <li>The Bishopston Society’s policy on planning applications is documented <a href="http://bishopstonsociety.org.uk/planning/policies">here</a> and
            reviewed/updated from time to time by the committee, with routine decision-making
            delegated to our planning team. </li>
        <li>We also consult our membership and disseminate our policy via our web site, newsletter,
            email updates, social media channels, etc., especially in response to changes in the
            policy environment, and when larger developments crop up. </li>
    </ul>
    <h3>About this portal </h3>
    <ul>
        <li>This portal has been developed by&#160;<a target="_blank" class="external" href="http://kitwallace.co.uk">Chris Wallace</a> as part of a project to analyse
            Bristol City Council planning applications. </li>
        <li>The data presented is drawn primarily from Bristol City Council’s <a target="_blank" class="external" href=" http://planningonline.bristol.gov.uk/online-applications/">searchable planning database</a> , with value-added content added by the TBS team. </li>
        <li>Technically-minded readers may wish to know that it uses&#160;the <a href="http://existdb.org"> eXist open source XML database</a> and is programmed in
            XQuery and Javascript. Issues and eventually code reside on <a target="_blank" class="external" href="https://github.com/KitWallace/TBS-planning-portal">Github</a>. </li>
    </ul>
    <h3>Feedback</h3>
    <ul>
        <li>Comments and feedback on this portal are welcome via <a href="http://bishopstonsociety.org.uk/about/contactus">our contact form</a>.</li>
    </ul>
    <h3> Disclaimer</h3>
    <ul>
        <li>Whilst we have confidence in the software and data used in the construction of this
            portal, we offer no warranty over the veracity or accuracy of the information provided,
            and are not liable for any errors or inaccuracies you may encounter. Our standard <a href="http://www.bishopstonsociety.org.uk/legal-notices">legal
            notices and policies </a> apply.</li>
    </ul>
    <h3>Admin</h3>
    <ul>
        <li>
            <a href="{$pa:root}admin/menu">Admin functions </a>
        </li>
    </ul>
</div>
 
 };
 
 
 declare function pa:analysis ($apps) {
   let $data :=
      for $app in $apps
      let $summary:=$app/summary
      let $position := if ($app/local/recommendation != "")
                        then $app/local/recommendation/string()
                        else let $group := $pa:group
                             let $group-comment := $app/comments/comment[starts-with(address,$group/response-address)]
                             return
                             if ($group-comment)
                             then if ($group-comment/support)
                                  then "SUPPORT"
                                  else if ($group-comment/object)
                                  then "OBJECT"
                                  else "NEUTRAL"
                             else "NEUTRAL"
      let $decision := if ($summary/status = "Decided" )
                       then if (contains($summary/decision,"GRANTED") or contains ($summary/decision,"BE ISSUED"))
                       then "Granted"
                       else if (contains($summary/decision,"REFUSED"))
                       then  "Refused"
                       else "unknown"
                       else if ($summary/status = "Withdrawn" )
                       then "Withdrawn"
                       else "Pending"
      return element app {$app/keyval, element TBS {$position}, element BCC {$decision}}
  return    
  <div>
  <h3>Decision analysis for {count($apps)} Applications</h3>
  <table id="analysis">
  <tr><th>TBS &#8594;<br/>BCC &#8595;
  </th><th>Support</th><th>Neutral</th><th>Object</th><th>Total</th></tr>
  <tr><th>Pending</th>
            <td>{count($data[TBS="SUPPORT"][BCC="Pending"])}</td>
            <td>{count($data[TBS="NEUTRAL"][BCC="Pending"])}</td>
            <td>{count($data[TBS="OBJECT"][BCC="Pending"])}</td>
            <td>{count($data[BCC="Pending"])}</td>
            </tr>
  <tr><th>Granted</th>
            <td style="background-color:green">{count($data[TBS="SUPPORT"][BCC="Granted"])}</td>
            <td>{count($data[TBS="NEUTRAL"][BCC="Granted"])}</td>
            <td style="background-color:red">{count($data[TBS="OBJECT"][BCC="Granted"])}</td>
            <td>{count($data[BCC="Granted"])}</td>
            </tr>
            
  <tr><th>Withdrawn</th>
            <td>{count($data[TBS="SUPPORT"][BCC="Withdrawn"])}</td>
            <td>{count($data[TBS="NEUTRAL"][BCC="Withdrawn"])}</td>
            <td style="background-color:green">{count($data[TBS="OBJECT"][BCC="Withdrawn"])}</td>
            <td>{count($data[BCC="Withdrawn"])}</td>
            </tr>
 <tr><th>Refused</th>
            <td style="background-color:red">{count($data[TBS="SUPPORT"][BCC="Refused"])}</td>
            <td>{count($data[TBS="NEUTRAL"][BCC="Refused"])}</td>
            <td style="background-color:green">{count($data[TBS="OBJECT"][BCC="Refused"])}</td>
            <td>{count($data[BCC="Refused"])}</td>
            </tr>
            
<tr><th>Total</th>
            <td>{count($data[TBS="SUPPORT"])}</td>
            <td>{count($data[TBS="NEUTRAL"])}</td>
            <td>{count($data[TBS="OBJECT"])}</td>
            <td>{count($data)}</td>
            </tr>
            
    </table>        
      </div>
 
 };
 
 declare function pa:glossary() {
    let $terms := doc("/db/apps/tbs/data/glossary.xml")//term
    return
    <div>
       <h2>Glosssary of Planning Terminology</h2>
       <div>
       This a work in progress to provide visors to the portal with explanations of planning terminology and links to relevant documents.  See also the <a href="http://bishopstonsociety.org.uk/planning">planning section of the Bishopston Society website</a>. All suggestions of suitable content welcome.
       </div>
       {for $term in $terms
        order by $term/name[1]
        return
          <div id="{$term/name[1]}">
             <h3>{$term/name[1]/string()}
                 {
                 if (count($term/name) > 1)
                 then concat( " (", string-join(subsequence($term/name,2),", "),")")
                 else ()
                 }
             </h3>
              <div class="def">
             {for $sa in $term/seealso
              return <div> See also <a href="#{$sa}">{$sa}</a></div>
             }
             
            
                {$term/definition/div}
             {if ($term/link)
              then 
                 <div>
                   <h4>References</h4>
                   {for $link in $term/link
                    return 
                      <div><a href="{$link/url}">{$link/title/string()}</a></div>
                   }
                   
                   </div>
              else ()
              }
              </div>
            </div>
       }
    </div>
 };
 
 declare function pa:link-article-form() {
    <div>
      <form action="{$pa:root}admin/link-article" >
       Enter URL of TBS Article : <input type="text" size="70"  name="url"/>
       <input type="submit" name="mode" value="update"/>
      </form>
   </div>
 };
 
 declare function pa:link-article(){
   let $articles := doc("/db/apps/tbs/data/articles.xml")/articles
   let $url := request:get-parameter("url",())
   let $doc := httpclient:get(xs:anyURI($url),false(),())
   let $title := $doc//head/title
   let $links := 
       $doc//a/@href[starts-with(.,"http://pp.bishopstonsociety.org.uk/Planning/application/")]
   let $datetime := $doc//time[@itemprop="datePublished"]/@datetime/string()
   let $earticle := $articles/article[url=$url]
   let $narticle := 
        element article {
            element url {$url},
            element datatime {$datetime},
            $title,
            for $link in $links
            return 
               element keyval {tokenize($link,'/')[last()]}
        }
   let $update := 
        if ($earticle)
        then update replace $earticle with $narticle
        else update insert $narticle into $articles
   return 
      <div>
        <a href="{$narticle/url}">{$narticle/title/string()}</a>
        <ul>
         {for $keyval in $narticle/keyval
         return <li>{$keyval/string()}</li>
         }
        </ul>
      </div>
 };
      
