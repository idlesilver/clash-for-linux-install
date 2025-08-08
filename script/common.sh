# shellcheck disable=SC2148
# shellcheck disable=SC2034
# shellcheck disable=SC2155
[ -n "$BASH_VERSION" ] && set +o noglob
[ -n "$ZSH_VERSION" ] && setopt glob no_nomatch

URL_GH_PROXY='https://gh-proxy.com/'
URL_CLASH_UI="http://board.zash.run.place"

SCRIPT_BASE_DIR='./script'
SCRIPT_FISH="${SCRIPT_BASE_DIR}/clashctl.fish"

RESOURCES_BASE_DIR='./resources'
RESOURCES_BIN_DIR="${RESOURCES_BASE_DIR}/bin"
RESOURCES_CONFIG="${RESOURCES_BASE_DIR}/config.yaml"
RESOURCES_CONFIG_MIXIN="${RESOURCES_BASE_DIR}/mixin.yaml"

ZIP_BASE_DIR="${RESOURCES_BASE_DIR}/zip"
ZIP_CLASH=$(echo ${ZIP_BASE_DIR}/clash*)
ZIP_MIHOMO=$(echo ${ZIP_BASE_DIR}/mihomo*)
ZIP_YQ=$(echo ${ZIP_BASE_DIR}/yq*)
ZIP_SUBCONVERTER=$(echo ${ZIP_BASE_DIR}/subconverter*)
ZIP_UI="${ZIP_BASE_DIR}/yacd.tar.xz"

CLASH_BASE_DIR='/opt/clash'
CLASH_SCRIPT_DIR="${CLASH_BASE_DIR}/$(basename $SCRIPT_BASE_DIR)"
CLASH_CONFIG_URL="${CLASH_BASE_DIR}/url"
CLASH_CONFIG_RAW="${CLASH_BASE_DIR}/$(basename $RESOURCES_CONFIG)"
CLASH_CONFIG_RAW_BAK="${CLASH_CONFIG_RAW}.bak"
CLASH_CONFIG_MIXIN="${CLASH_BASE_DIR}/$(basename $RESOURCES_CONFIG_MIXIN)"
CLASH_CONFIG_RUNTIME="${CLASH_BASE_DIR}/runtime.yaml"
CLASH_UPDATE_LOG="${CLASH_BASE_DIR}/clashupdate.log"

_set_var() {
    local user=$USER
    local home=$HOME
    [ -n "$SUDO_USER" ] && {
        user=$SUDO_USER
        home=$(awk -F: -v user="$SUDO_USER" '$1==user{print $6}' /etc/passwd)
    }

    [ -n "$BASH_VERSION" ] && {
        _SHELL=bash
    }
    [ -n "$ZSH_VERSION" ] && {
        _SHELL=zsh
    }
    [ -n "$fish_version" ] && {
        _SHELL=fish
    }

    # rc文件路径
    command -v bash >&/dev/null && {
        SHELL_RC_BASH="${home}/.bashrc"
    }
    command -v zsh >&/dev/null && {
        SHELL_RC_ZSH="${home}/.zshrc"
    }
    command -v fish >&/dev/null && {
        SHELL_RC_FISH="${home}/.config/fish/conf.d/clashctl.fish"
    }

    # 定时任务路径
    local os_info=$(cat /etc/os-release)
    echo "$os_info" | grep -iqsE "rhel|centos" && CLASH_CRON_TAB="/var/spool/cron/$user"
    echo "$os_info" | grep -iqsE "debian|ubuntu" && CLASH_CRON_TAB="/var/spool/cron/crontabs/$user"
}
_set_var

# shellcheck disable=SC2120
_set_bin() {
    local bin_base_dir="${CLASH_BASE_DIR}/bin"
    [ -n "$1" ] && bin_base_dir=$1
    BIN_CLASH="${bin_base_dir}/clash"
    BIN_MIHOMO="${bin_base_dir}/mihomo"
    BIN_YQ="${bin_base_dir}/yq"
    BIN_SUBCONVERTER_DIR="${bin_base_dir}/subconverter"
    BIN_SUBCONVERTER_CONFIG="$BIN_SUBCONVERTER_DIR/pref.yml"
    BIN_SUBCONVERTER_PORT="25500"
    BIN_SUBCONVERTER="${BIN_SUBCONVERTER_DIR}/subconverter"
    BIN_SUBCONVERTER_LOG="${BIN_SUBCONVERTER_DIR}/latest.log"

    [ -f "$BIN_CLASH" ] && {
        BIN_KERNEL=$BIN_CLASH
    }
    [ -f "$BIN_MIHOMO" ] && {
        BIN_KERNEL=$BIN_MIHOMO
    }
    BIN_KERNEL_NAME=$(basename "$BIN_KERNEL")
}
_set_bin

_set_rc() {
    [ "$1" = "unset" ] && {
        sed -i "\|$CLASH_SCRIPT_DIR|d" "$SHELL_RC_BASH" "$SHELL_RC_ZSH" 2>/dev/null
        rm -f "$SHELL_RC_FISH" 2>/dev/null
        return
    }

    echo "source $CLASH_SCRIPT_DIR/common.sh && source $CLASH_SCRIPT_DIR/clashctl.sh && watch_proxy" |
        tee -a "$SHELL_RC_BASH" "$SHELL_RC_ZSH" >&/dev/null
    [ -n "$SHELL_RC_FISH" ] && /usr/bin/install $SCRIPT_FISH "$SHELL_RC_FISH"
}

# 默认集成、安装mihomo内核
# 移除/删除mihomo：下载安装clash内核
function _get_kernel() {
    [ -f "$ZIP_CLASH" ] && {
        ZIP_KERNEL=$ZIP_CLASH
        BIN_KERNEL=$BIN_CLASH
    }

    [ -f "$ZIP_MIHOMO" ] && {
        ZIP_KERNEL=$ZIP_MIHOMO
        BIN_KERNEL=$BIN_MIHOMO
    }

    [ ! -f "$ZIP_MIHOMO" ] && [ ! -f "$ZIP_CLASH" ] && {
        local arch=$(uname -m)
        _failcat "${ZIP_BASE_DIR}：未检测到可用的内核压缩包"
        _download_clash "$arch"
        ZIP_KERNEL=$ZIP_CLASH
        BIN_KERNEL=$BIN_CLASH
    }

    BIN_KERNEL_NAME=$(basename "$BIN_KERNEL")
    _okcat "安装内核：$BIN_KERNEL_NAME"
}

_get_random_port() {
    local randomPort=$(shuf -i 1024-65535 -n 1)
    ! _is_bind "$randomPort" && { echo "$randomPort" && return; }
    _get_random_port
}

function _get_proxy_port() {
    local mixed_port=$(sudo "$BIN_YQ" '.mixed-port // ""' $CLASH_CONFIG_RUNTIME)
    MIXED_PORT=${mixed_port:-7890}

    _is_already_in_use "$MIXED_PORT" "$BIN_KERNEL_NAME" && {
        local newPort=$(_get_random_port)
        local msg="端口占用：${MIXED_PORT} 🎲 随机分配：$newPort"
        sudo "$BIN_YQ" -i ".mixed-port = $newPort" $CLASH_CONFIG_RUNTIME
        MIXED_PORT=$newPort
        _failcat '🎯' "$msg"
    }
}

function _get_ui_port() {
    local ext_addr=$(sudo "$BIN_YQ" '.external-controller // ""' $CLASH_CONFIG_RUNTIME)
    local ext_port=${ext_addr##*:}
    UI_PORT=${ext_port:-9090}

    _is_already_in_use "$UI_PORT" "$BIN_KERNEL_NAME" && {
        local newPort=$(_get_random_port)
        local msg="端口占用：${UI_PORT} 🎲 随机分配：$newPort"
        sudo "$BIN_YQ" -i ".external-controller = \"0.0.0.0:$newPort\"" $CLASH_CONFIG_RUNTIME
        UI_PORT=$newPort
        _failcat '🎯' "$msg"
    }
}

_get_color() {
    local hex="${1#\#}"
    local r=$((16#${hex:0:2}))
    local g=$((16#${hex:2:2}))
    local b=$((16#${hex:4:2}))
    printf "\e[38;2;%d;%d;%dm" "$r" "$g" "$b"
}
_get_color_msg() {
    local color=$(_get_color "$1")
    local msg=$2
    local reset="\033[0m"
    printf "%b%s%b\n" "$color" "$msg" "$reset"
}

function _okcat() {
    local color=#c8d6e5
    local emoji=😼
    [ $# -gt 1 ] && emoji=$1 && shift
    local msg="${emoji} $1"
    _get_color_msg "$color" "$msg" && return 0
}

function _failcat() {
    local color=#fd79a8
    local emoji=😾
    [ $# -gt 1 ] && emoji=$1 && shift
    local msg="${emoji} $1"
    _get_color_msg "$color" "$msg" >&2 && return 1
}

function _quit() {
    local user=root
    [ -n "$SUDO_USER" ] && user=$SUDO_USER
    exec sudo -u "$user" -- "$_SHELL" -i
}

function _error_quit() {
    [ $# -gt 0 ] && {
        local color=#f92f60
        local emoji=📢
        [ $# -gt 1 ] && emoji=$1 && shift
        local msg="${emoji} $1"
        _get_color_msg "$color" "$msg"
    }
    exec $_SHELL -i
}

_is_bind() {
    local port=$1
    { sudo ss -lnptu || sudo netstat -lnptu; } | grep ":${port}\b"
}

_is_already_in_use() {
    local port=$1
    local progress=$2
    _is_bind "$port" | grep -qs -v "$progress"
}

function _is_root() {
    [ "$(whoami)" = "root" ]
}

function _valid_env() {
    _is_root || _error_quit "需要 root 或 sudo 权限执行"
    [ -n "$ZSH_VERSION" ] && [ -n "$BASH_VERSION" ] && _error_quit "仅支持：bash、zsh"
    # 检查是否有systemd或SysV init
    if [ "$(ps -p 1 -o comm=)" = "systemd" ]; then
        INIT_SYSTEM="systemd"
    elif [ -d "/etc/init.d" ]; then
        INIT_SYSTEM="sysv"
    else
        _error_quit "系统不具备 systemd 或 SysV init"
    fi
}

function _valid_config() {
    [ -e "$1" ] && [ "$(wc -l <"$1")" -gt 1 ] && {
        local cmd msg
        cmd="$BIN_KERNEL -d $(dirname "$1") -f $1 -t"
        msg=$(eval "$cmd") || {
            eval "$cmd"
            echo "$msg" | grep -qs "unsupport proxy type" && {
                local prefix="检测到订阅中包含不受支持的代理协议"
                [ "$BIN_KERNEL_NAME" = "clash" ] && _error_quit "${prefix}, 推荐安装使用 mihomo 内核"
                _error_quit "${prefix}, 请检查并升级内核版本"
            }
        }
    }
}

_download_clash() {
    local arch=$1
    local url sha256sum
    case "$arch" in
    x86_64)
        url=https://downloads.clash.wiki/ClashPremium/clash-linux-amd64-2023.08.17.gz
        sha256sum='92380f053f083e3794c1681583be013a57b160292d1d9e1056e7fa1c2d948747'
        ;;
    *86*)
        url=https://downloads.clash.wiki/ClashPremium/clash-linux-386-2023.08.17.gz
        sha256sum='254125efa731ade3c1bf7cfd83ae09a824e1361592ccd7c0cccd2a266dcb92b5'
        ;;
    armv*)
        url=https://downloads.clash.wiki/ClashPremium/clash-linux-armv5-2023.08.17.gz
        sha256sum='622f5e774847782b6d54066f0716114a088f143f9bdd37edf3394ae8253062e8'
        ;;
    aarch64)
        url=https://downloads.clash.wiki/ClashPremium/clash-linux-arm64-2023.08.17.gz
        sha256sum='c45b39bb241e270ae5f4498e2af75cecc0f03c9db3c0db5e55c8c4919f01afdd'
        ;;
    *)
        _error_quit "未知的架构版本：$arch，请自行下载对应版本至 ${ZIP_BASE_DIR} 目录下：https://downloads.clash.wiki/ClashPremium/"
        ;;
    esac

    _okcat '⏳' "正在下载：clash：${arch} 架构..."
    ZIP_CLASH="${ZIP_BASE_DIR}/$(basename $url)"
    curl \
        --progress-bar \
        --show-error \
        --fail \
        --insecure \
        --connect-timeout 15 \
        --retry 1 \
        --output "$ZIP_CLASH" \
        "$url"
    echo $sha256sum "$ZIP_CLASH" | sha256sum -c ||
        _error_quit "下载失败：请自行下载对应版本至 ${ZIP_BASE_DIR} 目录下：https://downloads.clash.wiki/ClashPremium/"
}

_download_raw_config() {
    local dest=$1
    local url=$2
    local agent='clash-verge/v2.0.4'
    sudo curl \
        --silent \
        --show-error \
        --insecure \
        --connect-timeout 4 \
        --retry 1 \
        --user-agent "$agent" \
        --output "$dest" \
        "$url" ||
        sudo wget \
            --no-verbose \
            --no-check-certificate \
            --timeout 3 \
            --tries 1 \
            --user-agent "$agent" \
            --output-document "$dest" \
            "$url"
}
_download_convert_config() {
    local dest=$1
    local url=$2
    _start_convert
    local convert_url=$(
        target='clash'
        base_url="http://127.0.0.1:${BIN_SUBCONVERTER_PORT}/sub"
        curl \
            --get \
            --silent \
            --output /dev/null \
            --data-urlencode "target=$target" \
            --data-urlencode "url=$url" \
            --write-out '%{url_effective}' \
            "$base_url"
    )
    _download_raw_config "$dest" "$convert_url"
    _stop_convert
}
function _download_config() {
    local dest=$1
    local url=$2
    [ "${url:0:4}" = 'file' ] && return 0
    _download_raw_config "$dest" "$url" || return 1
    _okcat '🍃' '下载成功：内核验证配置...'
    _valid_config "$dest" || {
        _failcat '🍂' "验证失败：尝试订阅转换..."
        _download_convert_config "$dest" "$url" || _failcat '🍂' "转换失败：请检查日志：$BIN_SUBCONVERTER_LOG"
    }
}

_start_convert() {
    _is_already_in_use $BIN_SUBCONVERTER_PORT 'subconverter' && {
        local newPort=$(_get_random_port)
        _failcat '🎯' "端口占用：$BIN_SUBCONVERTER_PORT 🎲 随机分配：$newPort"
        [ ! -e "$BIN_SUBCONVERTER_CONFIG" ] && {
            sudo /bin/cp -f "$BIN_SUBCONVERTER_DIR/pref.example.yml" "$BIN_SUBCONVERTER_CONFIG"
        }
        sudo "$BIN_YQ" -i ".server.port = $newPort" "$BIN_SUBCONVERTER_CONFIG"
        BIN_SUBCONVERTER_PORT=$newPort
    }
    local start=$(date +%s)
    # 子shell运行，屏蔽kill时的输出
    (sudo "$BIN_SUBCONVERTER" 2>&1 | sudo tee "$BIN_SUBCONVERTER_LOG" >/dev/null &)
    while ! _is_bind "$BIN_SUBCONVERTER_PORT" >&/dev/null; do
        sleep 1s
        local now=$(date +%s)
        [ $((now - start)) -gt 1 ] && _error_quit "订阅转换服务未启动，请检查日志：$BIN_SUBCONVERTER_LOG"
    done
}
_stop_convert() {
    pkill -9 -f "$BIN_SUBCONVERTER" >&/dev/null
}

# 生成SysV init脚本的函数
_generate_sysv_script() {
    local service_name="$1"
    local exec_path="$2"
    local config_path="$3"
    local base_dir="$4"
    
    cat <<EOF
#!/bin/sh
### BEGIN INIT INFO
# Provides: $service_name
# Required-Start: \$syslog \$local_fs \$network 
# Required-Stop: \$syslog \$local_fs \$network
# Default-Start: 2 3 4 5
# Default-Stop: 0 1 6
# Short-Description: $service_name Daemon, A[nother] Clash Kernel.
### END INIT INFO

. /lib/lsb/init-functions
prog=$service_name
PIDFILE=/var/run/\$prog.pid
DESC="$service_name Daemon, A[nother] Clash Kernel."

start() {
	log_daemon_msg "Starting \$DESC" "\$prog"
	
	# 检查是否已经在运行
	if [ -f \$PIDFILE ]; then
		PID=\$(cat \$PIDFILE)
		if [ -n "\$PID" ] && kill -0 "\$PID" 2>/dev/null; then
			log_end_msg 0
			echo "\$prog is already running with PID \$PID"
			return 0
		fi
	fi
	
	# 启动服务并记录PID
	start-stop-daemon --start --quiet --pidfile \$PIDFILE --exec $exec_path --background --make-pidfile -- -d $base_dir -f $config_path
	
	if [ \$? -ne 0 ]; then
		log_end_msg 1
		exit 1
	fi
	
	# 等待一下确保服务启动
	sleep 1
	if [ -f \$PIDFILE ]; then
		PID=\$(cat \$PIDFILE)
		if [ -n "\$PID" ] && kill -0 "\$PID" 2>/dev/null; then
			log_end_msg 0
		else
			log_end_msg 1
			exit 1
		fi
	else
		log_end_msg 1
		exit 1
	fi
	exit 0
}

stop() {
	log_daemon_msg "Stopping \$DESC" "\$prog"
	
	if [ -f \$PIDFILE ]; then
		PID=\$(cat \$PIDFILE)
		if [ -n "\$PID" ] && kill -0 "\$PID" 2>/dev/null; then
			kill "\$PID"
			
			# 等待进程结束
			for i in \$(seq 1 10); do
				if ! kill -0 "\$PID" 2>/dev/null; then
					break
				fi
				sleep 1
			done
			
			# 如果还没结束，强制杀死
			if kill -0 "\$PID" 2>/dev/null; then
				kill -9 "\$PID"
			fi
			
			rm -f \$PIDFILE
		fi
	fi
	
	# 确保所有相关进程都被杀死
	pkill -f "$exec_path" 2>/dev/null || true
	
	log_end_msg 0
}

status() {
	if [ -f \$PIDFILE ]; then
		PID=\$(cat \$PIDFILE)
		if [ -n "\$PID" ] && kill -0 "\$PID" 2>/dev/null; then
			echo "\$prog is running with PID \$PID"
			return 0
		else
			echo "\$prog is not running (stale PID file)"
			rm -f \$PIDFILE
			return 1
		fi
	else
		echo "\$prog is not running"
		return 1
	fi
}

reload() {
	log_daemon_msg "Reloading \$DESC" "\$prog"
	if [ -f \$PIDFILE ]; then
		PID=\$(cat \$PIDFILE)
		if [ -n "\$PID" ] && kill -0 "\$PID" 2>/dev/null; then
			kill -HUP "\$PID"
			log_end_msg 0
		else
			log_end_msg 1
			exit 1
		fi
	else
		log_end_msg 1
		exit 1
	fi
	exit 0
}

force_reload() {
	stop
	start
}

case "\$1" in
	start)
		start
		;;
	stop)
		stop
		;;
	status)
		status
		;;
	force-reload)
		force_reload
		;;
	restart)
		stop
		start
		;;
	reload)
		reload
		;;
	*)
		echo "Usage: \$prog {start|stop|status|reload|force-reload|restart}"
		exit 2
esac
EOF
}

# 服务管理统一函数
_service_start() {
    local service_name="$1"
    if [ "$INIT_SYSTEM" = "systemd" ]; then
        systemctl start "$service_name"
    else
        service "$service_name" start || {
            # 如果service命令不可用，直接调用init脚本
            [ -x "/etc/init.d/$service_name" ] && "/etc/init.d/$service_name" start
        }
    fi
}

_service_stop() {
    local service_name="$1"
    if [ "$INIT_SYSTEM" = "systemd" ]; then
        systemctl stop "$service_name"
    else
        service "$service_name" stop || {
            # 如果service命令不可用，直接调用init脚本
            [ -x "/etc/init.d/$service_name" ] && "/etc/init.d/$service_name" stop
        }
    fi
}

_service_restart() {
    local service_name="$1"
    if [ "$INIT_SYSTEM" = "systemd" ]; then
        systemctl restart "$service_name"
    else
        service "$service_name" restart || {
            # 如果service命令不可用，直接调用init脚本
            [ -x "/etc/init.d/$service_name" ] && "/etc/init.d/$service_name" restart
        }
    fi
}

_service_status() {
    local service_name="$1"
    shift
    if [ "$INIT_SYSTEM" = "systemd" ]; then
        systemctl status "$service_name" "$@"
    else
        service "$service_name" status "$@" || {
            # 如果service命令不可用，直接调用init脚本
            [ -x "/etc/init.d/$service_name" ] && "/etc/init.d/$service_name" status "$@"
        }
    fi
}

_service_is_active() {
    local service_name="$1"
    if [ "$INIT_SYSTEM" = "systemd" ]; then
        systemctl is-active "$service_name" >&/dev/null
    else
        service "$service_name" status >&/dev/null || {
            # 如果service命令不可用，直接调用init脚本
            [ -x "/etc/init.d/$service_name" ] && "/etc/init.d/$service_name" status >&/dev/null
        }
    fi
}

_service_enable() {
    local service_name="$1"
    if [ "$INIT_SYSTEM" = "systemd" ]; then
        systemctl enable "$service_name"
    else
        if command -v update-rc.d >&/dev/null; then
            update-rc.d "$service_name" defaults
        elif command -v chkconfig >&/dev/null; then
            chkconfig --add "$service_name"
            chkconfig "$service_name" on
        fi
    fi
}

_service_disable() {
    local service_name="$1"
    if [ "$INIT_SYSTEM" = "systemd" ]; then
        systemctl disable "$service_name"
    else
        if command -v update-rc.d >&/dev/null; then
            update-rc.d -f "$service_name" remove
        elif command -v chkconfig >&/dev/null; then
            chkconfig "$service_name" off
            chkconfig --del "$service_name"
        fi
    fi
}
