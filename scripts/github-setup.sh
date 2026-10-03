#!/usr/bin/env bash
# ============================================================
# 衣念项目：GitHub 一键配置脚本
#
# 用途：把本地仓库与 GitHub 打通——推送代码、配置 5 个 Actions Secrets、
#       触发一次 CI 构建并下载产物。全程只需一次性粘贴 Personal Access Token。
#
# 用法：
#   bash scripts/github-setup.sh
#
# 需要你提供：GitHub Personal Access Token（在 GitHub → Settings →
#   Developer settings → Personal access tokens → Generate new token (classic)
#   勾选：repo（读写仓库）、workflow（推送含 workflow 的改动时必需））
#
# 脚本不会打印 token；Token 仅通过隐藏输入传给 gh。
# ============================================================
set -euo pipefail

REPO="Ezra-Maker-MAX/clothes"
# 后端地址。别用 guesses 填这里——填错的话 App 会报
# HandshakeException / WRONG_VERSION_NUMBER，看起来像网络问题，
# 实际是连错了服务器。真实域名见 public/main.dart.js（Web 产物里是权威值）。
API_BASE_URL="${API_BASE_URL:-https://selena.ccwu.cc}"

echo "============================================"
echo " 衣念 · GitHub 配置向导"
echo "============================================"
echo "目标仓库: https://github.com/$REPO"
echo

# ---------- 1. 确认在仓库根目录 ----------
if [ ! -d ".git" ]; then
  echo "✗ 请在 dapei-app 仓库根目录（含 .git）运行本脚本"
  exit 1
fi

# ---------- 2. 前置检查 ----------
echo "【前置检查】"
if ! command -v gh >/dev/null 2>&1; then
  echo "✗ 未找到 gh 命令。安装：https://cli.github.com"
  exit 1
fi
echo "✓ gh 已安装: $(gh --version | head -1)"

REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")
if [ -z "$REMOTE_URL" ]; then
  echo "→ 未配置 remote，正在添加 origin..."
  git remote add origin "https://github.com/$REPO.git"
  echo "✓ origin 已添加"
else
  echo "✓ origin 已配置: $REMOTE_URL"
fi

echo "✓ 敏感文件忽略状态:"
for f in app/android/yinian-release.p12 app/android/key.properties .env; do
  if git check-ignore -q "$f" 2>/dev/null; then
    echo "    · $f 已忽略 ✓"
  else
    echo "    ⚠ $f 未被忽略 —— 请检查 .gitignore！"
  fi
done
echo

# ---------- 3. 登录 GitHub ----------
echo "【GitHub 登录】"
if gh auth status >/dev/null 2>&1; then
  echo "✓ 已登录，跳过"
else
  echo "需要 GitHub Personal Access Token。"
  echo "  获取地址: https://github.com/settings/tokens/new"
  echo "  勾选权限: repo, workflow"
  echo
  printf "请粘贴 Token（输入不回显）: "
  read -rs GH_TOKEN
  echo
  if [ -z "$GH_TOKEN" ]; then
    echo "✗ 未输入 Token，已退出"
    exit 1
  fi
  echo "$GH_TOKEN" | gh auth login --with-token
  unset GH_TOKEN
  echo "✓ 登录成功"
fi
echo

# ---------- 4. 确认仓库可访问 ----------
echo "【仓库检查】"
if gh repo view "$REPO" >/dev/null 2>&1; then
  echo "✓ $REPO 可访问"
else
  echo "✗ 无法访问 $REPO。请确认：token 有 repo 权限、仓库名拼写正确"
  exit 1
fi
echo

# ---------- 5. 推送代码 ----------
echo "【推送代码】"
BRANCH=$(git branch --show-current)
echo "当前分支: $BRANCH"
git add -A
if git diff --cached --quiet; then
  echo "✓ 无未提交改动"
else
  echo "→ 提交本地改动"
  git commit -m "chore: 同步本地改动"
fi

# 关键防呆：本地与远端分叉时不能硬推。
# 真实教训：本地 reset 或换机器 clone 过，再push 会被拒；
# 而 --force 会把远端独有的文件（比如别人提交的功能更新说明）直接抹掉。
if git rev-parse --verify "origin/$BRANCH" >/dev/null 2>&1; then
  git fetch origin "$BRANCH" --quiet || {
    echo "✗ fetch 失败。若网络受限，可用 GitHub API 推送（见 README）。"
    exit 1
  }
  LOCAL=$(git rev-parse HEAD)
  REMOTE=$(git rev-parse "origin/$BRANCH")
  if [ "$LOCAL" = "$REMOTE" ]; then
    echo "✓ 已与远端同步，无需推送"
  elif git merge-base --is-ancestor "$REMOTE" "$LOCAL" 2>/dev/null; then
    echo "→ 本地领先远端，快进推送"
    git push origin "$BRANCH"
  else
    echo "✗ 本地与远端已分叉（各有对方没有的提交）。"
    echo "  本地独有: $(git rev-list --count $REMOTE..$LOCAL) 个"
    echo "  远端独有: $(git rev-list --count $LOCAL..$REMOTE) 个"
    echo
    # 最重要的一步：把远端独有的文件列出来。
    # 强推的代价是这些文件无声消失——曾有一次远端存着 4 份功能更新说明，
    # 本地没有，若直接 --force 就再也找不回来了。
    # diff方向：git diff A B 里的 A 是「旧」，B 是「新」，
    # 所以 --diff-filter=A 才是「B 有而 A 没有的」= 远端有、本地无。
    echo "  ⚠ 远端有、本地没有的文件（强推会永久丢失）："
    ONLY_REMOTE=$(git -c core.quotePath=false diff --name-only --diff-filter=A "$LOCAL" "$REMOTE" 2>/dev/null || true)
    if [ -n "$ONLY_REMOTE" ]; then
      echo "$ONLY_REMOTE" | sed 's/^/      · /'
      echo
      echo "    先取回这些文件再推（逐个执行，路径换成上面列出的）："
      echo "      git checkout $REMOTE -- \"<文件路径>\""
      echo "    然后 git add -A && git commit -m '取回远端独有文件'"
    else
      echo "      （无，远端文件本地都有）"
    fi
    echo
    echo "  两边差异总览: git diff --stat $LOCAL..$REMOTE"
    echo "  建议: git pull --rebase origin $BRANCH  （把远端提交逐个应用下来）"
    echo
    read -rp "已处理分叉后重试推送? [y/N] " GO
    [ "${GO:-N}" = "y" ] || [ "${GO:-N}" = "Y" ] || { echo "已退出，未推送"; exit 1; }
    git push origin "$BRANCH"
  fi
else
  echo "→ 首次推送 $BRANCH"
  git push -u origin "$BRANCH"
fi
echo "✓ 推送完成"
echo

# ---------- 6. 配置 Actions Secrets ----------
echo "【配置 Actions Secrets】"
KS_FILE="app/android/yinian-release.p12"
if [ ! -f "$KS_FILE" ]; then
  echo "✗ 找不到 $KS_FILE"
  echo "  若本机没有，请先用 README 的 keytool 命令生成一份，"
  echo "  或从已有备份恢复（丢了就永久无法更新已发布的 App）。"
  exit 1
fi

# base64：Linux 用 -w0，macOS 无此参数
if base64 --help 2>&1 | grep -q -- "-w"; then
  KS_B64=$(base64 -w0 "$KS_FILE")
else
  KS_B64=$(base64 -i "$KS_FILE" | tr -d '\n')
fi

store_pw=$(grep '^storePassword=' app/android/key.properties 2>/dev/null | cut -d= -f2- || true)
key_pw=$(grep '^keyPassword=' app/android/key.properties 2>/dev/null | cut -d= -f2- || true)
key_alias=$(grep '^keyAlias=' app/android/key.properties 2>/dev/null | cut -d= -f2- || true)
[ -n "$key_alias" ] || key_alias="yinian"

set_secret() {
  local name="$1" val="$2"
  if [ -z "$val" ]; then
    echo "  ⚠ $name 值为空，跳过"
    return
  fi
  printf '%s' "$val" | gh secret set "$name" --repo "$REPO"
  echo "  ✓ $name"
}

set_secret ANDROID_KEYSTORE_BASE64 "$KS_B64"
set_secret ANDROID_KEYSTORE_PASSWORD "$store_pw"
set_secret ANDROID_KEY_ALIAS "$key_alias"
set_secret ANDROID_KEY_PASSWORD "$key_pw"
set_secret API_BASE_URL "$API_BASE_URL"

echo "✓ 5 个 Secret 配置完成"
echo "  查看: gh secret list --repo $REPO"
echo

# ---------- 7. 可选：触发一次构建 ----------
echo "【触发构建】"
read -rp "现在就触发一次 CI 构建验证链路? [y/N] " RUN_NOW
if [ "${RUN_NOW:-N}" = "y" ] || [ "${RUN_NOW:-N}" = "Y" ]; then
  echo "→ 触发 workflow_dispatch"
  gh workflow run android-build.yml --repo "$REPO"
  echo "✓ 已触发。查看进度："
  echo "  gh run watch --repo $REPO"
  echo "  或打开 https://github.com/$REPO/actions"
else
  echo "→ 已跳过。稍后可手动触发："
  echo "  gh workflow run android-build.yml --repo $REPO"
fi

echo
echo "============================================"
echo " 完成"
echo "============================================"
echo "下一步："
echo "  1. 打开 https://github.com/$REPO/actions 看构建结果"
echo "  2. 绿色 ✓ 后可在 Artifacts 下载 yinian-apk"
echo "  3. 打 tag 可自动出包并发Release："
echo "     git tag v1.0.0 && git push origin v1.0.0"
echo
echo "⚠️ 提醒：Vercel 私有 Blob store 仍需你在 Dashboard 手动创建"
echo "   （access=Private，prefix 填 PRIVATE_BLOB_），否则私密图上传返回 503。"
