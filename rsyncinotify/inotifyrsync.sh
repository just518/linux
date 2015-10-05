#!/bin/bash
host1=118.193.199.9
host2=118.193.207.9
host3=103.40.100.130
host4=103.228.131.198
host5=115.126.62.210
host6=27.126.183.58
src=/etc/nginx/
dst1=proxy1
dst2=proxy2
dst3=proxy3
dst4=proxy4
dst5=proxy5
dst6=proxy6
user1=proxyuser1
user2=proxyuser2
user3=proxyuser3
user3=proxyuser4
user3=proxyuser5
user3=proxyuser6
/usr/local/bin/inotifywait -mrq --timefmt '%d/%m/%y %H:%M' --format '%T %w%f%e' -e close_write,delete,create,attrib  $src \
 | while read files
        do
        /usr/bin/rsync -vzrtopg --delete --progress --password-file=/etc/server.pass $src $user1@$host1::$dst1
        /usr/bin/rsync -vzrtopg --delete --progress --password-file=/etc/server.pass $src $user2@$host2::$dst2
        /usr/bin/rsync -vzrtopg --delete --progress --password-file=/etc/server.pass $src $user3@$host3::$dst3
	/usr/bin/rsync -vzrtopg --delete --progress --password-file=/etc/server.pass $src $user4@$host4::$dst4
	/usr/bin/rsync -vzrtopg --delete --progress --password-file=/etc/server.pass $src $user5@$host5::$dst5
	/usr/bin/rsync -vzrtopg --delete --progress --password-file=/etc/server.pass $src $user6@$host6::$dst6
                echo "${files} was rsynced" >>/tmp/rsync.log 2>&1
        done
