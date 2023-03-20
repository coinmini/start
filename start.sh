#!/bin/bash
set -eou pipefail
sed -i "s@/proc/meminfo@/tmp/meminfo@g" /usr/src/app/src/utils/system.js


# patch DNS to use the ones the host passed to docker
# we grab the top two, so we don't potentially load balance over a ton of resolvers
# IPv4 regexp ref - https://www.shellhacks.com/regex-find-ip-addresses-file-grep/
host_resolvers="$(grep nameserver /etc/resolv.conf | awk '{print $2}' | grep -E '(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)' | head -n2 | tr '\n' ' ')"
if [ -n "$host_resolvers" ]; then
  sed -i'' -e "s/resolver\s.*\s/resolver $host_resolvers/" /etc/nginx/confs/tls_proxy.conf
fi

if [ ! -f "/usr/src/app/shared/nodeId.txt" ]; then
  cat /proc/sys/kernel/random/uuid > /usr/src/app/shared/nodeId.txt
fi

echo "$(date -u) [container] Booting $NETWORK network L1 v$NODE_VERSION"
echo "$(date -u) [container] ID: $(cat /usr/src/app/shared/nodeId.txt)"
echo "$(date -u) [container] CPUs: $(nproc --all)"
echo "$(date -u) [container] Memory: $(awk '(NR<4)' /proc/meminfo | tr -d '  ' | tr '\n' ' ')"
echo "$(date -u) [container] Disk: $(df -h /usr/src/app/shared | awk '(NR>1)')"
[ -f /sys/block/sda/queue/rotational ] && echo "$(date -u) [container] SDD: $([ "$(cat /sys/block/sda/queue/rotational)" == "0" ] && echo 'true' || echo 'false')"
[ -f /sys/block/vda/queue/rotational ] && echo "$(date -u) [container] SDD: $([ "$(cat /sys/block/vda/queue/rotational)" == "0" ] && echo 'true' || echo 'false')"

# Create if not exists
mkdir -p /usr/src/app/shared/ssl
mkdir -p /usr/src/app/shared/nginx_log

L1_CONF_FILE=/etc/nginx/conf.d/L1.conf

# If we have a cert, start nginx with TLS, else without (but always start the shim)
if [ -f "/usr/src/app/shared/ssl/node.crt" ]; then
  echo "$(date -u) [container] SSL config available, starting TLS nginx and node shim";
  cp /etc/nginx/confs/tls_proxy.conf $L1_CONF_FILE;
else
  echo "$(date -u) [container] SSL config unavailable, starting non-TLS nginx and node shim";
  cp /etc/nginx/confs/non_tls_proxy.conf $L1_CONF_FILE;
fi

sed -i "s@\$node_id@$(cat /usr/src/app/shared/nodeId.txt)@g" /etc/nginx/conf.d/shared.conf
sed -i "s@\$node_version@$NODE_VERSION@g" /etc/nginx/conf.d/shared.conf

min_uses=2
if [ $(df -h /usr/src/app/shared | awk '(NR>1) { printf "%d", $5}') -lt 80 ]; then
  min_uses=1;
fi
sed -i "s@\$cache_min_uses@$min_uses@g" /etc/nginx/conf.d/shared.conf


if [ -n "${IPFS_GATEWAY_ORIGIN:-}" ]; then
  sed -i "s@https://ipfs.io;@$IPFS_GATEWAY_ORIGIN;@g" /etc/nginx/conf.d/shared.conf;
fi

nginx

export LASSIE_PORT=7766
export LASSIE_ORIGIN=http://127.0.0.1:$LASSIE_PORT
export LASSIE_EVENT_RECORDER_INSTANCE_ID="$(cat /usr/src/app/shared/nodeId.txt)"
export LASSIE_TEMP_DIRECTORY=/usr/src/app/shared/lassie
export LASSIE_MAX_BLOCKS_PER_REQUEST=10000
export LASSIE_LIBP2P_CONNECTIONS_LOWWATER=2000
export LASSIE_LIBP2P_CONNECTIONS_HIGHWATER=3000
export LASSIE_CONCURRENT_SP_RETRIEVALS=1
export LASSIE_EXPOSE_METRICS=true
export LASSIE_METRICS_PORT=7776
export LASSIE_METRICS_ADDRESS=0.0.0.0
export LASSIE_DISABLE_GRAPHSYNC=true
export LASSIE_EXCLUDE_PROVIDERS=bafzbeibhqavlasjc7dvbiopygwncnrtvjd2xmryk5laib7zyjor6kf3avm

mkdir -p $LASSIE_TEMP_DIRECTORY

if [ "${LASSIE_ORIGIN:-}" != "" ]; then
  lassie daemon &>/dev/null &
  LASSIE_PID=$!

  node --max-old-space-size=4096 /usr/src/app/src/bin/shim.js &
  SHIM_PID=$!

  _quit() {
    kill -INT "$SHIM_PID" 2>/dev/null # trigger shutdown

    wait "$SHIM_PID" # let shim exit itself

    exit $?
  }

  _term() {
    trap _quit SIGINT SIGQUIT # handle next wave of signals

    kill -TERM "$SHIM_PID" 2>/dev/null # trigger deregistration

    wait "$SHIM_PID" # keep shim alive while draining
  }

  trap _term SIGTERM

  wait -n $LASSIE_PID $SHIM_PID
else
  exec node --max-old-space-size=4096 /usr/src/app/src/bin/shim.js
fi
