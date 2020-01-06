
#! /bin/bash

# 写入 hostapd 配置 这里需要修改
sudo bash -c "cat >/etc/hostapd/hostapd.conf <<EOF
interface=wlan0
driver=nl80211
hw_mode=g
channel=3
ieee80211n=1
wmm_enabled=1
ht_capab=[HT40][SHORT-GI-20][DSSS_CCK-40]
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
ssid=PI
wpa_passphrase=12345678
EOF"

# 追加到dnsmasq.conf
sudo bash -c "cat >>/etc/dnsmasq.conf <<EOF
# Use interface wlan0
interface=wlan0

# Explicitly specify the address to listen on
listen-address=192.168.3.1

# Bind to the interface to make sure we aren't sending things elsewhere
bind-interfaces

# Forward DNS requests to AliDNS
server=223.5.5.5

# Don't forward short names
domain-needed

# Never forward addresses in the non-routed address spaces
bogus-priv

# Assign IP addresses between 192.168.3.50 and 192.168.3.150 with a 12 hour lease time
dhcp-range=192.168.3.50,192.168.3.150,12h
EOF"

#开机启动
sudo systemctl enable dnsmasq
#直接enable可能有错误
sudo systemctl unmask hostapd
sudo systemctl enable hostapd

# iptables
sudo iptables -t nat -A POSTROUTING -o wlan1 -j MASQUERADE
sudo iptables -A FORWARD -i wlan1 -o wlan0 -m state --state RELATED,ESTABLISHED -j ACCEPT
sudo iptables -A FORWARD -i wlan0 -o wlan1 -j ACCEPT

# 备份并设置开机恢复
sudo apt-get install -y iptables-persistent

sudo service netfilter-persistent save

sudo bash -c "cat >>/etc/rc.local <<EOF
iptables-restore < /etc/iptables/rules.v4
EOF"

echo "now system need reboot"


