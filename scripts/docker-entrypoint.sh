#!/bin/bash

set -exo pipefail

# usage: file_env VAR [DEFAULT]
#    ie: file_env 'XYZ_DB_PASSWORD' 'example'
# (will allow for "$XYZ_DB_PASSWORD_FILE" to fill in the value of
#  "$XYZ_DB_PASSWORD" from a file, especially for Docker's secrets feature)
file_env() {
	local var="$1"
	local fileVar="${var}_FILE"
	local def="${2:-}"
	if [ "${!var:-}" ] && [ "${!fileVar:-}" ]; then
		echo >&2 "error: both $var and $fileVar are set (but are exclusive)"
		exit 1
	fi
	local val="$def"
	if [ "${!var:-}" ]; then
		val="${!var}"
	elif [ "${!fileVar:-}" ]; then
		val="$(< "${!fileVar}")"
	fi
	export "$var"="$val"
	unset "$fileVar"
}

_log() {
    echo "$@"
}

_error() {
    _log >&2 "$@"
}

_fail() {
    _error "$@"
    exit 1
}

export ADMIN_USER=$(echo "$ADMIN_USERS" | cut -d, -f1)
export ADMIN_KEY=${ADMIN_KEY:-$(openssl rand -base64 32 | cut -c1-40)}
export PLUGINS=${PLUGINS:-reject}
export AUTH_PROVIDER=${AUTH_PROVIDER:-basic}
export BASE_URL=${BASE_URL:-/api}

file_env 'OAUTH2_CLIENT_SECRET' ''
file_env 'SMTP_PASSWORD' ''
file_env 'SECRET_KEY' "$(< /dev/urandom tr -dc A-Za-z0-9_\!\@\#\$\%\^\&\*\(\)-+= | head -c 32)"

# Validation of authentication parameters
case "$AUTH_PROVIDER" in
    'basic' )
    ;;
    'gitlab' )
        if [ -z "$OAUTH2_CLIENT_ID" ] || [ -z "$OAUTH2_CLIENT_SECRET" ] || [ -z "$GITLAB_URL" ]; then
            _fail "All these env vars must be set: OAUTH2_CLIENT_ID, OAUTH2_CLIENT_SECRET, GITLAB_URL"
        fi
        ALLOWED_GITHUB_ORGS=${ALLOWED_GITHUB_ORGS:-*}
    ;;
    'github' )
        if [ -z "$OAUTH2_CLIENT_ID" ] || [ -z "$OAUTH2_CLIENT_SECRET" ] || [ -z "$GITHUB_URL" ]; then
            _fail "All these env vars must be set: OAUTH2_CLIENT_ID, OAUTH2_CLIENT_SECRET, GITHUB_URL"
        fi
        ALLOWED_GITHUB_ORGS=${ALLOWED_GITHUB_ORGS:-*}
    ;;
    'google' )
        if [ -z "$OAUTH2_CLIENT_ID" ] || [ -z "$OAUTH2_CLIENT_SECRET" ]; then
            _fail "All these env vars must be set: OAUTH2_CLIENT_ID, OAUTH2_CLIENT_SECRET"
        fi
    ;;
    * )
        _fail "Unknown auth provider: $AUTH_PROVIDER"
    ;;
esac

ESC_BASE_URL=$(echo "$BASE_URL" | sed 's/\//\\\//')

# Config for WebUI
SOURCE_WEB_IU_CONF="$ALERTA_WEB_CONF_FILE.source"
cat "$SOURCE_WEB_IU_CONF" \
    | sed -e "s/%BASE_URL%/${ESC_BASE_URL}/g" \
    | sed -e "s/%AUTH_PROVIDER%/${AUTH_PROVIDER}/g" \
    | sed -e "s/%OAUTH_CLIENT_ID%/${OAUTH2_CLIENT_ID}/g" \
    > "$ALERTA_WEB_CONF_FILE"

NGINX_CONF='/etc/nginx/nginx.conf'
NGINX_SOURCE_CONF="$NGINX_CONF.source"

cat "$NGINX_SOURCE_CONF" | sed -e "s/%BASE_URL%/${ESC_BASE_URL}/g" > "$NGINX_CONF"
echo "$?"

# Generate client config
cat > "$ALERTA_CONF_FILE" << EOF
[DEFAULT]
endpoint = http://localhost${BASE_URL}
key = ${ADMIN_KEY}
EOF

# Install plugins
OIFS=$IFS && IFS=','
for plugin in $PLUGINS; do
    if [ $plugin != 'reject' ]; then
        pip install --no-cache-dir git+https://github.com/alerta/alerta-contrib.git#subdirectory=plugins/$plugin
    fi
done
IFS=$OIFS

# Configure housekeeping and heartbeat alerts
echo  "* * * * * sh -c 'MONGODB_URI=$MONGODB_URI MONGO_URI=$MONGO_URI python -u /usr/local/bin/housekeeping_alerts.py 2>&1 >> /var/log/cron_tasks.log'" >> /etc/crontabs/root
echo  "* * * * * sh -c 'ALERTA_CONF_FILE=$ALERTA_CONF_FILE /usr/local/bin/alerta heartbeats --alert 2>&1 >> /var/log/cron_tasks.log'" >> /etc/crontabs/root

if [ -z "$@" ] || [ "${1:0:1}" == "-" ]; then
    set -- supervisord -c "/etc/supervisord.conf" -e "${LOGLEVEL:-INFO}" -j "/var/run/supervisor.pid" -n "$@"
fi

exec "$@"
