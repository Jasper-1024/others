#!/bin/bash
# This script initializes the zsh shell and sets it as the default shell.

# set -e
# set -x

# Detect the OS
OS=$(uname -s)

if [ "${OS}" == "Linux" ]; then
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    fi
fi

# function to install packages
install_packages() {
	local password=$1
	shift

	if [ "${OS}" == "ubuntu" ] || [ "${OS}" == "debian" ]; then
		if [ -n "${password}" ]; then
			echo "${password}" | sudo -S apt update
			echo "${password}" | sudo -S apt install -y "$@"
		else
			sudo apt update
			sudo apt install -y "$@"
		fi
	elif [ "${OS}" == "centos" ]; then
		if [ -n "${password}" ]; then
			echo "${password}" | sudo -S yum update
			echo "${password}" | sudo -S yum install -y "$@"
		else
			sudo yum update
			sudo yum install -y "$@"
		fi
	fi
}

# Now you can use the install_packages function in the rest of your script
install_packages git curl

install_packages  zsh # 安装 zsh

# Check if zsh is installed.
if ! grep -q "$(which zsh)" /etc/shells; then
    echo "zsh is not installed, please check the installation process..."
	exit 1
fi

# 安装 Oh My Zsh | 静默
sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

# 更改主题
sed -i 's/ZSH_THEME="robbyrussell"/ZSH_THEME="ys"/g' ~/.zshrc

sed -i '/ZSH_THEME="ys"/a\
export LS_COLORS=${LS_COLORS}:\x27di=01;37;44\x27
' ~/.zshrc

# 安装命令补全插件
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
# zsh-history
git clone https://github.com/zsh-users/zsh-history-substring-search ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-history-substring-search

# 启用插件 z extract sudo cp git docker docker-compose kubectl zsh-autosuggestions zsh-syntax-highlighting zsh-history-substring-search
sed -i '0,/.*plugins=(git).*/s//plugins=(git z sudo cp extract docker docker-compose kubectl colored-man-pages command-not-found zsh-autosuggestions zsh-syntax-highlighting zsh-history-substring-search)/' ~/.zshrc
# 添加 zsh-completions 补全
sed -i '/^plugins=(git/a\
fpath+=\${ZSH_CUSTOM:-\${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-completions/src
' ~/.zshrc

# 配置 zsh-autosuggestions 插件
cat <<'EOF' >>~/.zshrc

# .zshrc 粘贴文字变慢
# This speeds up pasting w/ autosuggest
# https://github.com/zsh-users/zsh-autosuggestions/issues/238
pasteinit() {
  OLD_SELF_INSERT=${${(s.:.)widgets[self-insert]}[2,3]}
  zle -N self-insert url-quote-magic # I wonder if you'd need `.url-quote-magic`?
}
 
pastefinish() {
  zle -N self-insert $OLD_SELF_INSERT
}
zstyle :bracketed-paste-magic paste-init pasteinit
zstyle :bracketed-paste-magic paste-finish pastefinish
EOF

# 添加 irc-zsh 插件
echo 'source ~/.oh-my-zsh/plugins/incr/incr*.zsh' >>~/.zshrc

# 安装 incr 脚本
# mkdir -p ~/.oh-my-zsh/plugins/incr && tee ~/.oh-my-zsh/plugins/incr/incr-0.2.zsh <<'EOF'
# # Incremental completion for zsh
# # by y.fujii <y-fujii at mimosa-pudica.net>, public domain

mkdir -p ~/.oh-my-zsh/plugins/incr && cat <<'EOF' >~/.oh-my-zsh/plugins/incr/incr-0.2.zsh
# Incremental completion for zsh
# by y.fujii <y-fujii at mimosa-pudica.net>, public domain:

autoload -U compinit
zle -N self-insert self-insert-incr
zle -N vi-cmd-mode-incr
zle -N vi-backward-delete-char-incr
zle -N backward-delete-char-incr
zle -N expand-or-complete-prefix-incr
compinit

bindkey -M viins '^[' vi-cmd-mode-incr
bindkey -M viins '^h' vi-backward-delete-char-incr
bindkey -M viins '^?' vi-backward-delete-char-incr
bindkey -M viins '^i' expand-or-complete-prefix-incr
bindkey -M emacs '^h' backward-delete-char-incr
bindkey -M emacs '^?' backward-delete-char-incr
bindkey -M emacs '^i' expand-or-complete-prefix-incr

unsetopt automenu
compdef -d scp
compdef -d tar
compdef -d make
compdef -d java
compdef -d svn
compdef -d cvs

# TODO:
#     cp dir/

now_predict=0

function limit-completion
{
	if ((compstate[nmatches] <= 1)); then
		zle -M ""
	elif ((compstate[list_lines] > 6)); then
		compstate[list]=""
		zle -M "too many matches."
	fi
}

function correct-prediction
{
	if ((now_predict == 1)); then
		if [[ "$BUFFER" != "$buffer_prd" ]] || ((CURSOR != cursor_org)); then
			now_predict=0
		fi
	fi
}

function remove-prediction
{
	if ((now_predict == 1)); then
		BUFFER="$buffer_org"
		now_predict=0
	fi
}

function show-prediction
{
	# assert(now_predict == 0)
	if
		((PENDING == 0)) &&
		((CURSOR > 1)) &&
		[[ "$PREBUFFER" == "" ]] &&
		[[ "$BUFFER[CURSOR]" != " " ]]
	then
		cursor_org="$CURSOR"
		buffer_org="$BUFFER"
		comppostfuncs=(limit-completion)
		zle complete-word
		cursor_prd="$CURSOR"
		buffer_prd="$BUFFER"
		#if [[ "$buffer_org[1,cursor_org]" == "$buffer_prd[1,cursor_org]" ]]; then
		#	CURSOR="$cursor_org"
		#	if [[ "$buffer_org" != "$buffer_prd" ]] || ((cursor_org != cursor_prd)); then
		#		now_predict=1
		#	fi
		#else
			BUFFER="$buffer_org"
			CURSOR="$cursor_org"
		#fi
		echo -n "\e[32m"
	else
		zle -M ""
	fi
}

function preexec
{
	echo -n "\e[39m"
}

function vi-cmd-mode-incr
{
	correct-prediction
	remove-prediction
	zle vi-cmd-mode
}

function self-insert-incr
{
	correct-prediction
	remove-prediction
	if zle .self-insert; then
		show-prediction
	fi
}

function vi-backward-delete-char-incr
{
	correct-prediction
	remove-prediction
	if zle vi-backward-delete-char; then
		show-prediction
	fi
}

function backward-delete-char-incr
{
	correct-prediction
	remove-prediction
	if zle backward-delete-char; then
		show-prediction
	fi
}

function expand-or-complete-prefix-incr
{
	correct-prediction
	if ((now_predict == 1)); then
		CURSOR="$cursor_prd"
		now_predict=0
		comppostfuncs=(limit-completion)
		zle list-choices
	else
		remove-prediction
		zle expand-or-complete-prefix
	fi
}
EOF

# 更改默认 shell
echo "$1" | sudo -S chsh -s $(which zsh) $USER

echo 'zsh init complete!'


