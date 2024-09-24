#!/bin/bash

# Set database config from Heroku DATABASE_URL
if [ "$DATABASE_URL" != "" ]; then
    echo "Found database configuration in DATABASE_URL=$DATABASE_URL"

    regex='^postgres://([a-zA-Z0-9_-]+):([a-zA-Z0-9]+)@([a-z0-9.-]+):([[:digit:]]+)/([a-zA-Z0-9_-]+)$'
    if [[ $DATABASE_URL =~ $regex ]]; then
        export DB_ADDR=${BASH_REMATCH[3]}
        export DB_PORT=${BASH_REMATCH[4]}
        export DB_DATABASE=${BASH_REMATCH[5]}
        export DB_USER=${BASH_REMATCH[1]}
        export DB_PASSWORD=${BASH_REMATCH[2]}

        echo "DB_ADDR=$DB_ADDR, DB_PORT=$DB_PORT, DB_DATABASE=$DB_DATABASE, DB_USER=$DB_USER, DB_PASSWORD=$DB_PASSWORD"
        export DB_VENDOR=postgres
    fi
fi

# usage: file_env VAR [DEFAULT]
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

##################
# Add admin user #
##################

file_env 'KEYCLOAK_USER'
file_env 'KEYCLOAK_PASSWORD'

if [ "$KEYCLOAK_USER" ] && [ "$KEYCLOAK_PASSWORD" ]; then
    # Using the new kc.sh command to add an admin user
    /opt/keycloak/bin/kc.sh add-user --user "$KEYCLOAK_USER" --password "$KEYCLOAK_PASSWORD" --roles admin
fi

############
# Hostname #
############

if [ "$KEYCLOAK_HOSTNAME" != "" ]; then
    SYS_PROPS="--hostname-strict=false --hostname=$KEYCLOAK_HOSTNAME"

    if [ "$KEYCLOAK_HTTP_PORT" != "" ]; then
        SYS_PROPS+=" --hostname-http-port=$KEYCLOAK_HTTP_PORT"
    fi

    if [ "$KEYCLOAK_HTTPS_PORT" != "" ]; then
        SYS_PROPS+=" --hostname-https-port=$KEYCLOAK_HTTPS_PORT"
    fi
fi

################
# Realm import #
################

if [ "$KEYCLOAK_IMPORT" ]; then
    SYS_PROPS+=" --import-realm=$KEYCLOAK_IMPORT"
fi

########################
# JGroups bind options #
########################

if [ -z "$BIND" ]; then
    BIND=$(hostname -i)
fi

if [ -z "$BIND_OPTS" ]; then
    for BIND_IP in $BIND
    do
        BIND_OPTS+=" --bind=$BIND_IP --bind-private=$BIND_IP "
    done
fi

SYS_PROPS+=" $BIND_OPTS"

############
# DB setup #
############

file_env 'DB_USER'
file_env 'DB_PASSWORD'

# Lower case DB_VENDOR
DB_VENDOR=$(echo "$DB_VENDOR" | tr 'A-Z' 'a-z')

# Detect DB vendor from default host names
if [ "$DB_VENDOR" == "" ]; then
    if (getent hosts postgres &>/dev/null); then
        export DB_VENDOR="postgres"
    elif (getent hosts mysql &>/dev/null); then
        export DB_VENDOR="mysql"
    elif (getent hosts mariadb &>/dev/null); then
        export DB_VENDOR="mariadb"
    fi
fi

# Default to H2 if DB type not detected
if [ "$DB_VENDOR" == "" ]; then
    export DB_VENDOR="h2"
fi

# Set DB name based on vendor
case "$DB_VENDOR" in
    postgres)
        DB_NAME="PostgreSQL";;
    mysql)
        DB_NAME="MySQL";;
    mariadb)
        DB_NAME="MariaDB";;
    h2)
        DB_NAME="Embedded H2";;
    *)
        echo "Unknown DB vendor $DB_VENDOR"
        exit 1
esac

# Append '?' in the beginning of the string if JDBC_PARAMS value isn't empty
export JDBC_PARAMS=$(echo "${JDBC_PARAMS}" | sed '/^$/! s/^/?/')

# Configure DB
echo "========================================================================="
echo ""
echo "  Using $DB_NAME database"
echo ""
echo "========================================================================="
echo ""

# Database config using kc.sh in Quarkus mode
if [ "$DB_VENDOR" != "h2" ]; then
    export KC_DB="--db=$DB_VENDOR --db-url=jdbc:$DB_VENDOR://$DB_ADDR:$DB_PORT/$DB_DATABASE --db-username=$DB_USER --db-password=$DB_PASSWORD"
fi

##################
# Start Keycloak #
##################

/opt/keycloak/bin/kc.sh start $SYS_PROPS $KC_DB --http-port=$PORT
