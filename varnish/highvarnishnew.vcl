 backend web { 
     .host = "58.96.181.236"; 
     .port = "80"; 
     .connect_timeout = 20s; 
     .first_byte_timeout = 20s; 
     .between_bytes_timeout = 20s; 
 } 
 
#允许刷新缓存的规则 
acl purgeAllow { 
#     只能本机进行刷新 
     "localhost"; 
	 "58.96.181.236"; 
} 
  
# Below is a commented-out copy of the default VCL logic.  If you 
# redefine any of these subroutines, the built-in logic will be 
# appended to your code. 
 
sub vcl_recv { 
    #判断请求主机,跳转到相应后端服务器 
    if(req.http.host ~ "^(.*)(just518.com)") 
    { 
        set req.backend=web; 
    }else{ 
        error 408 "Hostname not found";  
    } 
     
    #grace缓存过期仍存放 
    # 若backend是健康的，则仅grace 5s，如果backend不健康，则grace 1m。 
    # 这里，5s的目的是为了提高高并发时的吞吐率； 
    # 1m的目的是，backend挂了之后，还能继续服务一段时间，期望backend挂的不要太久。。。 
    if (req.backend.healthy) { 
        set req.grace = 5s; 
    } else { 
        set req.grace = 1m; 
    } 
 
    #刷新缓存的处理 
    if (req.request == "PURGE"){ 
        if(!client.ip ~ purgeAllow) { 
                error 405 "Not allowed."; 
        } 
    #    #转到hit或者miss处理 
        return (lookup); 
    } 
    #不移除一些特定格式的cookie 
    if (!(req.url ~ "wp-(login|admin)")) { 
         #移除cookie,以便能缓存到varnish 
         unset req.http.cookie; 
    }  
    #移除一些特定格式的cookie 
    if (req.url ~ "^(.*)\.(jpg|png|gif|jpeg|flv|bmp|gz|tgz|bz2|tbz|js|css|html|htm|xml)($|\?)" ) { 
         #移除cookie,以便能缓存到varnish 
         unset req.http.cookie; 
    } 
 
   #Accept-Encoding 是浏览器发给服务器,声明浏览器支持的编码类型的 
   #修正客户端的Accept-Encoding头信息 
   #防止个别浏览器发送类似 deflate, gzip 
    if (req.http.Accept-Encoding) { 
        if (req.url ~ "^(.*)\.(jpg|png|gif|jpeg|flv|bmp|gz|tgz|bz2|tbz)($|\?)" ) { 
            remove req.http.Accept-Encoding; 
        }else if (req.http.Accept-Encoding ~ "gzip"){ 
            set req.http.Accept-Encoding = "gzip"; 
        } else if (req.http.Accept-Encoding ~ "deflate"){ 
            set req.http.Accept-Encoding = "deflate"; 
        } else if (req.http.Accept-Encoding ~ "sdch"){ 
            #chrome新增加的压缩 
            set req.http.Accept-Encoding = "sdch"; 
        }else { 
            remove req.http.Accept-Encoding; 
        } 
    }         
    #首次访问增加X-Forwarded-For头信息,方便后端程序获取客户端ip 
    if (req.restarts == 0) { 
        if (req.http.x-forwarded-for) { 
            set req.http.X-Forwarded-For = 
            req.http.X-Forwarded-For + ", " + client.ip; 
        } else { 
            set req.http.X-Forwarded-For = client.ip; 
        } 
    } 
 
   if (req.request != "GET" && 
       req.request != "HEAD" && 
       req.request != "PUT" && 
       req.request != "POST" && 
       req.request != "TRACE" && 
       req.request != "OPTIONS" && 
       req.request != "DELETE") { 
       return (pipe); 
   } 
     if (req.request != "GET" && req.request != "HEAD") { 
         /* We only deal with GET and HEAD by default */ 
         return (pass); 
     } 
     if (req.http.Authorization) { 
         /* Not cacheable by default */ 
         return (pass); 
     } 
     #js,css文件都有Cookie,不能每次都去后台服务器去取 
     #if (req.http.Cookie) { 
     #    /* Not cacheable by default */ 
     #    return (pass); 
     #} 
     
     #如果请求的是动态页面直接转发到后端服务器 
     if (req.url ~ "^(.*)\.(php|jsp|do|aspx|asmx|ashx)($|.*)") { 
          return (pass); 
     } 
     return (lookup); 
 }    
 sub vcl_pipe { 
     # Note that only the first request to the backend will have 
     # X-Forwarded-For set.  If you use X-Forwarded-For and want to 
     # have it set for all requests, make sure to have: 
     # set bereq.http.connection = "close"; 
     # here.  It is not set by default as it might break some broken web 
     # applications, like IIS with NTLM authentication. 
     return (pipe); 
 }    
#放过,让其直接去后台服务器请求数据 
sub vcl_pass { 
     return (pass); 
 }    
sub vcl_hash { 
     hash_data(req.url); 
     if (req.http.host) { 
         hash_data(req.http.host); 
     } else { 
         hash_data(server.ip); 
     } 
     #支持压缩的要增加,防止发送给不支持压缩的浏览器压缩的内容 
     if(req.http.Accept-Encoding){ 
          hash_data(req.http.Accept-Encoding); 
     } 
     return (hash); 
 } 
  
#缓存服务器lookup查找命中:hit 
 sub vcl_hit { 
     #刷新缓存的请求操作,设置TTL为0,返回处理结果代码 
     if (req.request == "PURGE") { 
          set obj.ttl = 0s; 
          error 200 "Purged."; 
      }   
     #缓存服务器命中后(查找到了) 
     return (deliver); 
 }    
#缓存服务器lookup查找没有命中:miss 
sub vcl_miss { 
    #刷新缓存的请求操作, 
    #if (req.request == "PURGE") { 
    #    error 404 "Not in cache."; 
    #}   
    #缓存服务器没有命中(去后台服务器取) 
     return (fetch); 
 }   
#从后台服务器取回数据后,视情况是否进行缓存 
sub vcl_fetch { 
    #不移除一些特定格式的cookie 
    if (!(req.url ~ "wp-(login|admin)")) { 
         #移除cookie,以便能缓存到varnish 
         unset req.http.cookie; 
    } 
    #如果请求的是动态页面直接发转发 
    #动态请求回来的,一定要放在前面处理 
    if (req.url ~ "^(.*)\.(php|jsp|do|aspx|asmx|ashx)($|.*)") { 
        set beresp.http.Cache-Control="no-cache, no-store"; 
        unset beresp.http.Expires; 
        return (deliver); 
    }   
    # 仅当该请求可以缓存时，才设置beresp.grace，若该请求不能被缓存，则不设置beresp.grace 
    if (beresp.ttl > 0s) { 
        set beresp.grace = 1m; 
    }     
     if (beresp.ttl <= 0s || 
         beresp.http.Set-Cookie || 
         beresp.http.Vary == "*") { 
            /* 
             * Mark as "Hit-For-Pass" for the next 2 minutes 
             */ 
            set beresp.ttl = 120 s; 
            #下次请求时不进行lookup,直接pass 
            return (hit_for_pass); 
     }   
    #设置从后台服务器获得的特定格式文件的缓存TTL 
    if (req.url ~ "^(.*)\.(pdf|xls|ppt|doc|docx|xlsx|pptx|chm|rar|zip)($|\?)")      
    { 
        #移除服务器发送的cookie  
        unset beresp.http.Set-Cookie; 
        #加上缓存时间 
        set beresp.ttl = 30d; 
        return (deliver); 
    }else if(req.url ~ "^(.*)\.(bmp|jpeg|jpg|png|gif|svg|png|ico|txt|css|js|html|htm|xml)($|\?)"){ 
        #移除服务器发送的cookie  
        unset beresp.http.Set-Cookie; 
        #加上缓存时间 
        set beresp.ttl = 15d; 
        return (deliver); 
    }else if(req.url ~ "^(.*)\.(mp3|wma|mp4|rmvb|ogg|mov|avi|wmv|mpeg|mpg|dat|3pg|swf|flv|asf)($|\?)"){ 
        #移除服务器发送的cookie  
        unset beresp.http.Set-Cookie; 
        #加上缓存时间 
        set beresp.ttl = 30d; 
        return (deliver); 
    }   
    #从后台服务器返回的response信息中,没有缓存的,不缓存 
    if (beresp.http.Pragma ~"no-cache" || beresp.http.Cache-Control ~"no-cache" || beresp.http.Cache-Control ~"private") { 
            return (deliver); 
    } 
    return (deliver); 
 }    
#缓存服务器发送到客户端前调用 
 sub vcl_deliver { 
    #下面是添加一个Header标识，以判断缓存是否命中。 
    if (obj.hits > 0) { 
        set resp.http.X-Cache = "HIT from cache"; 
       #set resp.http.X-Varnish = "HIT from cache"; 
    } else { 
        set resp.http.X-Cache = "MISS from cache"; 
       #set resp.http.X-Varnish = "MISS from cache"; 
    } 
    #去掉不是必须的header 
    unset resp.http.Vary; 
    unset resp.http.X-Powered-By; 
    unset resp.http.X-AspNet-Version; 
    return (deliver); 
 } 
  
 sub vcl_error { 
     set obj.http.Content-Type = "text/html; charset=utf-8"; 
     set obj.http.Retry-After = "5"; 
     synthetic {" 
 <?xml version="1.0" encoding="utf-8"?> 
 <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" 
  "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd"> 
 <html> 
   <head> 
     <title>"} + obj.status + " " + obj.response + {"</title> 
   </head> 
   <body> 
     <h1>Error "} + obj.status + " " + obj.response + {"</h1> 
     <p>"} + obj.response + {"</p> 
     <h3>Guru Meditation:</h3> 
     <p>XID: "} + req.xid + {"</p> 
     <hr> 
     <p>cache server</p> 
   </body> 
 </html> 
 "}; 
     return (deliver); 
 }    
 sub vcl_init { 
    return (ok); 
 }   
 sub vcl_fini { 
    return (ok); 
 }
