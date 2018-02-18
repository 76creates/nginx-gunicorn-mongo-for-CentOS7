yum -y install epel-release
yum -y update

# PYTHON 3.6

yum -y groupinstall development
yum -y install https://centos7.iuscommunity.org/ius-release.rpm
yum -y install python36u python36u-pip python36u-devel python36u-setuptools

# SETING UP NGINX

mkdir /etc/nginx/sites-availible
mkdir /etc/nginx/sites-enabled

cat << EOF > /etc/nginx/sites-availible/gunicorn.site
upstream app_server {
        server unix:/run/gunicorn/socket fail_timeout=0;
}

server {
        listen 80;
        server_name troll.work;

        location / {
                add_header Cache-Control "no-cache";
                try_files $uri  @proxy_to_app;
        }
        location @proxy_to_app {
                add_header Cache-Control "no-cache";
                proxy_set_header Host $host;
                proxy_redirect off;
                proxy_pass http://app_server;
        }
}
EOF

ln -s /etc/nginx/sites-availible/gunicorn.site /etc/nginx/sites-enabled/

# needs working this one bellow
sed -i '38,60s/.*//' /etc/nginx/nginx.conf
sed -i '38iserver { return 404; }' /etc/nginx/nginx.conf
sed -i '39iinclude /etc/nginx/sites-enabled/*.site;' /etc/nginx/nginx.conf

nginx -s reload

# INSTALLING GUNICORN

pip3.6 install gunicorn

useradd gunicorn

# setting up gunicorn service
cat << EOF > /etc/systemd/system/gunicorn.service
[Unit]
Description=gunicorn daemon
Requires=gunicorn.socket
After=network.target

[Service]
PermissionsStartOnly=True
PIDFile=/run/gunicorn/pid
User=gunicorn
Group=gunicorn
WorkingDirectory=/var/www/gun
ExecStart=/usr/bin/gunicorn --pid /run/gunicorn/pid --bind unix:/run/gunicorn/socket -c config app:app
ExecReload=/bin/kill -s HUP \$MAINPID
ExecStop=/bin/kill -s TERM \$MAINPID

[Install]
WantedBy=multi-user.target
EOF

cat << EOF > /etc/systemd/system/gunicorn.socket
[Unit]
Description=gunicorn socket

[Socket]
ListenStream=/run/gunicorn/socket

[Install]
WantedBy=sockets.target
EOF

echo "d /run/gunicorn 0755 gunicorn gunicorn -" > /etc/tmpfiles.d/gunicorn.conf

mkdir -p /var/www/gun/scripts
chcon -Rt httpd_sys_content_t /var/www/gun

cat << EOF > /var/www/gun/app.py
def app(environ, start_response):
    """Simplest possible application object"""
    data = b'Hello, World!\n'
    status = '200 OK'
    response_headers = [
        ('Content-type','text/plain'),
        ('Content-Length', str(len(data)))
    ]
    start_response(status, response_headers)
    return iter([data])
EOF

mkdir -p /var/log/gunicorn
chown -R gunicorn:gunicorn /var/log/gunicorn

cat << EOF > /var/www/gun/config
import multiprocessing

# simple configuration
workers = multiprocessing.cpu_count() * 2 + 1
reload = True
accesslog = "/var/log/gunicorn/access.log"
errorlog = "/var/log/gunicorn/error.log"
EOF


systemctl enable gunicorn.service
systemctl start gunicorn.service
chown -R gunicorn:gunicorn /run/gunicorn

# MONGO DB

cat << EOF > /etc/yum.repos.d/mongodb-org-3.6.repo
[mongodb-org-3.6]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/7/mongodb-org/3.6/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://www.mongodb.org/static/pgp/server-3.6.asc
EOF

yum install -y mongodb-org
pip3.6 install pymongo

systemctl enable mongod
systemctl start mongod
#################################################################################################################################
