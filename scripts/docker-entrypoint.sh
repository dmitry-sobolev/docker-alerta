#!/bin/bash

set -ex

export ADMIN_USER=$(echo $ADMIN_USERS | cut -d, -f1)
export ADMIN_KEY=${ADMIN_KEY:-$(openssl rand -base64 32 | cut -c1-40)}

python /usr/local/bin/insert_cron_key.py

# Generate server config, if not supplied
if [ ! -f "$ALERTA_SVR_CONF_FILE" ]; then
    cat >$ALERTA_SVR_CONF_FILE << EOF
SECRET_KEY = '$(< /dev/urandom tr -dc A-Za-z0-9_\!\@\#\$\%\^\&\*\(\)-+= | head -c 32)'
PLUGINS = $(python -c "print('${PLUGINS:-reject}'.split(','))")
EOF
else
    PLUGINS=$(python -c "exec(open('$ALERTA_SVR_CONF_FILE')); print(','.join(PLUGINS))")
fi

# Generate client config
cat >/root/alerta.conf << EOF
[DEFAULT]
endpoint = http://localhost/api
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
echo  "* * * * * root MONGODB_URI=$MONGODB_URI MONGO_URI=$MONGO_URI python /usr/local/bin/housekeeping_alerts.py >>/var/log/cron.log 2>&1" >> /etc/crontabs/alerta
echo  "* * * * * root ALERTA_CONF_FILE=$ALERTA_CONF_FILE /usr/local/bin/alerta heartbeats --alert >>/var/log/cron.log 2>&1" >> /etc/crontabs/alerta

if [ -z "$@" ] || [ "${1:0:1}" == "-" ]; then
    set -- supervisord -c "/etc/supervisord.conf" -e "${LOGLEVEL:-DEBUG}" -j "/var/run/supervisor.pid" -n "$@"
fi

exec "$@"
