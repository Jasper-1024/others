#!/bin/bash
#!/usr/bin/expect

# function ssh-key(){
#   chmod 700 ~/.ssh
#   chmod 600 ~/.ssh/authorized_keys
#   echo "$password" | sed -i "s/#PubkeyAuthentication/PubkeyAuthentication/g" /etc/ssh/sshd_config
#   echo "$password" | sed -i "s/#AuthorizedKeysFile/AuthorizedKeysFile/g" /etc/ssh/sshd_config
#   echo "$password" | /etc/init.d/ssh restart
# }

set -x

read  -erp "ip adress: " ip || exit 1

read -t 5 -erp "port(default 22): " port
port=${port:-22}

read -t 5  -erp "user(default root): " user
user=${user:-"root"}

read -t 5 -erp "password(default 123456): " password
password=${password:-"123456"}

read -t 5  -erp "ssh keyName(default key): " key
key=${key:-"key"}

# echo "$ip $port $user $password $key"

ssh-keygen -b 4096 -t ed25519 -N '' -f "$HOME/.ssh/$key"

cd "$HOME/.ssh/" || exit 2

sshpass -p "$password" ssh-copy-id -i "$key.pub" -p "$port" "$user@$ip"

sshpass -p "$password" ssh -p "$port" "$user@$ip" << _ssh-key_
  set -x
  cd ~/
  chmod 700 ~/.ssh
  chmod 600 ~/.ssh/authorized_keys
  echo "$password" | sudo -S sed -i "s/#PubkeyAuthentication/PubkeyAuthentication/g" /etc/ssh/sshd_config
  echo "$password" | sudo -S sed -i "s/#AuthorizedKeysFile/AuthorizedKeysFile/g" /etc/ssh/sshd_config
  echo "$password" | sudo -S /etc/init.d/ssh restart
_ssh-key_

cat > ~/.ssh/config << _ssh-config_
# 关键词
Host $key
  # 主机地址
  HostName $ip
  # 用户名
  User $user
  # 认证文件
  IdentityFile ~/.ssh/$key
  # 指定端口
  Port $port
_ssh-config_


sshpass -p "$password" ssh -p "$port" "$user@$ip" << _ssh-key_
  echo "$password" | sudo -S apt-get install fail2ban
  echo "$password" | sudo -S service fail2ban restart
  echo "$password" | sudo -S cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
  echo "$password" | sudo -S sed -i "/^\[sshd\]/a\
  enabled = true
  " /etc/fail2ban/jail.local
  echo "$password" | sudo -S service fail2ban restart
_ssh-key_

sshpass -p "$password" ssh -p "$port" "$user@$ip" << _ssh-key_
  rm -fv csf.tgz
  wget http://download.configserver.com/csf.tgz
  tar -xzf csf.tgz
  cd csf
  echo "$password" | sudo -S sh install.sh
_ssh-key_

set +x


