# jschnabel/docker-nginx

 ___A lightweight, pre-configured nginx container with HTTP 2.0, TLS1.3 and SSL Labs A rating___

[![Stars](https://img.shields.io/docker/stars/jschnabel/nginx "Stars")](https://hub.docker.com/r/jschnabel/nginx) 
[![Docker Build](https://img.shields.io/docker/cloud/automated/jschnabel/nginx "Docker Build")](https://hub.docker.com/r/jschnabel/nginx) 
[![Docker Build](https://img.shields.io/docker/cloud/build/jschnabel/nginx "Docker Build")](https://hub.docker.com/r/jschnabel/nginx) 
[![Docker Pulls](https://img.shields.io/docker/pulls/jschnabel/nginx "Docker Pulls")](https://hub.docker.com/r/jschnabel/nginx) 
[![License](https://img.shields.io/github/license/joshua-schnabel/docker-nginx "License")](https://github.com/joshua-schnabel/docker-nginx/blob/master/LICENSE) 

## What is nginx?

> Nginx is a web server which can also be used as a reverse proxy, load balancer, mail proxy and HTTP cache. (_Wikipedia_)

## Why would you use this image?

With this image you get a preconfigured nginx image. This image provides support for TLS 1.3 and HTTP 2.0. 

A secure TLS protected server is started without having to change the configuration. A self-signed certificate is created for this purpose. SSL Labs rates the configuration with an A.

![SSL Labs rating](https://raw.githubusercontent.com/joshua-schnabel/docker-nginx/master/doc/image/ssllabs.png) (_Only with custom TLS certificate_)

## Setup

The easiest way to start the server is the following command.

```bash
docker run -d -p 80:80 -p 443:443 jschnabel/nginx
```

You can also use docker-compose.

```yml
services:
   nginx:
     image: jschnabel/nginx
     container_name: nginx
     ports:
       - 80:80
       - 443:443
```

If now the IP address or domain is accessed with the browser, the test page should be visible.

### Hosting some simple static content

To be able to host your own content, just mount a directory under `/media/data/webroot`. 

```yml
services:
   nginx:
     image: jschnabel/nginx
     container_name: nginx
     ports:
       - 80:80
       - 443:443	 
     volumes:
       - /media/docker/volumes/nginx/webroot:/media/data/webroot
```

In this example all data from the host directory `/media/docker/volumes/nginx/webroot` will be published as content.

### Custom SSL Certificate

The configuration shown above will cause a warning window in all browsers. This is due to the self-signed certificate. 
To get a free certificate from Let's Encrypt you have to do the following. First the certbot must be installed on the host. 
Then a certificate can be created using the command below. Please make sure that a directory is mounted by the host as webroot.

```bash
certbot certonly --webroot --webroot-path /media/docker/volumes/nginx/webroot --rsa-key-size 4096 --renew-by-default -d <your.domain>
```

The program will create the following files.

```
/etc/letsencrypt/live/<your.domain>/fullchain.pem
/etc/letsencrypt/live/<your.domain>/privkey.pem
```

Now the certificate and the private key have to be mounted. 

```yml
services:
   nginx:
     image: jschnabel/nginx
     container_name: nginx
     ports:
       - 80:80
       - 443:443	 
     volumes:
       - /media/docker/volumes/nginx/webroot:/media/data/webroot
       - /etc/letsencrypt/live/<your.domain>/fullchain.pem:/media/data/certs/default_cert.pem:ro
       - /etc/letsencrypt/live/<your.domain>/privkey.pem:/media/data/certs/default_key.pem:ro
```

And that was it. Now every browser should accept the connection without problems. 

### Custom Config

In order to provide own configurations, these must be simply mounted under the directory `/media/data/sites-enabled`. 
All configurations from this directory are activated. In this way several domains can be configured.

```yml
services:
   nginx:
     image: jschnabel/nginx
     container_name: nginx
     ports:
       - 80:80
       - 443:443	 
     volumes:
       - /media/docker/volumes/nginx/webroot:/media/data/webroot
       - /etc/letsencrypt/live/<your.domain>/fullchain.pem:/media/data/certs/default_cert.pem:ro
       - /etc/letsencrypt/live/<your.domain>/privkey.pem:/media/data/certs/default_key.pem:ro
       - /media/docker/volumes/nginx/config:/media/data/sites-enabled
```

A custom configuration could look like this.

```nginx
server {
	listen 80;
	listen [::]:80;
	server_name <your.domain>; 
	
	return 301 https://$host$request_uri;
}

server {
	listen 443 ssl http2;
	listen [::]:443 ssl http2;
	server_name <your.domain>; 
	
	ssl_certificate	 /media/data/certs/<your.domain>.pem;
	ssl_certificate_key /media/data/certs/<your.domain>.pem;

	include /media/data/snippets/gzip.conf;
	include /media/data/snippets/header.conf;
	include /media/data/snippets/tls.conf;
	
	location / {
		root   /media/data/webroot/<your.domain>;
		index  index.html index.htm;
	}

	error_page   500 502 503 504  /50x.html;
	location = /50x.html {
		root   /media/data/webroot/<your.domain>;
	}
}

```

## Stuff

In this chapter further settings are described.

### How to gat a SSL Labs A+ rating?

To get an A+ rating on SSL Labs two things have to be done:

1. Add a CAA entry to your DNS with the value `0 issue "letsencrypt.org"` (only if issued via letsencrypt, if not insert your CA)
2. Add the following configuration

```nginx
server {
	listen 80 default_server;
	listen [::]:80 default_server;
	server_name _; 
	
	return 301 https://$host$request_uri;
}

server {
	listen 443 ssl http2 default_server;
	listen [::]:443 ssl http2 default_server;
	server_name _;
	
	ssl_certificate	 /media/data/certs/default_cert.pem;
	ssl_certificate_key /media/data/certs/default_key.pem;

	include /media/data/snippets/gzip.conf;
	include /media/data/snippets/header.conf;
	include /media/data/snippets/tls.conf;
	
	location / {
		root   /media/data/webroot;
		index  index.html index.htm;
	}

	error_page   500 502 503 504  /50x.html;
	location = /50x.html {
		root   /media/data/webroot;
	}
}
```

### How to disable TLS?

Simply add an environment variable named `DISABLETLS` to the container. The value must be `true`.

```yml
services:
   nginx:
     image: jschnabel/nginx
     container_name: nginx
     environment:
       - DISABLETLS="true"
     ports:
       - 80:80
     volumes:
       - /media/docker/volumes/nginx/webroot:/media/data/webroot
```
