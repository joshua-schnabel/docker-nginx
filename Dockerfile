FROM alpine:3.10
LABEL Maintainer="Joshua Schnabel <dev@joshua-schnabel.de>" \
      Description="Lightweight container with Nginx & PHP-FPM 7 based on Alpine Linux for WebApps."

# Update packages
RUN apk update && apk upgrade

# Install tools packages 
RUN apk --no-cache add bash curl supervisor

# Install nginx packages
RUN apk --no-cache add nginx nginx-mod-http-headers-more nginx-mod-http-lua
