
# PYTHON AND WEB STUFF

yum -y groupinstall development
yum -y install https://centos7.iuscommunity.org/ius-release.rpm
yum -y install python36u python36u-pip python36u-devel python36u-setuptools

# SETING UP NGINX
yum -y install epel-release
yum -y install nginx

mkdir /etc/nginx/sites-availible
mkdir /etc/nginx/sites-enabled

# delete the default block, return 404 to any request without the host header 
sed -i '38,60d' /etc/nginx/nginx.conf
sed -i '38iserver { return 404; }\n' /etc/nginx/nginx.conf
sed -i '37iinclude /etc/nginx/sites-enabled/*.site;\n' /etc/nginx/nginx.conf

# basic server config
cat << EOF > /etc/nginx/sites-availible/gunicorn.site
upstream app_server {
        server unix:/run/gunicorn/socket fail_timeout=0;
}

server {
        listen 80;
        server_name localhost;

        location / {
                add_header Cache-Control "no-cache";
                try_files \$uri  @proxy_to_app;
        }
        location @proxy_to_app {
                add_header Cache-Control "no-cache";
                proxy_set_header Host \$host;
                proxy_redirect off;
                proxy_pass http://app_server;
        }
}
EOF

ln -s /etc/nginx/sites-availible/gunicorn.site /etc/nginx/sites-enabled/

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

# setting up gunicorn socke
cat << EOF > /etc/systemd/system/gunicorn.socket
[Unit]
Description=gunicorn socket

[Socket]
ListenStream=/run/gunicorn/socket

[Install]
WantedBy=sockets.target
EOF

# setting up permissions for gunicorn socket
echo "d /run/gunicorn 0755 gunicorn gunicorn -" > /etc/tmpfiles.d/gunicorn.conf

# setting up site location
mkdir -p /var/www/gun/scripts
chcon -Rt httpd_sys_content_t /var/www/gun

# basic app
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

# setting up dir for Gunicorn logs
mkdir -p /var/log/gunicorn
chown -R gunicorn:gunicorn /var/log/gunicorn

# setting up basic gunicorn config file
cat << EOF > /var/www/gun/config
import multiprocessing
# simple configuration
workers = multiprocessing.cpu_count() * 2 + 1
reload = True
accesslog = "/var/log/gunicorn/access.log"
errorlog = "/var/log/gunicorn/error.log"
EOF


# MONGO DB
# Install Mongo and Py3.6 lib
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

# Ingition
systemctl enable nginx
systemctl start nginx

systemctl enable gunicorn.service
systemctl start gunicorn.service
chown -R gunicorn:gunicorn /run/gunicorn

systemctl enable mongod
systemctl start mongod
