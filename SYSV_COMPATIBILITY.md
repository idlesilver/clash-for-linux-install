# clash-for-linux-install SysV Init 兼容性修改

本文档说明了对 clash-for-linux-install 项目所做的修改，以使其能在没有 systemd 的 Linux 系统上正常工作。

## 修改概述

原项目仅支持使用 systemd 的 Linux 发行版，现在已修改为同时支持 systemd 和 SysV init 系统。

## 主要修改

### 1. 修改环境检查 (`script/common.sh`)

**原代码:**
```bash
function _valid_env() {
    _is_root || _error_quit "需要 root 或 sudo 权限执行"
    [ -n "$ZSH_VERSION" ] && [ -n "$BASH_VERSION" ] && _error_quit "仅支持：bash、zsh"
    [ "$(ps -p 1 -o comm=)" != "systemd" ] && _error_quit "系统不具备 systemd"
}
```

**修改后:**
```bash
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
```

### 2. 添加 SysV Init 脚本生成函数

新增 `_generate_sysv_script()` 函数，用于生成标准的 LSB 兼容的 SysV init 脚本：

```bash
_generate_sysv_script() {
    local service_name="$1"
    local exec_path="$2" 
    local config_path="$3"
    local base_dir="$4"
    
    # 生成完整的SysV init脚本
    # 包含LSB头部信息、start/stop/status/restart函数
    # 支持PID文件管理和后台运行
}
```

### 3. 添加统一的服务管理函数

新增以下函数以统一管理不同init系统的服务：

- `_service_start()` - 启动服务
- `_service_stop()` - 停止服务  
- `_service_restart()` - 重启服务
- `_service_status()` - 查看服务状态
- `_service_is_active()` - 检查服务是否运行
- `_service_enable()` - 设置服务开机自启
- `_service_disable()` - 禁用服务开机自启

### 4. 修改安装脚本 (`install.sh`)

**原代码直接创建systemd服务文件:**
```bash
cat <<EOF >"/etc/systemd/system/${BIN_KERNEL_NAME}.service"
[Unit]
Description=$BIN_KERNEL_NAME Daemon, A[nother] Clash Kernel.
[Service]
Type=simple
Restart=always
ExecStart=${BIN_KERNEL} -d ${CLASH_BASE_DIR} -f ${CLASH_CONFIG_RUNTIME}
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable "$BIN_KERNEL_NAME"
```

**修改后根据init系统选择:**
```bash
if [ "$INIT_SYSTEM" = "systemd" ]; then
    # 创建systemd服务文件
    cat <<EOF >"/etc/systemd/system/${BIN_KERNEL_NAME}.service"
    ...
    EOF
    systemctl daemon-reload
else
    # 创建SysV init脚本
    _generate_sysv_script "$BIN_KERNEL_NAME" "$BIN_KERNEL" "$CLASH_CONFIG_RUNTIME" "$CLASH_BASE_DIR" > "/etc/init.d/${BIN_KERNEL_NAME}"
    chmod +x "/etc/init.d/${BIN_KERNEL_NAME}"
fi
_service_enable "$BIN_KERNEL_NAME"
```

### 5. 修改控制脚本 (`script/clashctl.sh`)

将所有 `systemctl` 命令替换为统一的服务管理函数：

**原代码:**
```bash
systemctl start "$BIN_KERNEL_NAME"
systemctl stop "$BIN_KERNEL_NAME"  
systemctl status "$BIN_KERNEL_NAME"
systemctl is-active "$BIN_KERNEL_NAME"
```

**修改后:**
```bash
sudo _service_start "$BIN_KERNEL_NAME"
sudo _service_stop "$BIN_KERNEL_NAME"
sudo _service_status "$BIN_KERNEL_NAME" 
_service_is_active "$BIN_KERNEL_NAME"
```

### 6. 修改卸载脚本 (`uninstall.sh`)

**原代码:**
```bash
systemctl disable "$BIN_KERNEL_NAME"
rm -f "/etc/systemd/system/${BIN_KERNEL_NAME}.service"
systemctl daemon-reload
```

**修改后:**
```bash
if [ "$INIT_SYSTEM" = "systemd" ]; then
    systemctl disable "$BIN_KERNEL_NAME" >&/dev/null
    rm -f "/etc/systemd/system/${BIN_KERNEL_NAME}.service"
    systemctl daemon-reload
else
    _service_disable "$BIN_KERNEL_NAME" >&/dev/null
    rm -f "/etc/init.d/${BIN_KERNEL_NAME}"
fi
```

### 7. 修改日志检查

在TUN模式检查中，对非systemd系统提供备用方案：

**原代码:**
```bash
sudo journalctl -u "$BIN_KERNEL_NAME" --since "1 min ago" | grep -E -m1 'unsupported kernel version|Start TUN listening error'
```

**修改后:**
```bash
if command -v journalctl >&/dev/null && [ "$INIT_SYSTEM" = "systemd" ]; then
    sudo journalctl -u "$BIN_KERNEL_NAME" --since "1 min ago" | grep -E -m1 'unsupported kernel version|Start TUN listening error'
else
    # 对于SysV系统，检查服务状态
    if ! _service_is_active "$BIN_KERNEL_NAME"; then
        _error_quit '启动失败，可能是不支持的内核版本'
    fi
fi
```

## 兼容性支持

修改后的脚本支持以下Linux发行版：

### 带systemd的发行版
- Ubuntu 15.04+
- Debian 8+
- CentOS 7+
- RHEL 7+
- Fedora 15+
- openSUSE 12.1+

### 使用SysV init的发行版  
- Debian 7及更早版本
- Ubuntu 14.04及更早版本
- CentOS 6及更早版本
- RHEL 6及更早版本
- Alpine Linux
- Devuan
- 其他使用SysV init的发行版

## 功能保持不变

所有原有的clash功能都得到保留：
- ✅ 代理服务的启动/停止/重启
- ✅ 系统代理设置
- ✅ Web UI访问
- ✅ TUN模式支持
- ✅ 配置更新和管理
- ✅ 开机自启设置
- ✅ 完整的命令行控制

## 使用方法

修改后的使用方法与原版完全相同：

```bash
# 安装
sudo ./install.sh

# 启动代理
clash on

# 停止代理  
clash off

# 查看状态
clash status

# 访问Web UI
clash ui

# 卸载
sudo ./uninstall.sh
```

## 测试

可以运行包含的测试脚本验证兼容性：

```bash
```bash
./test_compatibility.sh
```

该脚本会检查所有关键函数是否正确实现，并验证SysV脚本生成功能。

## 故障排除

### 修复的问题

#### 1. "sudo: _service_start: command not found" 错误

**问题**: 在使用 `clashon` 和 `clashstatus` 命令时出现此错误。

**原因**: sudo 无法执行 shell 函数，因为函数只存在于当前 shell 环境中。

**解决方案**: 
- 移除了 `sudo _service_*` 的调用方式
- 直接在函数内部根据 `INIT_SYSTEM` 变量选择合适的系统命令
- 修改后的代码示例：

```bash
# 修改前（错误）
sudo _service_start "$BIN_KERNEL_NAME"

# 修改后（正确）  
if [ "$INIT_SYSTEM" = "systemd" ]; then
    sudo systemctl start "$BIN_KERNEL_NAME"
else
    sudo service "$BIN_KERNEL_NAME" start || sudo "/etc/init.d/$BIN_KERNEL_NAME" start
fi
```

### 其他常见问题

#### 2. 服务启动失败

**检查步骤**:
1. 确认脚本已正确安装: `ls -la /etc/init.d/{service_name}`
2. 检查脚本权限: `chmod +x /etc/init.d/{service_name}`
3. 手动测试脚本: `sudo /etc/init.d/{service_name} start`
4. 查看进程状态: `ps aux | grep {service_name}`

#### 3. 开机自启设置失败

**Debian/Ubuntu 系统**:
```bash
sudo update-rc.d {service_name} defaults
```

**RHEL/CentOS 系统**:
```bash
sudo chkconfig --add {service_name}
sudo chkconfig {service_name} on
```

## 更新日志

### 最新修复 (当前版本)
- ✅ **修复**: 解决了 "sudo: _service_start: command not found" 错误
- ✅ **改进**: 重构了服务管理逻辑，移除了有问题的 sudo 函数调用
- ✅ **优化**: 简化了代码结构，提高了可靠性

### 之前的修改
- ✅ **新增**: SysV init 脚本自动生成功能
- ✅ **兼容**: 支持传统 Linux 发行版 (Debian 7, CentOS 6 等)
- ✅ **统一**: 服务管理接口适配不同 init 系统
- ✅ **保持**: 所有原有 clash 功能完整保留

## 验证安装

安装完成后，可以通过以下命令验证：

```bash
# 检查服务脚本
if [ "$INIT_SYSTEM" = "systemd" ]; then
    systemctl status {service_name}
else
    service {service_name} status
fi

# 测试基本功能
clashon      # 应该能正常启动
clashstatus  # 应该显示服务状态
clashoff     # 应该能正常停止
```

现在您的 clash-for-linux-install 应该能在没有 systemd 的 Linux 系统上完美工作了！
```

该脚本会检查所有关键函数是否正确实现，并验证SysV脚本生成功能。
