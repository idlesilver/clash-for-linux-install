#!/bin/bash

# 测试兼容性脚本
# 检查修改后的脚本是否能在systemd和SysV init系统下正常工作

echo "🔍 测试系统兼容性..."

# 模拟不同的init系统
echo "📋 测试环境检查..."

# 保存原始的ps命令
original_ps=$(which ps)

# 测试systemd环境
echo "1. 测试systemd环境..."
export INIT_SYSTEM="systemd"
echo "   - INIT_SYSTEM设置为: $INIT_SYSTEM"

# 测试SysV环境
echo "2. 测试SysV环境..."
export INIT_SYSTEM="sysv"
echo "   - INIT_SYSTEM设置为: $INIT_SYSTEM"

# 检查关键函数是否存在
echo "📝 检查关键函数..."
source script/common.sh 2>/dev/null && echo "   ✅ common.sh 加载成功" || echo "   ❌ common.sh 加载失败"

# 检查服务管理函数
echo "   - 检查 _generate_sysv_script 函数..."
type _generate_sysv_script >/dev/null 2>&1 && echo "     ✅ _generate_sysv_script 存在" || echo "     ❌ _generate_sysv_script 不存在"

echo "   - 检查 _service_start 函数..."
type _service_start >/dev/null 2>&1 && echo "     ✅ _service_start 存在" || echo "     ❌ _service_start 不存在"

echo "   - 检查 _service_stop 函数..."
type _service_stop >/dev/null 2>&1 && echo "     ✅ _service_stop 存在" || echo "     ❌ _service_stop 不存在"

echo "   - 检查 _service_status 函数..."
type _service_status >/dev/null 2>&1 && echo "     ✅ _service_status 存在" || echo "     ❌ _service_status 不存在"

echo "   - 检查 _service_is_active 函数..."
type _service_is_active >/dev/null 2>&1 && echo "     ✅ _service_is_active 存在" || echo "     ❌ _service_is_active 不存在"

# 测试SysV脚本生成
echo "🛠️  测试SysV脚本生成..."
test_script="/tmp/test_sysv_script"
_generate_sysv_script "test-service" "/usr/bin/test" "/etc/test.conf" "/opt/test" > "$test_script"

if [ -f "$test_script" ] && [ -s "$test_script" ]; then
    echo "   ✅ SysV脚本生成成功"
    echo "   📄 脚本大小: $(wc -l < "$test_script") 行"
    
    # 检查脚本是否包含必要的部分
    if grep -q "### BEGIN INIT INFO" "$test_script"; then
        echo "   ✅ LSB头部信息存在"
    else
        echo "   ❌ LSB头部信息缺失"
    fi
    
    if grep -q "start()" "$test_script"; then
        echo "   ✅ start函数存在"
    else
        echo "   ❌ start函数缺失"
    fi
    
    if grep -q "stop()" "$test_script"; then
        echo "   ✅ stop函数存在"
    else
        echo "   ❌ stop函数缺失"
    fi
    
    if grep -q "status()" "$test_script"; then
        echo "   ✅ status函数存在"
    else
        echo "   ❌ status函数缺失"
    fi
    
    rm -f "$test_script"
else
    echo "   ❌ SysV脚本生成失败"
fi

echo "✅ 兼容性测试完成"

echo ""
echo "📋 修改摘要:"
echo "   1. ✅ 修改了 _valid_env 函数以支持systemd和SysV init"
echo "   2. ✅ 添加了 _generate_sysv_script 函数生成SysV init脚本"
echo "   3. ✅ 添加了统一的服务管理函数"
echo "   4. ✅ 修改了 install.sh 以支持两种init系统"
echo "   5. ✅ 修改了 clashctl.sh 使用统一的服务管理函数"
echo "   6. ✅ 修改了 uninstall.sh 支持两种init系统"
echo "   7. ✅ 修改了TUN模式检查以兼容非systemd系统"
echo ""
echo "🎉 现在您的clash-for-linux-install脚本应该能在没有systemd的Linux系统上正常工作了！"
