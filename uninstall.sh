# shellcheck disable=SC2148
# shellcheck disable=SC1091
. script/common.sh >&/dev/null
. script/clashctl.sh >&/dev/null

_valid_env

clashoff >&/dev/null

if [ "$INIT_SYSTEM" = "systemd" ]; then
    systemctl disable "$BIN_KERNEL_NAME" >&/dev/null
    rm -f "/etc/systemd/system/${BIN_KERNEL_NAME}.service"
    systemctl daemon-reload
else
    # 禁用SysV服务
    if command -v update-rc.d >&/dev/null; then
        update-rc.d -f "$BIN_KERNEL_NAME" remove >&/dev/null
    elif command -v chkconfig >&/dev/null; then
        chkconfig "$BIN_KERNEL_NAME" off >&/dev/null
        chkconfig --del "$BIN_KERNEL_NAME" >&/dev/null
    fi
    rm -f "/etc/init.d/${BIN_KERNEL_NAME}"
fi

rm -rf "$CLASH_BASE_DIR"
rm -rf "$RESOURCES_BIN_DIR"
sed -i '/clashupdate/d' "$CLASH_CRON_TAB" >&/dev/null
_set_rc unset

_okcat '✨' '已卸载，相关配置已清除'
_quit
