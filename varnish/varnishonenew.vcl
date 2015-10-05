import std;
backend web1 {
    .host = "58.96.181.236";
    .port = "80";
    .probe = {
        .url = "/";
        .interval = 10s;
        .timeout = 2s;
        .window = 3;
        .threshold = 3;
    }
}
 
# 允许刷新缓存的ip
acl purgeAllow {
     "localhost";
     "58.96.181.236";
}
 
sub vcl_recv {
    # 刷新缓存设置
    if (req.request == "PURGE") {
        #判断是否允许ip
        if (!client.ip ~ purgeAllow) {
             error 405 "Not allowed.";
        }
        #去缓存中查找
        return (lookup);
    }
 
    std.log("LOG_DEBUG: URL=" + req.url); 
 
    set req.backend = web1;
    if (req.request != "GET" && req.request != "HEAD" && req.request != "PUT" && req.request != "POST" && req.request != "TRACE" && req.request != "OPTIONS" && req.request != "DELETE") {
         /* Non-RFC2616 or CONNECT which is weird. */
         return (pipe);
    }
 
    # 只缓存 GET 和 HEAD 请求
    if (req.request != "GET" && req.request != "HEAD") {
        std.log("LOG_DEBUG: req.request not get!  " + req.request );
        return(pass);
    }
    # http 认证的页面也 pass
#　　if (req.http.Authorization) { 
#        std.log("LOG_DEBUG: req is authorization !");
#        return (pass);
#    }
    if (req.http.Cache-Control ~ "no-cache") {
        std.log("LOG_DEBUG: req is no-cache");
        return (pass);
    }
    # 忽略admin、verify、servlet目录，以.jsp和.do结尾以及带有?的URL,直接从后端服务器读取内容
    if (req.url ~ "^/admin" || req.url ~ "^/verify/" || req.url ~ "^/servlet/" || req.url ~ "\.(jsp|php|do)($|\?)") {
        std.log("url is admin or servlet or jsp|php|do, pass.");
        return (pass);
    }
 
    # 只缓存指定扩展名的请求, 并去除 cookie
    if (req.url ~ "^/[^?]+\.(jpeg|jpg|png|gif|bmp|tif|tiff|ico|wmf|js|css|ejs|swf|txt|zip|exe|html|htm)(\?.*|)$") {
        std.log("*** url is jpeg|jpg|png|gif|ico|js|css|txt|zip|exe|html|htm set cached! ***");
        unset req.http.cookie;
        # 规范请求头,Accept-Encoding 只保留必要的内容
        if (req.http.Accept-Encoding) {
            if (req.url ~ "\.(jpg|png|gif|jpeg)(\?.*|)$") {
                remove req.http.Accept-Encoding;
            } elsif (req.http.Accept-Encoding ~ "gzip") {
                set req.http.Accept-Encoding = "gzip";
            } elsif (req.http.Accept-Encoding ~ "deflate") {
                set req.http.Accept-Encoding = "deflate";
            } else {
                remove req.http.Accept-Encoding;
            }
        }
        return(lookup);
    } else {
        std.log("url is not cached!");
        return (pass);
    }
}
 
sub vcl_hit {
    if (req.request == "PURGE") {    
        set obj.ttl = 0s;    
        error 200 "Purged.";    
    }
    return (deliver);
}
 
sub vcl_miss {
    std.log("################# cache miss ################### url=" + req.url);
    if (req.request == "PURGE") {
        purge;
        error 200 "Purged.";
    }
}
 
sub vcl_fetch {
    # 如果后端服务器返回错误，则进入 saintmode
    if (beresp.status == 500 || beresp.status == 501 || beresp.status == 502 || beresp.status == 503 || beresp.status == 504) {
        std.log("beresp.status error!!! beresp.status=" + beresp.status);
        set req.http.host = "status";
        set beresp.saintmode = 20s;
        return (restart);
    }
    # 如果后端静止缓存, 则跳过
    if (beresp.http.Pragma ~ "no-cache" || beresp.http.Cache-Control ~ "no-cache" || beresp.http.Cache-Control ~ "private") {
        std.log("not allow cached!   beresp.http.Cache-Control=" + beresp.http.Cache-Control);
    return (hit_for_pass);
    }
    if (beresp.ttl <= 0s || beresp.http.Set-Cookie || beresp.http.Vary == "*") {
        /* Mark as "Hit-For-Pass" for the next 2 minutes */
        set beresp.ttl = 120 s;
        return (hit_for_pass);
    }
 
    if (req.request == "GET" && req.url ~ "\.(css|js|ejs|html|htm)$") {
        std.log("gzip is enable.");
        set beresp.do_gzip = true;
        set beresp.ttl = 20s;
    }
 
    if (req.request == "GET" && req.url ~ "^/[^?]+\.(jpeg|jpg|png|gif|bmp|tif|tiff|ico|wmf|js|css|ejs|swf|txt|zip|exe)(\?.*|)$") {
        std.log("url css|js|gif|jpg|jpeg|bmp|png|tiff|tif|ico|swf|exe|zip|bmp|wmf is cache 5m!");
        set beresp.ttl = 5m;
    } elseif (req.request == "GET" && req.url ~ "\.(html|htm)$") {
        set beresp.ttl = 30s;
    } else {
        return (hit_for_pass);
    }
  
    # 如果后端不健康，则先返回缓存数据1分钟
    if (!req.backend.healthy) {
        std.log("eq.backend not healthy! req.grace = 1m");
        set req.grace = 1m;
    } else {
        set req.grace = 30s;
    }
     return (deliver);
}
 
# 发送给客户端
sub vcl_deliver {
    if ( obj.hits > 0 ) {
    set resp.http.X-Cache = "has cache";
    } else {
    #set resp.http.X-Cache = "no cache";
    }
    return (deliver);
}
