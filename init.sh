#!/bin/sh
# Unified Road-Warrior (VPS-friendly) — OpenWrt 24.10.x (x86_64)
# bash -c "$(wget -O- https://bit.ly/4ozyiZf)"

# --------- UI helpers ----------
say()  { printf "\033[1;32m[RW]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[RW]\033[0m %s\n" "$*"; }
err()  { printf "\033[1;31m[RW]\033[0m %s\n" "$*"; }

say "=== Firewall setup for remote admin ==="
uci add firewall rule
uci set firewall.@rule[-1].name='Allow-Remote-Admin'
uci set firewall.@rule[-1].src='wan'
uci set firewall.@rule[-1].dest_port='22 80 443'
uci set firewall.@rule[-1].proto='tcp'
uci set firewall.@rule[-1].target='ACCEPT'
uci set firewall.@rule[-1].enabled='1'
uci commit firewall
/etc/init.d/firewall restart

say "=== Enable SSH ==="
uci set dropbear.@dropbear[0].Interface='wan'
uci set dropbear.@dropbear[0].Port='22'
uci commit dropbear
/etc/init.d/dropbear restart
say "SSH done."

check_interface() { ip link show "$1" >/dev/null 2>&1; }
have_bin() { command -v "$1" >/dev/null 2>&1; }

say "=== Auto Setup ==="
say "Checking basic parameters..."

# --------- detection ----------
PUB_DEV="$(ip -4 route show default 2>/dev/null | awk '{print $5; exit}')"
PUB_GW="$( ip -4 route show default 2>/dev/null | awk '{print $3; exit}')"
PUB_IP="$( ip -4 -o addr show dev "${PUB_DEV:-}" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 )"

[ -z "${PUB_DEV:-}" ] && PUB_DEV="br-lan"
[ -z "${PUB_GW:-}" ]  && PUB_GW="$(ip r | awk '/^default/ {print $3; exit}')"
[ -z "${PUB_IP:-}" ]  && PUB_IP="$(ip -4 -o addr | awk '!/127\.0\.0\.1/ {print $4}' | head -n1 | cut -d/ -f1)"

say "Public dev: $PUB_DEV"
say "Public IP : ${PUB_IP:-UNKNOWN}"
say "Public GW : ${PUB_GW:-UNKNOWN}"

if ! check_interface "$PUB_DEV"; then
  err "Public interface $PUB_DEV not found — aborting."
  exit 1
fi

# --------- packages ----------
say "=== Installing base packages ==="
opkg update || warn "opkg update: errors occurred (continuing)"
install_pkg() {
  local p="$1"
  say "Installing: $p"
  opkg install -V1 "$p" >/dev/null 2>&1 || warn "Failed to install $p (continuing)"
}
for p in pptpd kmod-nf-nathelper-extra openssl-util lua-cjson luasocket luasec curl bash jq \
         luci-app-commands ip-full kmod-tun luci-mod-rpc \
         luci-lib-ipkg luci-compat luci-app-homeproxy; do
  install_pkg "$p"
done

say "=== Setting up PPTP server ==="

VPN_POOL="192.168.9.128-254"
VPN_USER="betty"
VPN_PASS="prgrno1"

cat << EOF >> /etc/sysctl.conf
net.netfilter.nf_conntrack_helper=1
EOF
service sysctl restart
 
# Configure firewall
uci rename firewall.@zone[0]="lan"
uci rename firewall.@zone[1]="wan"
uci del_list firewall.lan.device="ppp+"
uci add_list firewall.lan.device="ppp+"
uci -q delete firewall.pptp
uci set firewall.pptp="rule"
uci set firewall.pptp.name="Allow-PPTP"
uci set firewall.pptp.src="wan"
uci set firewall.pptp.dest_port="1723"
uci set firewall.pptp.proto="tcp"
uci set firewall.pptp.target="ACCEPT"
uci commit firewall
service firewall restart

uci set pptpd.pptpd.enabled="1"
uci set pptpd.pptpd.logwtmp="0"
uci set pptpd.pptpd.localip="${VPN_POOL%.*}.1"
uci set pptpd.pptpd.remoteip="${VPN_POOL}"
uci -q delete pptpd.@login[0]
uci set pptpd.client="login"
uci set pptpd.client.username="${VPN_USER}"
uci set pptpd.client.password="${VPN_PASS}"
uci commit pptpd
service pptpd restart

say "PPTP done."

say "=== Config homeproxy ==="
uci set homeproxy.control.bind_interface='eth0'
uci add_list homeproxy.control.listen_interfaces='br-lan'
uci add_list homeproxy.control.listen_interfaces='ppp0'
uci set homeproxy.config.main_udp_node='same'
uci set homeproxy.config.dns_server='1.1.1.2'
uci set homeproxy.config.routing_mode='global'
uci set homeproxy.config.proxy_mode='redirect_tproxy'
uci set homeproxy.config.ipv6_support='1'
uci delete homeproxy.config.routing_port

uci set network.proxy='interface'
uci set network.proxy.proto='none'
uci set network.proxy.device='singtun0'

# Add firewall zone "proxy"
uci add firewall zone
uci set firewall.@zone[-1].name='proxy'
uci set firewall.@zone[-1].input='REJECT'
uci set firewall.@zone[-1].output='ACCEPT'
uci set firewall.@zone[-1].forward='REJECT'
uci set firewall.@zone[-1].network='proxy'
uci set firewall.@zone[-1].masq='1'

# Add LAN -> proxy forwarding
uci add firewall forwarding
uci set firewall.@forwarding[-1].src='lan'
uci set firewall.@forwarding[-1].dest='proxy'

# LAN zone
uci set firewall.lan='zone'
uci set firewall.lan.name='lan'
uci set firewall.lan.input='ACCEPT'
uci set firewall.lan.output='ACCEPT'
uci set firewall.lan.forward='REJECT'
uci set firewall.lan.device='ppp+'
uci set firewall.lan.network='lan'

# WAN zone
uci set firewall.wan='zone'
uci set firewall.wan.name='wan'
uci set firewall.wan.input='REJECT'
uci set firewall.wan.output='ACCEPT'
uci set firewall.wan.forward='REJECT'
uci set firewall.wan.masq='1'
uci set firewall.wan.mtu_fix='1'

# network is a list: 'wan' 'wan6'
uci delete firewall.wan.network 2>/dev/null
uci add_list firewall.wan.network='wan'
uci add_list firewall.wan.network='wan6'

# Save & reload
uci commit network
uci commit homeproxy
uci commit firewall
service homeproxy restart
service network restart
/etc/init.d/firewall reload

say "Homeproxy done."

# ---------- Final information ----------
say "=== SETUP COMPLETED ==="
passwd
