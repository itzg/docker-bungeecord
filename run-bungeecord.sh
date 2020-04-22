#!/bin/bash

: ${TYPE:=BUNGEECORD}
: ${BUNGEE_HOME:=/server}
: ${MEMORY:=512m}

function isURL {
  local value=$1

  if [[ ${value:0:8} == "https://" || ${value:0:7} == "http://" ]]; then
    return 0
  else
    return 1
  fi
}

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
    : ${BUNGEE_BASE_URL:=https://papermc.io/ci/job/Waterfall/}
    : ${BUNGEE_JOB_ID:=lastStableBuild}
    : ${BUNGEE_JAR_URL:=${BUNGEE_BASE_URL}/${BUNGEE_JOB_ID}/artifact/Waterfall-Proxy/bootstrap/target/Waterfall.jar}
    : ${BUNGEE_JAR_REVISION:=${BUNGEE_JOB_ID}}
    BUNGEE_JAR=$BUNGEE_HOME/${BUNGEE_JAR:=Waterfall-${BUNGEE_JAR_REVISION}.jar}
  ;;

  CUSTOM)
    if isURL ${BUNGEE_JAR_URL}; then
      BUNGEE_JAR=$BUNGEE_HOME/$(basename ${BUNGEE_JAR_URL})
    elif [[ -f ${BUNGEE_JAR_URL} ]]; then
      echo "Using custom server jar at ${BUNGEE_JAR_URL} ..."
      BUNGEE_JAR=${BUNGEE_JAR_URL}
    else
      echo "BUNGEE_JAR_URL is not properly set to a URL or existing jar file"
      exit 2
    fi
  ;;

  *)
      echo "Invalid type: '$TYPE'"
      echo "Must be: BUNGEECORD, WATERFALL, CUSTOM"
      exit 1
  ;;
esac

if [[ ! -e $BUNGEE_JAR ]]; then
    echo "Downloading ${BUNGEE_JAR_URL}"
    if ! curl -o $BUNGEE_JAR -fsSL $BUNGEE_JAR_URL; then
        echo "ERROR: failed to download" >&2
        exit 2
    fi
fi

if [ -d /plugins ]; then
    echo "Copying BungeeCord plugins over..."
    cp -r /plugins $BUNGEE_HOME
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

      mkdir -p /server/plugins
      mv /tmp/${EFFECTIVE_PLUGIN_URL##*/} /server/plugins/${EFFECTIVE_PLUGIN_URL##*/}
      rm -f /tmp/${EFFECTIVE_PLUGIN_URL##*/}
      ;;
    *)
      echo "Invalid URL given for plugin list: Must be HTTP or HTTPS and a JAR file"
      ;;
  esac
done
fi

if [ -d /config ]; then
    echo "Copying BungeeCord configs over..."
    cp -u /config/config.yml "$BUNGEE_HOME/config.yml"
fi

if [ -f /var/run/default-config.yml -a ! -f /server/config.yml ]; then
    echo "Installing default configuration"
    cp /var/run/default-config.yml /server/config.yml
    if [ $UID == 0 ]; then
        chown bungeecord: /server/config.yml
    fi
fi

if [ $UID == 0 ]; then
  chown -R bungeecord:bungeecord $BUNGEE_HOME
fi

echo "Setting initial memory to ${INIT_MEMORY:-${MEMORY}} and max to ${MAX_MEMORY:-${MEMORY}}"
JVM_OPTS="-Xms${INIT_MEMORY:-${MEMORY}} -Xmx${MAX_MEMORY:-${MEMORY}} ${JVM_OPTS}"

if [ $UID == 0 ]; then
  exec sudo -u bungeecord java $JVM_OPTS -jar $BUNGEE_JAR "$@"
else
  exec java $JVM_OPTS -jar $BUNGEE_JAR "$@"
fi
