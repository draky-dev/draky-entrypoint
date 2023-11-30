#!/usr/bin/env sh

set -e

export DRAKY_ENTRYPOINT_DEBUG="${DRAKY_ENTRYPOINT_DEBUG:-0}"

if [ "${DRAKY_ENTRYPOINT_DEBUG}" = "1" ]; then
  set -x
fi

# Make sure that required env variables are set
export DRAKY_ENTRYPOINT_CORE_BIN_PATH="${DRAKY_ENTRYPOINT_CORE_BIN_PATH:-/draky-entrypoint.core.bin}"
export DRAKY_ENTRYPOINT_CORE_INIT_PATH="${DRAKY_ENTRYPOINT_CORE_INIT_PATH:-/draky-entrypoint.core.init.d}"
export DRAKY_ENTRYPOINT_BIN_PATH="${DRAKY_ENTRYPOINT_BIN_PATH:-/draky-entrypoint.bin}"
export DRAKY_ENTRYPOINT_INIT_PATH="${DRAKY_ENTRYPOINT_INIT_PATH:-/draky-entrypoint.init.d}"
export DRAKY_ENTRYPOINT_RESOURCES_PATH="${DRAKY_ENTRYPOINT_RESOURCES_PATH:-/draky-entrypoint.resources}"

export PATH="$DRAKY_ENTRYPOINT_CORE_BIN_PATH:$PATH"

export DRAKY_TEMPLATE_VAR_PREFIX="${DRAKY_TEMPLATE_VAR_PREFIX:-DRAKY_OVERRIDE_}"

draky_entry_log() {
  if [ -n "$1" ] && [ -n "$2" ]; then
    echo "$0:$1: $2"
  else
    echo "$0: $1"
  fi
}

draky_entry_error() {
  draky_entry_log "$1" "$2" >&2
}

setup_host_user() {
  DRAKY_FUNCTION_NAME=setup_host_user

  if [ -z ${DRAKY_ENTRYPOINT_DO_CREATE_HOST_USER+x} ]; then
    draky_entry_error $DRAKY_FUNCTION_NAME "DRAKY_ENTRYPOINT_DO_CREATE_HOST_USER is unavailable. Skipping creating host user in the container."
    return 0
  fi

  DRAKY_HOST_UID=${DRAKY_ENTRYPOINT_DO_CREATE_HOST_USER}
  DRAKY_HOST_GID=${DRAKY_HOST_GID:-$DRAKY_HOST_UID}

  draky_entry_log $DRAKY_FUNCTION_NAME "Setting up host user."

  export DRAKY_HOST_USERNAME=host
  export DRAKY_HOST_GROUP="${DRAKY_HOST_USERNAME}"

  EXISTING_USER="$(getent passwd "${DRAKY_HOST_UID}" | cut -d: -f1)"

  # If user with the same UID already exists in container, then remove him.
  if [ -n "${EXISTING_USER}" ]; then
    >&2 echo "WARNING: User '${EXISTING_USER}' already exists, so it will be removed."
    deluser "${EXISTING_USER}"
  fi

  # Create host group if fitting group doesn't already exist.
  if [ ! "$(getent group "${DRAKY_HOST_GID}")" ]; then
    echo "Creating the host user's group."
    addgroup --gid "${DRAKY_HOST_GID}" "${DRAKY_HOST_GROUP}"
    else
    DRAKY_HOST_GROUP="$(getent group "${DRAKY_HOST_GID}" | sed -E "s/^([a-z]+):.*$/\1/")"
  fi

  # Create host user.
  echo "Creating the host user."
  adduser --uid "${DRAKY_HOST_UID}" --ingroup "${DRAKY_HOST_GROUP}" --gecos "Docker host" --disabled-password --shell /bin/sh "${DRAKY_HOST_USERNAME}"
  DRAKY_FUNCTION_NAME=
}

override_configuration() {
  DRAKY_FUNCTION_NAME=override_configuration
  draky_entry_log $DRAKY_FUNCTION_NAME "Overriding configuration."

  DRAKY_OVERRIDE_PATH="${DRAKY_ENTRYPOINT_RESOURCES_PATH}/override"

  if [ ! -d "${DRAKY_OVERRIDE_PATH}" ]; then
    draky_entry_error $DRAKY_FUNCTION_NAME "Directory '${DRAKY_OVERRIDE_PATH}' doesn't exist. Skipping."
    return 0
  fi

  find "${DRAKY_OVERRIDE_PATH}" -type f -exec sh -c "
    template() {
      ALL_VARIABLES=\$(env | grep -E \"^${DRAKY_TEMPLATE_VAR_PREFIX}\")
      result=\"\$(cat \${1})\"

      for var in \$ALL_VARIABLES; do
        varname=\$(echo \"\$var\" | sed -rn \"s/(\\w*)=.*/\1/p\")
        varvalue=\$(echo \"\$var\" | sed -rn \"s/\\w*=(.*)/\1/p\")
        # I have no idea why busybox's sed complained about the default '/' separator below. That's why it's changed.
        result=\$(echo \"\${result}\" | sed \"s~\\\${\$varname}~\$varvalue~g\")
      done

      echo \"\$result\"
    }
    TARGET=\"\${1#'${DRAKY_OVERRIDE_PATH}'}\"
    RESULT=\"\$(template \${1})\"
    echo \"Overriding: \${TARGET}\"
    echo \"\${RESULT}\" > \"\${TARGET}\"
  " sh {} \;

  DRAKY_FUNCTION_NAME=
}

setup_host_user
override_configuration

if [ -d "${DRAKY_ENTRYPOINT_CORE_INIT_PATH}" ]; then
  draky_entry_log "Running core initialization scripts."
  for f in "${DRAKY_ENTRYPOINT_CORE_INIT_PATH}"/*; do
  	case "$f" in
  		*.sh)
  		  draky_entry_log "running $f"
  		  if ! "$f"; then
  		    echo "$f: FAILED"
          exit 1
  		  fi
  		;;
  		*) draky_entry_log "ignoring $f" ;;
  	esac
  done
else
  draky_entry_log "Directory '${DRAKY_ENTRYPOINT_CORE_INIT_PATH}' has not been found. Skipping core initialization scripts."
fi

if [ -d "${DRAKY_ENTRYPOINT_INIT_PATH}" ]; then
  draky_entry_log "Running extra initialization scripts."

  for f in "${DRAKY_ENTRYPOINT_INIT_PATH}"/*; do
  	case "$f" in
  		*.sh)
  		  draky_entry_log "running $f"
  		  if ! "$f"; then
  		    draky_entry_error "$f: FAILED"
          exit 1
  		  fi
  		;;
  		*) draky_entry_log "ignoring $f" ;;
  	esac
  done
else
  draky_entry_log "Directory '${DRAKY_ENTRYPOINT_INIT_PATH}' has not been found. Skipping core initialization scripts."
fi

DRAKY_ENTRYPOINT_USER=${DRAKY_ENTRYPOINT_USER:-root}

if [ "$DRAKY_ENTRYPOINT_USER" = 'root' ]; then
  # If user is root, just use the current shell.
  if [ -n "$DRAKY_ENTRYPOINT_ORIGINAL"  ]; then
    exec "$DRAKY_ENTRYPOINT_ORIGINAL" "$@"
  else
    exec "$@"
  fi
  else
  # If user is someone other than root, then create a new login shell to run commands as him, and pass to him env variables.
  ( echo "set -a" ;env | grep -vE "^(PWD=|HOME=|SHLVL=)" ;echo "set +a" ;echo "cd ${PWD}" ) > /etc/profile.d/5-user-vars.draky-entrypoint.sh
  if [ -n "$DRAKY_ENTRYPOINT_ORIGINAL"  ]; then
    exec sudo -i -u "${DRAKY_ENTRYPOINT_USER}" -- "$DRAKY_ENTRYPOINT_ORIGINAL" "$@"
  else
    exec sudo -i -u "${DRAKY_ENTRYPOINT_USER}" -- "$@"
  fi
fi
