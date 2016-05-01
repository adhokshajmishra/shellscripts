#!/bin/bash

webroot="/usr/share/nginx/html"
wp_latest="http://wordpress.org/latest.zip"
wp_opt="/tmp/wordepress_latest.zip"
wp_home="${webroot}/wordpress"

php='error_page 404 /404.html;
    error_page 500 502 503 504 /50x.html;
    location = /50x.html {
        root /usr/share/nginx/html;
    }
    location ~ \.php$ {
        try_files $uri =404;
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/var/run/php5-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
    }'

println()
{
    if [ "$1" = "error" ]; then
        tput setaf 1
        tput bold
        echo  -n "Error: "
        tput sgr0
        tput setaf 1
        echo $2
        tput sgr0
    elif [ "$1" = "success" ]; then
        tput setaf 10
        tput bold
        echo  -n "Success: "
        tput sgr0
        tput setaf 10
        echo $2
        tput sgr0
    elif [ "$1" = "warning" ]; then
        tput setaf 3
        tput bold
        echo  -n "Warning: "
        tput sgr0
        tput setaf 3
        echo $2
        tput sgr0
    elif [ "$1" = "notif" ]; then
        tput setaf 6
        tput bold
        echo  -n "==> "
        tput sgr0
        tput setaf 6
        echo $2
        tput sgr0
    elif [ "$1" = "default" ] ; then
        tput sgr0
        echo $2
    fi
}

terminate()
{
    if (( $? )); then
        println "error" "Unexpected error in previous command. Exiting..."
        exit 1
    fi
}

install()
{
        if command -v $1 &> /dev/null; then
                println "success" "$1 Installed. Continuing..."
        else
                println "notif" "$1 not found. Installing..."
                sudo apt-get install $2 -y
		terminate
        fi
}

update()
{
    sudo apt-get update -y
}

install_servers()
{
    install nginx nginx
    ## here-string support from shell is assumed.
    sudo debconf-set-selections <<< 'mysql-server mysql-server/root_password password defaultpass'
    sudo debconf-set-selections <<< 'mysql-server mysql-server/root_password_again password defaultpass'
    ## if shell does not support here-strings, comment the above two lines, and uncomment the following two
    # echo "mysql-server-5.5 mysql-server/root_password defaultpass root" | debconf-set-selections
    # echo "mysql-server-5.5 mysql-server/root_password_again defaultpass root" | debconf-set-selections
    install mysql mysql-server
}

install_php()
{
    if [ ! -e /usr/share/php5/mysql/mysql.ini ]; then
        install php5-mysql php5-mysql
    fi
    
    install php5-fpm php5-fpm
    
    cp /etc/php5/fpm/php.ini /tmp/php.tmp
    sed -i -e "s/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/g" /tmp/php.tmp
    sudo mv /tmp/php.tmp /etc/php5/fpm/php.ini
    println "notif" "Restarting php5-fpm service"
    sudo service php5-fpm restart
}

configure_domain()
{
    println "default" "Please enter your domain name."
    echo -n ": "
    read dName
    hName=$dName
    dName=`echo $dName|tr [:punct:] _

    if ! grep --quiet -e "127.0.0.1 '${hName}'" /etc/hosts; then
        println "notif" "Configuring domain"
    	sudo bash -c 'echo "127.0.0.1 '${hName}'" >> /etc/hosts && exit'
    	terminate
    fi
}

configure_ngnix()
{
    cp /etc/nginx/sites-available/default /tmp/default.tmp
    sed -i -e "0,/.*server_name.*/s/.*server_name.*/        server_name $hName;/" /tmp/default.tmp
    if ! grep --quiet -e 'index.html index.php' /etc/nginx/sites-available/default; then
    	sed -i -e "s/index.html/index.html index.php/" /tmp/default.tmp
    fi

    sed -i -e "s#$webroot;#$wp_home;#" /tmp/default.tmp

    if ! grep --quiet -e 'try_files $uri =404;' /etc/nginx/sites-available/default; then
        println "notif" "Configuring ngnix"
        echo "$(ed -s /tmp/default.tmp << eof
66i
${php}
.
wq
eof
)"
    fi
    
    sudo mv /tmp/default.tmp /etc/nginx/sites-available/default
}

install_wordpress()
{
    install wget wget
    wget $wp_latest -O $wp_opt
    terminate

    install unzip unzip
    sudo unzip -a $wp_opt -d $webroot"/"
	terminate
}

configure_db()
{
    db="${dName}_db"
    cmd="create database $db"
    if [ ! -e /var/lib/mysql/$db ]; then
        println "notif" "Creating MySQL database"
        mysql -uroot -pdefaultpass -h localhost -e "${cmd}"
        terminate
    fi
    echo "$(sudo sed -i -e s/database_name_here/$db/g $wp_home/wp-config-sample.php)"
    echo "$(sudo sed -i -e s/username_here/root/g $wp_home/wp-config-sample.php)"
    echo "$(sudo sed -i -e s/password_here/defaultpass/g $wp_home/wp-config-sample.php)"
    sudo mv $wp_home"/wp-config-sample.php" $wp_home"/wp-config.php"
    println warning "PHP + MySQL is configured with default password."
    sudo chown -R www-data:www-data ${webroot}"/" 
    rm -f $wp_opt
    println "notif" "Restarting webserver"
    sudo service nginx restart
    terminate
}

main()
{
    update
    install_servers
    install_php
    configure_domain
    configure_ngnix
    install_wordpress
    configure_db
    terminate
    println "success" "Everything done. You can now test the site by going to 127.0.0.1"
}

main
