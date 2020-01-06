#! /bin/bash

# 修改清华源
sudo mv /etc/apt/sources.list /etc/apt/sources.list.bak
sudo bash -c "cat > /etc/apt/sources.list <<EOF
deb http://mirrors.tuna.tsinghua.edu.cn/raspbian/raspbian/ buster main non-free contrib
deb-src http://mirrors.tuna.tsinghua.edu.cn/raspbian/raspbian/ buster main non-free contrib
EOF"

sudo mv /etc/apt/sources.list.d/raspi.list /etc/apt/sources.list.d/raspi.list.bak
sudo bash -c "cat > /etc/apt/sources.list.d/raspi.list <<EOF
deb http://mirrors.tuna.tsinghua.edu.cn/raspberrypi/ buster main ui
EOF"

#系统更新
sudo apt-get update
# sudo apt-get upgrade

# 安装vim htop
sudo apt install -y vim htop

# 安装hostapd dnsmasq
sudo apt install -y hostapd dnsmasq

# sudo mv /etc/network/interfaces /etc/network/interfaces.bak

# 固定接口(可选)
#sudo bash -c "cat >> /etc/udev/rules.d/10-network.rules <<EOF
#SUBSYSTEM=="net", ACTION=="add", ATTR{address}=="aa:aa:aa:aa:aa:aa", NAME="wlan0"
#EOF"


# 写入默认wifi(修改)
sudo bash -c "cat >> /etc/wpa_supplicant/wpa_supplicant.conf <<EOF
network={
        ssid=\"A\"
        psk=\"12345678\"
        priority=1
}
EOF"

# 默认ip等

sudo bash -c "cat >> /etc/network/interfaces <<EOF
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
        address 192.168.4.1
        netmask 255.255.255.0

auto wlan0
allow-hotplug wlan0
#iface wlan0 inet dhcp
#wpa-conf /etc/wpa_supplicant/wpa_supplicant.conf
iface wlan0 inet static
        address 192.168.3.1
        netmask 255.255.255.0

auto wlan1
allow-hotplug wlan1
iface wlan1 inet dhcp
wpa-conf /etc/wpa_supplicant/wpa_supplicant.conf

#auto wlan2
#allow-hotplug wlan2
#iface wlan2 inet dhcp
#wpa-conf /etc/wpa_supplicant/wpa_supplicant.conf

EOF"

# 系统优化
# 提高系统限制
sudo bash -c "cat >> /etc/security/limits.conf <<EOF
* soft nofile 51200
* hard nofile 51200
EOF"

# tcp优化等
sudo sudo bash -c "cat >> /etc/sysctl.conf <<EOF
#TCP配置优化(不然你自己根本不知道你在干什么)
fs.file-max = 51200
#提高整个系统的文件限制
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.netdev_max_backlog = 250000
net.core.somaxconn = 4096

net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_tw_recycle = 0
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.ip_local_port_range = 10000 65000
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_max_tw_buckets = 5000
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_mem = 25600 51200 102400
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_congestion_control = bbr
net.ipv4.ip_forward = 1
#END OF LINE
EOF"

sudo  sysctl -p

echo "now system need reboot"