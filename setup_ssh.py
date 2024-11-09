#!/usr/bin/env python3
import configparser
import getpass
import os
import socket
import sys
from pathlib import Path
from typing import Union

import paramiko
from fabric import Connection

# 使用默认值
_DEFAULT_HOST_NAME = "vps"
_DEFAULT_HOST = "1.1.1.1"
_DEFAULT_PORT = 22
_DEFAULT_USER = "admin"
_DEFAULT_PASSWORD = "admin"
_DEFAULT_KEY_NAME = "id_ed25519"


# ====== 工具函数 ======
def ensure_safe_permissions(path: str, mode: int = 0o600):
    """确保文件权限安全"""
    if os.path.exists(path):
        current_mode = os.stat(path).st_mode & 0o777
        if current_mode != mode:
            os.chmod(path, mode)


def exec(conn: paramiko.SSHClient, commd: str) -> tuple:
    """执行命令

    Args:
        conn (paramiko.SSHClient):
        commd (str):
    Returns:
        tuple: (output, error)
    """
    stdin, stdout, stderr = conn.exec_command(f"{commd}")  # exec command
    output = stdout.readlines()
    error = stderr.readlines()
    return output, error


def exec_sudo(conn: paramiko.SSHClient, commd: str, password: str) -> tuple:
    """执行 sudo 命令

    Args:
        conn (paramiko.SSHClient):
        commd (str): no need sudo
        password (str): sudo password

    Returns:
        tuple: (output, error)
    """
    stdin, stdout, stderr = conn.exec_command(
        f"echo '{password}' | sudo -S {commd}"
    )  # exec sudo command
    stdin.write(f"{password}\n")  # 传入 sudo 密码
    stdin.flush()
    output = stdout.readlines()
    error = stderr.readlines()
    return output, error


def generate_ssh_key(key_path: str) -> bool:
    """生成加强版 SSH 密钥"""
    try:
        import subprocess

        # 使用 ed25519 ,增加 KDF 轮数
        subprocess.run(
            ["ssh-keygen", "-t", "ed25519", "-a", "200", "-f", key_path, "-N", ""],
            check=True,
            capture_output=True,
        )
        return True
    except subprocess.CalledProcessError:
        print("密钥生成失败")
        return False


# ====== SSH 连接相关 ======
def read_ssh_key(key_file):
    """
    读取 SSH key 文件，返回对应的 Paramiko 密钥对象
    """
    try:  # 尝试解析 ed25519 密钥
        key = paramiko.Ed25519Key.from_private_key_file(key_file)  # type: ignore
        return key
    except (
        paramiko.ssh_exception.SSHException
    ):  # 解析失败，尝试解析 RSA 密钥 # type: ignore
        key = paramiko.RSAKey.from_private_key_file(key_file)  # type: ignore
        return key


def connect_ssh(
    host: str, user: str, password=None, key_file=None, port: int = 22
) -> Union[paramiko.SSHClient, None]:
    """连接到 SSH 服务器

    Args:
        host (str): _description_
        user (str): _description_
        password (_type_, optional): _description_. Defaults to None.
        key_filename (_type_, optional): _description_. Defaults to None.
        port (int, optional): _description_. Defaults to 22.

    Returns:
        Union[paramiko.SSHClient, None]:
    """
    # 创建对象:
    client = paramiko.SSHClient()
    # 允许链接不在know_hosts文件中的主机
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())

    try:
        if key_file is not None:
            key = read_ssh_key(key_file)  # 读取密钥文件
            client.connect(
                hostname=host,
                username=user,
                pkey=key,
                port=port,
                timeout=30,  # 超时设置
                banner_timeout=60,
            )
        else:
            client.connect(
                hostname=host,
                username=user,
                password=password,
                port=port,
                timeout=30,
                banner_timeout=60,
            )
        return client
    except paramiko.SSHException as e:
        print("SSH连接失败")
        return None
    except socket.error as e:
        print("网络连接失败")
        return None


# ====== 配置文件管理 ======
def backup_ssh_config(conn: paramiko.SSHClient, password: str) -> bool:
    """备份 SSH 配置文件"""
    backup_path = "/etc/ssh/sshd_config.bak"
    try:
        # 检查是否已有备份
        _, stderr = exec(conn, f"test -f {backup_path}")
        if not stderr:
            print(f"Backup already exists at {backup_path}")
            return True

        # 创建备份
        output, error = exec_sudo(
            conn, f"cp /etc/ssh/sshd_config {backup_path}", password
        )
        if not error:
            print(f"SSH config backed up to {backup_path}")
            return True
        return False
    except Exception as e:
        print(f"Backup failed: {e}")
        return False


def add_ssh_config(
    host: str, hostname: str, user: str, key_file: str, port: int, password: str
):
    config_path = Path.home() / ".ssh" / "config"
    config_path.touch(exist_ok=True)

    existing_config = config_path.read_text()
    existing_blocks = existing_config.split("Host ")[1:]

    for existing_block in existing_blocks:
        lines = existing_block.splitlines()
        if lines[0].strip() == hostname:
            print(f"SSH Config: Host '{hostname}' already exists.")
            return

    new_block = f"""Host {hostname}
    HostName {host}
    User {user}
    IdentityFile {key_file}
    Port {port}
"""

    with open(config_path, "a") as file:
        file.write(new_block)
    print(f"Host '{host}' added to ssh config.")


# ====== 核心业务逻辑 ======
def switch_to_ssh_key(
    host: str, user: str, password: str, port: int, key_name="id_rsa"
) -> bool:
    # 测试 SSH Key 是否可用
    def __test_conn_key(ssh_key_path: str) -> bool:
        conn = connect_ssh(host, user, key_file=ssh_key_path, port=port)
        if conn is not None:
            conn.close()  # 关闭连接
            return True
        else:
            return False

    # 检查公钥是否已经存在于authorized_keys文件中
    def __check_pub_key(conn: paramiko.SSHClient, key_name: str) -> bool:
        stdin, stdout, stderr = conn.exec_command(
            f'grep -q "$(cat ~/.ssh/{key_name}.pub)" ~/.ssh/authorized_keys'
        )
        exit_status = stdout.channel.recv_exit_status()
        return exit_status == 0

    ssh_dir = os.path.expanduser("~/.ssh")
    if not os.path.exists(ssh_dir):
        os.mkdir(ssh_dir, mode=0o700)
    ensure_safe_permissions(ssh_key_path)
    ensure_safe_permissions(ssh_key_path + ".pub", 0o644)

    ssh_key_path = os.path.join(ssh_dir, key_name)

    if not os.path.exists(ssh_key_path):  # 生成密钥
        if not generate_ssh_key(ssh_key_path):
            return False
    else:
        print(f"SSH key {ssh_key_path} already exists, skipping key generation.")

    if __test_conn_key(ssh_key_path):
        print(f"SSH Key: {key_name} aleady add, skip")
        return True

    # 上传公钥到服务器
    with connect_ssh(host, user, password=password, port=port) as conn:  # type: ignore
        conn.exec_command(f"mkdir -p ~/.ssh")  # 创建.ssh目录
        try:  # 上传公钥
            sftp = conn.open_sftp()
            sftp.chdir(".ssh")  # 切换到 ~/
            sftp.put(f"{ssh_key_path}.pub", f"{key_name}.pub")
            sftp.close()
        except Exception as e:
            print(f"Upload SSH Key: {key_name} failed, error: {e}")
            return False
        finally:
            sftp.close()  # type: ignore

        if not __check_pub_key(conn, key_name):  #
            conn.exec_command(f"cat ~/.ssh/{key_name}.pub >> ~/.ssh/authorized_keys")
        conn.exec_command("chmod 700 ~/.ssh")
        conn.exec_command("chmod 600 ~/.ssh/authorized_keys")
        exec_sudo(
            conn,
            "sed -i 's/^#*PubkeyAuthentication .*/PubkeyAuthentication yes/' /etc/ssh/sshd_config",
            password,
        )  # 启用 SSH Key 登录
        exec_sudo(
            conn,
            "sed -i 's/^#*AuthorizedKeysFile .*/AuthorizedKeysFile  .ssh/authorized_keys/' /etc/ssh/sshd_config",
            password,
        )  # 启用 SSH Key 登录
        exec_sudo(conn, "/etc/init.d/ssh restart", password)

        if not backup_ssh_config(conn, password):
            print("Failed to backup SSH config")
            return False

    if __test_conn_key(ssh_key_path):  # Test whether the SSH Key is available
        print(f"SSH Key: {key_name} add success")
        return True
    else:
        print(f"SSH Key: {key_name} add failed")
        return False


def disablePwAuth(
    host: str, user: str, key_file: str, password: str, port: int
) -> bool:
    # 测试 password 是否可用
    def __test_conn_password(password: str) -> bool:
        conn = connect_ssh(host, user, password=password, port=port)
        if conn is not None:
            conn.close()  # 关闭连接
            return True
        else:
            return False

    with connect_ssh(host, user, key_file=key_file, port=port) as conn:  # type: ignore
        exec_sudo(
            conn,
            "sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config",
            password,
        )  # 禁用密码登录
        exec_sudo(conn, "rm -rf /etc/ssh/sshd_config.d/*", password)  # 删除多余配置
        exec_sudo(conn, "systemctl reload sshd", password)  # 重启 SSH 服务

        if not backup_ssh_config(conn, password):
            print("Failed to backup SSH config")
            return False

    return not __test_conn_password(password)  # Test whether the password is available


def execute_script(
    host, user, script: str, mode=0, password: str = "", key_file: str = "", port=22
) -> str:
    _remotScriptpath = (
        "/root/script.sh" if user == "root" else "/home/" + user + "/script.sh"
    )

    with Connection(
        host=host,
        user=user,
        port=port,
        connect_kwargs={"key_filename": key_file},
    ) as c:
        # 上传本地脚本
        c.put(script, _remotScriptpath)
        c.run(f"chmod +x {_remotScriptpath}")

        # 在远程服务器上执行本地脚本
        if mode == 0:
            result = c.run(f"bash {_remotScriptpath}")
        if mode == 1:
            result = c.sudo(
                f"bash {_remotScriptpath}",
                password=password,
                hide=True,
            )
        if mode == 2:
            result = c.run(f"bash {_remotScriptpath} {password}")
        return result.stdout  # type: ignore


# ====== 主程序 ======
if __name__ == "__main__":
    # 交互式输入 服务器参数
    hostname = input(f"Server Host Name ({_DEFAULT_HOST_NAME}): ") or _DEFAULT_HOST_NAME
    host = input(f"Server Host ({_DEFAULT_HOST}): ") or _DEFAULT_HOST
    port = int(input(f"Server Port ({_DEFAULT_PORT}): ") or _DEFAULT_PORT)
    user = input(f"Username ({_DEFAULT_USER}): ") or _DEFAULT_USER
    password = (
        getpass.getpass("Password: ") or _DEFAULT_PASSWORD
    )  # 使用 getpass 避免密码明文显示
    key_name = input(f"SSH Key Name ({_DEFAULT_KEY_NAME}): ") or _DEFAULT_KEY_NAME

    key_file = os.path.join(os.path.expanduser("~/.ssh"), key_name)  # type: ignore

    args = {
        "host": host,
        "user": user,
        "password": password,
        "port": port,
    }

    # 切换到 SSH Key 登录
    if not switch_to_ssh_key(key_name=key_name, **args):
        sys.exit()

    add_ssh_config(hostname=hostname, key_file=key_file, **args)

    if _DEFAULT_USER != "root":  # 非 root 禁用密码登录
        # 禁用密码登录
        if disablePwAuth(key_file=key_file, **args):
            print("diasble password login success")
        else:
            print("diasble password login failed")

    with connect_ssh(key_file=key_file, **args) as conn:  # type: ignore
        exec(conn, "rm ~/script.sh")
        exec(conn, "rm ~/.bash_history")  # 删除 bash_history
        exec(conn, "history -c")  # 删除 bash_history
