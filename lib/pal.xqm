module namespace pal ="http://kitwallace.co.uk/lib/pal";

import module namespace pa = "http://kit.wallace.co.uk/lib/pa" at "../lib/pa.xqm";
declare variable $pal:users := doc("/db/apps/tbs/ref/users.xml")/users;
declare variable $pal:secret :="gloucesterrd";

(: ----------------- login --------------------------- :)

declare function pal:login-form($fail) {
 <div>
  <div>Login as an admin user </div>
  {if ($fail)
  then <div>Credentials failed - try again. 
  </div>
  else ()
  }
   <form action="{$pa:root}admin/login" method="post">
     email address<input name="email" size="30"/>
     <input type="password" name="password"/>
     <input type="submit" name="mode" value="login"/>
   </form>
 </div>
};

declare function pal:login() {
  let $email := request:get-parameter("email",())
  let $password := request:get-parameter("password",())
  let $user :=$pal:users/user[email=$email]
  return
    if (exists($user) and util:hash($password,"MD5") = $user/password)
    then 
       let $session := session:set-attribute("user",$user/username)
       let $max := session:set-max-inactive-interval(120*60)
       return true()
     else 
       false()
};

declare function pal:do-login() {
  let $t := pal:login()
  return 
      if ($t)
      then response:redirect-to(xs:anyURI(concat($pa:base,$pa:root,"admin/menu")))
      else 
        pal:login-form(true())
};

declare function pal:do-logout() {
   let $t := pal:logout()
   return  response:redirect-to(xs:anyURI(concat($pa:base,$pa:root,"admin/menu")))
};
declare function pal:user() {
   if (session:exists()) then session:get-attribute("user") else false()
};

declare function pal:logout() {
  let $user := pal:user()
  let $invalidate := session:clear() 
  return
     true()
};

(: ----------------- user registration ---------------------- :)

declare function pal:register-form() {
 <div>
      <div>Fill in the following form to register for admin access. You will need to have been informed about the current secret word.</div>
      <form action="{$pa:root}admin/register" method="post">
        <table>
        <tr><th>Email address</th><td> <input name="email" size="30"/></td></tr>
        <tr><th>Username</th><td> <input name="username" size="30"/></td></tr>
        <tr><th>Password</th><td> <input type="password" name="password"/></td></tr>
        <tr><th>Repeat Password</th><td> <input type="password" name="password2"/> </td></tr>      
        <tr><th>Secret</th><td> <input type="text" name="secret"/>   </td></tr>    
        <tr><th/><td><input type="submit" name="mode" value="register"/></td></tr>
        </table>
     </form>
  </div>
};

declare function pal:register () {
let $email := request:get-parameter("email",())
let $username := request:get-parameter("username",())
let $password := request:get-parameter("password",())
let $password2 := request:get-parameter("password2",())
let $secret := request:get-parameter("secret",())
let $existing-member :=$pal:users[username=$username]
return
if (empty($existing-member) and $username ne "" and  $password ne "" and $password = $password2  and contains ($email,"@") and $secret =$pal:secret)
then  
   let $create := pal:create-member($email,$username,$password)
   return <div>User {$username} registered.  Now <a href="{$pa:root}admin/login-form">login.</a></div>
   
else 
  <div>There is a problem with your registration - please try again</div>
};

declare function pal:create-member($email, $username, $password) {
  let $login := xmldb:login("/db/apps/tbs","tbs","edgerton")
  let $user := 
<user>
   <username>{string($username)}</username>
   <email>{string($email)}</email>
   <password>{util:hash($password,"MD5")}</password>
   <date-joined>{current-date()}</date-joined>
</user>
  let $update := if (exists($pal:users[username=$username]))
                 then <error>membername already exists</error>
                 else update insert $user into $pal:users
                 
  return $update
};