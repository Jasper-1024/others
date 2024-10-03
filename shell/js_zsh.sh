#!/bin/bash
# This script initializes the zsh shell and sets it as the default shell.

set -e # Exit immediately if a command exits with a non-zero status.
set -x

# Detect the OS
OS=""
if [ -f /etc/os-release ]; then
	. /etc/os-release
	OS=$ID
elif [ -f /etc/redhat-release ]; then
	OS="rhel"
fi

# Function to check sudo access
check_sudo() {
	if sudo -n true 2>/dev/null; then
		echo "Sudo access available without password."
		return 0
	else
		return 1
	fi
}

# Function to install packages
install_packages() {
	local use_sudo=""
	if [ "$EUID" -ne 0 ]; then
		use_sudo="sudo"
	fi

	case $OS in
	debian | ubuntu)
		$use_sudo apt update
		$use_sudo apt install -y "$@"
		;;
	rocky | centos | rhel)
		$use_sudo yum update -y
		$use_sudo yum install -y "$@"
		;;
	*)
		echo "Unsupported operating system: $OS"
		exit 1
		;;
	esac
}

# 检查是否以 root 身份运行
if [ "$EUID" -eq 0 ]; then
	echo "Running as root. Proceeding without sudo."
else
	# 检查是否提供了 sudo 密码
	if [ -z "$1" ]; then
		echo "Sudo password not provided. Exiting."
		exit 1
	else
		sudo_password="$1"
		if echo "$sudo_password" | sudo -S true 2>/dev/null; then
			echo "Sudo access granted."
			export SUDO_ASKPASS="$(which ssh-askpass)"
			export SUDO_PASSWORD="$sudo_password"
		else
			echo "Invalid sudo password or no sudo privileges. Exiting."
			exit 1
		fi
	fi
fi

# Verify installations
for pkg in git curl; do
	if ! command -v $pkg &>/dev/null; then
		echo "$pkg is not installed."
		install_packages $pkg
	fi
done

# Check if zsh is installed.
if ! command -v zsh &>/dev/null; then
	echo "zsh is not installed. Installing zsh..."
	install_packages zsh
fi

echo "git, curl, and zsh have been successfully installed."

# 检查 Oh My Zsh 是否已经安装
if [ -d "$HOME/.oh-my-zsh" ]; then
	echo "Oh My Zsh is already installed."
else
	# 安装 Oh My Zsh | 静默
	sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
	echo "Oh My Zsh has been successfully installed."
fi

if [ -d ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k ]; then
	echo "Powerlevel10k theme is already installed."
else
	git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k
fi

# 更改主题 powerlevel10k
sed -i 's/ZSH_THEME="robbyrussell"/ZSH_THEME="powerlevel10k\/powerlevel10k"/g' ~/.zshrc

# 加载 p10k 配置 | not ready
# if [ -f ~/.p10k.zsh ]; then
# 	rm -f ~/.p10k.zsh
# fi
# curl -fsSL https://raw.githubusercontent.com/Jasper-1024/others/refs/heads/master/shell/.p10k.zsh >~/.p10k.zsh

# 默认颜色
# 默认颜色
if ! grep -q 'export LS_COLORS=${LS_COLORS}:\x27di=01;37;44\x27' ~/.zshrc; then
	sed -i '/ZSH_THEME="powerlevel10k\/powerlevel10k"/a\
export LS_COLORS=${LS_COLORS}:\x27di=01;37;44\x27
' ~/.zshrc
fi

# if custom/plugins 已经存在
plugins=("zsh-autosuggestions" "zsh-syntax-highlighting" "zsh-history-substring-search" "zsh-completions")
for plugin in "${plugins[@]}"; do
	plugin_path="$HOME/.oh-my-zsh/custom/plugins/$plugin"
	if [ -d "$plugin_path" ]; then
		echo "Removing existing $plugin plugin"
		rm -rf "$plugin_path"
	fi
done

# 安装命令补全插件
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
# zsh-history
git clone https://github.com/zsh-users/zsh-history-substring-search ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-history-substring-search
# zsh-completions
git clone https://github.com/zsh-users/zsh-completions ${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-completions

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

echo "$SUDO_PASSWORD" | sudo -S chsh -s $(which zsh) $USER

# # 更改默认 shell
# change_default_shell_to_zsh() {
# 	local zsh_path=$(which zsh)
# 	if [ -z "$zsh_path" ]; then
# 		echo "Error: zsh is not installed or not in PATH."
# 		return 1
# 	fi

# 	# Check if zsh is already in /etc/shells
# 	if ! grep -q "^$zsh_path$" /etc/shells; then
# 		echo "Adding $zsh_path to /etc/shells..."
# 		echo "$zsh_path" | sudo tee -a /etc/shells >/dev/null
# 	fi

# 	# Change the default shell
# 	if [ "$SHELL" != "$zsh_path" ]; then
# 		echo "Changing default shell to zsh..."
# 		if chsh -s "$zsh_path"; then
# 			echo "Default shell changed to zsh successfully."
# 			export SHELL="$zsh_path"
# 		else
# 			echo "Failed to change default shell. Please run 'chsh -s $(which zsh)' manually."
# 			return 1
# 		fi
# 	else
# 		echo "zsh is already the default shell."
# 	fi

# 	# Remind user to log out and log back in
# 	echo "Please log out and log back in for the changes to take effect."
# }

# # Call the function to change the default shell
# change_default_shell_to_zsh
