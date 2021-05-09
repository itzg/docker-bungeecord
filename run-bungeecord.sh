#!/bin/bash

: ${TYPE:=BUNGEECORD}
: ${MEMORY:=512m}
: ${RCON_JAR_VERSION:=1.0.0}
: ${ENV_VARIABLE_PREFIX:=CFG_}
BUNGEE_HOME=/server
RCON_JAR_URL=https://github.com/orblazer/bungee-rcon/releases/download/v${RCON_JAR_VERSION}/bungee-rcon-${RCON_JAR_VERSION}.jar
download_required=true

function isTrue() {
  local value=${1,,}

  result=

  case ${value} in
  true | on)
    result=0
    ;;
  *)
    result=1
    ;;
  esac

  return ${result}
}

function isDebugging() {
  if isTrue "${DEBUG:-false}"; then
    return 0
  else
    return 1
  fi
}

function handleDebugMode() {
  if isDebugging; then
    set -x
    extraCurlArgs=(-v)
  fi
}

handleDebugMode

echo "Resolving type given ${TYPE}"
case "${TYPE^^}" in
  BUNGEECORD)
    : ${BUNGEE_BASE_URL:=https://ci.md-5.net/job/BungeeCord}
    : ${BUNGEE_JOB_ID:=lastStableBuild}
    : ${BUNGEE_JAR_URL:=${BUNGEE_BASE_URL}/${BUNGEE_JOB_ID}/artifact/bootstrap/target/BungeeCord.jar}
    : ${BUNGEE_JAR_REVISION:=${BUNGEE_JOB_ID}}
    BUNGEE_JAR=$BUNGEE_HOME/${BUNGEE_JAR:=BungeeCord-${BUNGEE_JAR_REVISION}.jar}
  ;;

  WATERFALL)
    # Doc : https://papermc.io/api
    : ${WATERFALL_VERSION:=latest}
    : ${WATERFALL_BUILD_ID:=latest}

    # Retrieve waterfal version
    if [[ ${WATERFALL_VERSION^^} = LATEST ]]; then
      WATERFALL_VERSION=$(curl -fsSL "https://papermc.io/api/v2/projects/waterfall" -H "accept: application/json" | jq -r '.versions[-1]')
      if [ -z $WATERFALL_VERSION ]; then
        echo "ERROR: failed to lookup PaperMC versions"
        exit 1
      fi
    fi

    # Retrieve waterfall build
    if [[ ${WATERFALL_BUILD_ID^^} = LATEST ]]; then
      WATERFALL_BUILD_ID=$(curl -fsSL "https://papermc.io/api/v2/projects/waterfall/versions/${WATERFALL_VERSION}" -H  "accept: application/json" \
        | jq '.builds[-1]')
      if [ -z $WATERFALL_BUILD_ID ]; then
          echo "ERROR: failed to lookup PaperMC build from version ${WATERFALL_VERSION}"
          exit 1
      fi
    fi

    WATERFALL_JAR=$(curl -fsSL "https://papermc.io/api/v2/projects/waterfall/versions/${WATERFALL_VERSION}/builds/${WATERFALL_BUILD_ID}" \
      -H  "accept: application/json" | jq -r '.downloads.application.name')
    if [ -z $WATERFALL_JAR ]; then
      echo "ERROR: failed to lookup PaperMC download file from version=${WATERFALL_VERSION} build=${WATERFALL_BUILD_ID}"
      exit 1
    fi

    BUNGEE_JAR_URL="https://papermc.io/api/v2/projects/waterfall/versions/${WATERFALL_VERSION}/builds/${WATERFALL_BUILD_ID}/downloads/${WATERFALL_JAR}"
    BUNGEE_JAR=$BUNGEE_HOME/${BUNGEE_JAR:=Waterfall-${WATERFALL_VERSION}-${WATERFALL_BUILD_ID}.jar}
  ;;

  VELOCITY)
    : ${VELOCITY_VERSION:=latest}
    BUNGEE_JAR_URL="https://versions.velocitypowered.com/download/${VELOCITY_VERSION}.jar"
    BUNGEE_JAR=$BUNGEE_HOME/Velocity-${VELOCITY_VERSION}.jar
  ;;

  CUSTOM)
    if [[ -v BUNGEE_JAR_URL ]]; then
      echo "Using custom server jar at ${BUNGEE_JAR_URL} ..."
      BUNGEE_JAR=$BUNGEE_HOME/$(basename ${BUNGEE_JAR_URL})
    elif [[ -v BUNGEE_JAR_FILE ]]; then
      BUNGEE_JAR=${BUNGEE_JAR_FILE}
      download_required=false
    else
      echo "BUNGEE_JAR_URL is not properly set to a URL or existing jar file"
      exit 2
    fi
  ;;

  *)
      echo "Invalid type: '$TYPE'"
      echo "Must be: BUNGEECORD, WATERFALL, VELOCITY, CUSTOM"
      exit 1
  ;;
esac

if isTrue "$download_required"; then
  if [ -f "$BUNGEE_JAR" ]; then
    zarg="-z '$BUNGEE_JAR'"
  fi
  echo "Downloading ${BUNGEE_JAR_URL}"
  if ! curl -o "$BUNGEE_JAR" $zarg -fsSL "$BUNGEE_JAR_URL"; then
      echo "ERROR: failed to download" >&2
      exit 2
  fi
fi

if [ -d /plugins ]; then
    echo "Copying BungeeCord plugins over..."
    cp -ru /plugins $BUNGEE_HOME
fi

# If supplied with a URL for a plugin download it.
if [[ "$PLUGINS" ]]; then
for i in ${PLUGINS//,/ }
do
  EFFECTIVE_PLUGIN_URL=$(curl -Ls -o /dev/null -w %{url_effective} $i)
  case "X$EFFECTIVE_PLUGIN_URL" in
    X[Hh][Tt][Tt][Pp]*.jar)
      echo "Downloading plugin via HTTP"
      echo "  from $EFFECTIVE_PLUGIN_URL ..."
      if ! curl -sSL -o /tmp/${EFFECTIVE_PLUGIN_URL##*/} $EFFECTIVE_PLUGIN_URL; then
        echo "ERROR: failed to download from $EFFECTIVE_PLUGIN_URL to /tmp/${EFFECTIVE_PLUGIN_URL##*/}"
        exit 2
      fi

      mkdir -p $BUNGEE_HOME/plugins
      mv /tmp/${EFFECTIVE_PLUGIN_URL##*/} "$BUNGEE_HOME/plugins/${EFFECTIVE_PLUGIN_URL##*/}"
      rm -f /tmp/${EFFECTIVE_PLUGIN_URL##*/}
      ;;
    *)
      echo "Invalid URL given for plugin list: Must be HTTP or HTTPS and a JAR file"
      ;;
  esac
done
fi

# Download rcon plugin
if isTrue "${ENABLE_RCON}" && [[ ! -e $BUNGEE_HOME/plugins/${RCON_JAR_URL##*/} ]]; then
  echo "Downloading rcon plugin"
  mkdir -p $BUNGEE_HOME/plugins/bungee-rcon

  if ! curl -sSL -o "$BUNGEE_HOME/plugins/${RCON_JAR_URL##*/}" $RCON_JAR_URL; then
    echo "ERROR: failed to download from $RCON_JAR_URL to /tmp/${RCON_JAR_URL##*/}"
    exit 2
  fi

  echo "Copy rcon configuration"
  sed -i 's#${PORT}#'"$RCON_PORT"'#g' /tmp/rcon-config.yml
  sed -i 's#${PASSWORD}#'"$RCON_PASSWORD"'#g' /tmp/rcon-config.yml

  mv /tmp/rcon-config.yml "$BUNGEE_HOME/plugins/bungee-rcon/config.yml"
  rm -f /tmp/rcon-config.yml
fi

if [ -d /config ]; then
    echo "Copying BungeeCord configs over..."
    cp -u /config/config.yml "$BUNGEE_HOME/config.yml"

    # Copy other files if avaliable
    # server icon
    if [ -f /config/server-icon.png ]; then
      cp -u /config/server-icon.png "$BUNGEE_HOME/server-icon.png"
    fi
    # custom module list
    if [ -f /config/modules.yml ]; then
      cp -u /config/modules.yml "$BUNGEE_HOME/modules.yml"
    fi
    # Waterfall config
    if [ -f /config/waterfall.yml ]; then
      cp -u /config/waterfall.yml "$BUNGEE_HOME/waterfall.yml"
    fi
    # Velocity config
    if [ -f /config/velocity.toml ]; then
      cp -u /config/velocity.toml "$BUNGEE_HOME/velocity.toml"
    fi
    # Messages
    if [ -f /config/messages.properties ]; then
      cp -u /config/messages.properties "$BUNGEE_HOME/messages.properties"
    fi
fi

if [ -f /var/run/default-config.yml -a ! -f $BUNGEE_HOME/config.yml ]; then
    echo "Installing default configuration"
    cp /var/run/default-config.yml $BUNGEE_HOME/config.yml
    if [ $UID == 0 ]; then
        chown bungeecord: $BUNGEE_HOME/config.yml
    fi
fi

# Replace environment variables in config files
if isTrue "${REPLACE_ENV_VARIABLES}"; then
  echo "Replacing env variables in configs that match the prefix $ENV_VARIABLE_PREFIX..."
  for name in $(compgen -v $ENV_VARIABLE_PREFIX); do
    if [[ $name = *"_FILE" ]]; then
      value=$(<${!name})
      name="${name%_FILE}"
    else
      value=${!name}
    fi

    echo "Replacing $name ..."

    value=${value//\\/\\\\}
    value=${value//#/\\#}

    if isDebugging; then
      findDebug="-print"
    fi

    find /server/ \
        $dirExcludes \
        -type f \
        \( -name "*.yml" -or -name "*.yaml" -or -name "*.toml" -or -name "*.txt" \
          -or -name "*.cfg" -or -name "*.conf" -or -name "*.properties" -or -name "*.hjson" -or -name "*.json" \) \
        $fileExcludes \
        $findDebug \
        -exec sed -i 's#${'"$name"'}#'"$value"'#g' {} \;
  done
fi

if [ $UID == 0 ]; then
  chown -R bungeecord:bungeecord $BUNGEE_HOME
fi

echo "Setting initial memory to ${INIT_MEMORY:-${MEMORY}} and max to ${MAX_MEMORY:-${MEMORY}}"
JVM_OPTS="-Xms${INIT_MEMORY:-${MEMORY}} -Xmx${MAX_MEMORY:-${MEMORY}} ${JVM_OPTS}"

if [ $UID == 0 ]; then
  exec sudo -E -u bungeecord $JAVA_HOME/bin/java $JVM_OPTS -jar "$BUNGEE_JAR" "$@"
else
  exec $JAVA_HOME/bin/java $JVM_OPTS -jar "$BUNGEE_JAR" "$@"
fi
