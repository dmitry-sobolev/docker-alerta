FROM alpine:latest
LABEL maintainer="Dmitry Sobolev <ds@napoleonit.ru>"

RUN addgroup -S alerta && adduser -S -G alerta alerta

ARG APP_ROOT=/opt/app

RUN set -ex; \
  \
  apk add --no-cache --virtual .run-deps \
    bash \
    nginx \
    python \
    git \
    py-pip \
    py-setuptools \
    uwsgi-python \
    supervisor \
    openssl; \
  apk add --no-cache --virtual .build-dep \
    musl-dev \
    gcc \
    make \
    libffi-dev \
    python-dev; \
  pip install --no-cache-dir alerta-server alerta; \
  \
  apk del .build-dep && rm -rf /var/cache/apk/*

RUN set -ex; \
  \
  apk add --no-cache --virtual .fetch-deps \
    ca-certificates; \
  wget -q -O - https://github.com/alerta/angular-alerta-webui/tarball/master | tar zxf -; \
  \
  mkdir -p $APP_ROOT; \
  mv alerta-angular-alerta-webui-*/app /opt; \
  rm -Rf /alerta-angular-alerta-webui-*; \
  mv $APP_ROOT/config.js $APP_ROOT/config.js.orig; \
  \
  apk del .fetch-deps && rm -rf /var/cache/apk/*;

ENV ALERTA_SVR_CONF_FILE "/etc/alerta/alertad.conf"
ENV ALERTA_WEB_CONF_FILE "$APP_ROOT/config.js"
ENV ALERTA_CONF_FILE "/etc/alerta/alerta.conf"

ENV BASE_URL "/api"
ENV AUTH_PROVIDER "basic"
ENV OAUTH2_CLIENT_ID ""

COPY configs/uwsgi.ini /etc/alerta/uwsgi.ini
COPY configs/web_config.js $APP_ROOT/config.js.source
COPY configs/nginx.conf /etc/nginx/nginx.conf.source
COPY configs/supervisor.d/* /etc/supervisor.d/

COPY scripts/* /usr/local/bin/

RUN set -ex; \
  \
  mkdir -p /etc/alerta; \
  echo "from alerta.app import app" > /etc/alerta/wsgi.py; \
  chmod +x /usr/local/bin/docker-entrypoint.sh; \
  chmod +x /usr/local/bin/alerta_key.py; \
  chmod +x /usr/local/bin/housekeeping_alerts.py; \
  chmod +x /usr/local/bin/supervisor_killer

EXPOSE 80

ENTRYPOINT ["docker-entrypoint.sh"]
