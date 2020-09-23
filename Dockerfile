ARG ALPINEVERSION="3.12"

FROM alpine:$ALPINEVERSION

ARG BUILD_DATE=""
ARG VCS_REF=""
ARG VERSION=""
ARG VENDORVERSION=""

LABEL org.label-schema.build-date=$BUILD_DATE \
      org.label-schema.name="jschnabel/nginx" \
      org.label-schema.description="Lightweight Nginx container" \
      org.label-schema.url="https://joshua-schnabel.de" \
      org.label-schema.vcs-ref=$VCS_REF \
      org.label-schema.vcs-url="https://github.com/joshua-schnabel/docker-nginx/" \
      org.label-schema.vendor="Joshua Schnabel" \
      org.label-schema.version=$VERSION \
      org.label-schema.schema-version="1.0" \
      Maintainer="Joshua Schnabel <dev@joshua-schnabel.de>" \
      Description="Lightweight Nginx container." \
      nginx-version=$VENDORVERSION \
      alpine-version=$ALPINEVERSION

ENV DISABLETLS="false"

RUN \
  build_pkgs="build-base linux-headers openssl-dev pcre-dev wget zlib-dev git" && \
  runtime_pkgs="ca-certificates openssl pcre zlib tzdata bash curl coreutils logrotate" && \
  apk --no-cache add ${build_pkgs} ${runtime_pkgs} && \
  rm -rf /var/cache/apk/* && \
  cd /tmp && \
  wget https://github.com/openresty/headers-more-nginx-module/archive/v0.33.tar.gz && \
  tar xzf v0.33.tar.gz && \
  wget https://nginx.org/download/nginx-${VENDORVERSION}.tar.gz && \
  tar xzf nginx-${VENDORVERSION}.tar.gz && \
  cd /tmp/nginx-${VENDORVERSION} && \
  ./configure \
    --prefix=/etc/nginx \
    --sbin-path=/usr/sbin/nginx \
    --conf-path=/etc/nginx/nginx.conf \
    --error-log-path=/var/log/nginx/error.log \
    --http-log-path=/var/log/nginx/access.log \
    --pid-path=/var/run/nginx.pid \
    --lock-path=/var/run/nginx.lock \
    --http-client-body-temp-path=/var/cache/nginx/client_temp \
    --http-proxy-temp-path=/var/cache/nginx/proxy_temp \
    --http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
    --http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
    --http-scgi-temp-path=/var/cache/nginx/scgi_temp \
    --user=nginx \
    --group=nginx \
    --with-http_ssl_module \
    --with-http_realip_module \
    --with-http_addition_module \
    --with-http_sub_module \
    --with-http_dav_module \
    --with-http_flv_module \
    --with-http_mp4_module \
    --with-http_gunzip_module \
    --with-http_gzip_static_module \
    --with-http_random_index_module \
    --with-http_secure_link_module \
    --with-http_stub_status_module \
    --with-http_auth_request_module \
    --with-mail \
    --with-mail_ssl_module \
    --with-file-aio \
    --with-threads \
    --with-stream \
    --with-stream_ssl_module \
    --with-stream_realip_module \
    --with-http_slice_module \
    --with-http_v2_module && \
    --add-module=/tmp/headers-more-nginx-module-0.33 && \
  make && \
  make install && \
  rm -rf /tmp/* && \
  apk del ${build_pkgs} && \
  rm -rf /var/cache/apk/*

# Ensure www-data user exists
# 82 is the standard uid/gid for "www-data" in Alpine
RUN set -x ; \
    addgroup -g 82 -S www-data ; \
    adduser -u 82 -D -S -G www-data www-data && exit 0 ; exit 1

COPY ./CHANGELOG /CHANGELOG
COPY ./nginx /etc/nginx/
COPY ./media /media/
COPY ./logrotate.conf /etc/logrotate.d/nginx

# Setup folders
RUN mkdir -p /media/data && \
    mkdir -p /media/data/certs && \
    mkdir -p /media/data/dhparams && \
    mkdir -p /media/data/logs && \    
    mkdir -p /media/data/sites-enabled && \
    mkdir -p /media/data/streams && \
    chown -R www-data:www-data /media/data && \
    touch /var/log/messages

COPY entrypoint.sh /usr/local/bin/

RUN chmod +x /usr/local/bin/entrypoint.sh

#RUN chown -R www-data:www-data /var/lib/nginx/ && chmod -R 770 /var/lib/nginx/

VOLUME ["/media/data/logs","/media/data/certs","/media/data/dhparams","/media/data/webroot","/media/data/sites-enabled","/media/data/streams"]

HEALTHCHECK CMD curl -f http://localhost:4444/health || exit 1;

STOPSIGNAL SIGTERM

ENTRYPOINT ["entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
