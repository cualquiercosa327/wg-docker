#!/bin/bash
set -x

if [[ -z $WGSECRET ]] || [[ -z $NEXTNODE ]] || [[ -z $CLIENTPREFIX ]] ||
  [[ -z $NODEPREFIX ]] || [[ -z $WHOLENET ]] 
then
  echo WGSECRET, NEXTNODE, CLIENTPREFIX, NODEPREFIX, WHOLENET must be defined. Check your env-file.
  exit
fi

/scripts/detect-apt-proxy.sh

# Install Wireguard. This has to be done dynamically since the kernel
# module depends on the host kernel version.
apt update
apt install -y linux-headers-$(uname -r)
apt install -y wireguard

#setup ip rules
/scripts/iprules $NODEPREFIX $CLIENTPREFIX


echo $WGSECRET >$PRIVATEKEY

babeld -D -I "" -C "ipv6-subtrees true" \
  -C "reflect-kernel-metric true" \
  -C "export-table 10" \
  -C "import-table 11" \
  -C "import-table 12" \
  -C "local-port-readwrite 33123" \
  -C "interface babeldummydne type wired rxcost 10 update-interval 60" \
  -C "default enable-timestamps true" \
  -C "default max-rtt-penalty 96" \
  -C "default rtt-min 25" \
  -C "out ip $NEXTNODE/128 deny" \
  -C "redistribute ip $NEXTNODE/128 deny" \
  -C "redistribute ip $CLIENTPREFIX eq 128  allow" \
  -C "redistribute ip $NODEPREFIX eq 128  allow" \
  -C "redistribute src-ip $WHOLENET ip 2000::/3 allow" \
  -C "redistribute ip ::/0 allow" \
  -C "redistribute ip 2000::/3 allow" \
  -C "redistribute local deny" \
  -C "install pref-src $OWNIP"


ip -6 a a ${OWNIP}/64 dev eth0

mmfd -s /var/run/mmfd.sock &
/usr/local/bin/l3roamd -s /var/run/l3roamd.sock -p $NODEPREFIX -p $CLIENTPREFIX -m babeldummydne -t 11 -a $OWNIP -4 0:0:0:0:0:ffff::/96 &

# start wireguard broker
wg-broker-server &

# Handle shutdown behavior
finish () {
    killall mmfd
    killall l3roamd
    killall babeld
    killall wg-broker-server
# TODO: how do we bring down all irrelevant interfaces
    echo "$(date): Shutting down Wireguard"
    wg-quick down $interface
    exit 0
}

trap finish SIGTERM SIGINT SIGQUIT

if [[ ! -n ${DEBUG} ]]; then
  sleep infinity &
  wait $!
else
  /bin/bash
fi

