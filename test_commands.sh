#!/bin/bash

# 测试clash命令是否能正常工作
echo "🧪 测试clash命令功能..."

# 加载必要的脚本
source script/common.sh
source script/clashctl.sh

# 设置测试环境变量
export INIT_SYSTEM="sysv"  # 模拟SysV环境
export BIN_KERNEL_NAME="clash-test"

echo "📋 当前环境设置:"
echo "   - INIT_SYSTEM: $INIT_SYSTEM"
echo "   - BIN_KERNEL_NAME: $BIN_KERNEL_NAME"

echo ""
echo "🔍 测试函数定义..."

# 测试clashon函数是否存在
if type clashon >/dev/null 2>&1; then
    echo "   ✅ clashon 函数已定义"
else
    echo "   ❌ clashon 函数未定义"
fi

# 测试clashoff函数是否存在  
if type clashoff >/dev/null 2>&1; then
    echo "   ✅ clashoff 函数已定义"
else
    echo "   ❌ clashoff 函数未定义"
fi

# 测试clashstatus函数是否存在
if type clashstatus >/dev/null 2>&1; then
    echo "   ✅ clashstatus 函数已定义"
else
    echo "   ❌ clashstatus 函数未定义"
fi

echo ""
echo "🎯 测试函数内容..."

# 查看clashon函数内容
echo "📄 clashon 函数内容预览:"
type clashon | grep -A 5 -B 1 "systemctl\|service\|/etc/init.d"

echo ""
echo "📄 clashstatus 函数内容预览:"
type clashstatus | grep -A 5 -B 1 "systemctl\|service\|/etc/init.d"

echo ""
echo "✅ 命令测试完成"
echo ""
echo "💡 修复说明："
echo "   - 移除了 sudo _service_* 调用，直接使用 sudo systemctl/service 命令"
echo "   - 函数内部根据 INIT_SYSTEM 变量选择正确的服务管理方式"
echo "   - 现在应该不会再出现 'command not found' 错误"
