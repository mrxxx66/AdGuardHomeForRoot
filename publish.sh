#!/bin/bash

# AdGuardHomeForRoot 发布脚本
# 自动化提交更改并推送到远程仓库

set -e  # 遇到错误时退出

echo "开始发布流程..."

# 检查是否在git仓库中
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "错误: 当前目录不是一个git仓库"
    exit 1
fi

# 获取当前分支
current_branch=$(git branch --show-current)
if [ -z "$current_branch" ]; then
    echo "错误: 无法获取当前分支名称"
    exit 1
fi

echo "当前分支: $current_branch"

# 添加所有更改的文件
echo "添加所有更改的文件..."
git add .

# 检查是否有更改
if git diff-index --quiet HEAD --; then
    echo "没有更改需要提交"
    exit 0
fi

# 提交更改
read -p "请输入提交信息: " commit_message

if [ -z "$commit_message" ]; then
    commit_message="自动发布更新"
    echo "使用默认提交信息: $commit_message"
fi

echo "提交更改..."
git commit -m "$commit_message"

# 推送到远程仓库
echo "推送到远程仓库..."
git push origin "$current_branch"

echo "发布完成！"