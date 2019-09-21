FROM alpine:3.10
LABEL Maintainer="Joshua Schnabel <dev@joshua-schnabel.de>" \
      Description="Lightweight container with Nginx."

# Update packages
RUN apk update && apk upgrade

# Install tools packages 
RUN apk --no-cache add bash curl

# Install nginx packages
RUN apk --no-cache add nginx nginx-mod-http-headers-more nginx-mod-http-lua

# Setup document root
RUN mkdir -p /media/webroot

VOLUME /media/webroot
VOLUME /etc/nginx

STOPSIGNAL SIGTERM
CMD ["nginx", "-g", "daemon off;"]
