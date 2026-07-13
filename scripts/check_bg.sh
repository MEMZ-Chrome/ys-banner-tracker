#!/usr/bin/env bash
# check_bg.sh — 检测 ys.mihoyo.com/cloud 背景图是否更新
# 数据来源: api-cloudgame.mihoyo.com getUIConfig API
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STATE_FILE="$REPO_ROOT/images/.bg_state.json"
DESKTOP_DIR="$REPO_ROOT/images/desktop"
MOBILE_DIR="$REPO_ROOT/images/mobile"

mkdir -p "$DESKTOP_DIR" "$MOBILE_DIR"

echo "=== 云·原神背景图检测 ==="
echo "时间: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"

# 1. 调用 getUIConfig API 获取背景图信息
echo "[1/5] 调用 getUIConfig API..."
API_RESP=$(curl -sL --max-time 30 \
  'https://api-cloudgame.mihoyo.com/hk4e_cg_cn/gamer/api/getUIConfig?height=457&width=800' \
  -H 'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36' \
  -H 'Accept: application/json')

RETCODE=$(echo "$API_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('retcode',''))" 2>/dev/null || echo "")
if [ "$RETCODE" != "0" ]; then
  echo "❌ API 返回错误: $RETCODE"
  echo "$API_RESP" | head -5
  exit 1
fi

BG_URL=$(echo "$API_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['bg_image']['url'])" 2>/dev/null || echo "")
BG_MD5=$(echo "$API_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['bg_image']['md5'])" 2>/dev/null || echo "")

if [ -z "$BG_URL" ]; then
  echo "❌ 未获取到背景图 URL"
  exit 1
fi

echo "  URL: $BG_URL"
echo "  MD5: $BG_MD5"

# 2. 读取上次保存的状态
echo "[2/5] 对比历史状态..."
OLD_MD5=""
if [ -f "$STATE_FILE" ]; then
  OLD_MD5=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('md5',''))" 2>/dev/null || echo "")
  echo "  上次 MD5: ${OLD_MD5:-无}"
else
  echo "  首次运行，无历史记录"
fi

# 3. 判断是否有变化
CHANGED="false"
if [ "$BG_MD5" != "$OLD_MD5" ]; then
  CHANGED="true"
  echo ""
  echo "🔄 检测到背景图更新！"
  echo "  旧 MD5: ${OLD_MD5:-无}"
  echo "  新 MD5: $BG_MD5"
else
  echo ""
  echo "✅ 背景图未变化 (MD5: $BG_MD5)"
fi

# 4. 如果变化，下载新图片
if [ "$CHANGED" = "true" ]; then
  echo ""
  echo "[4/5] 下载新背景图..."
  TIMESTAMP=$(date -u '+%Y%m%d_%H%M%S')

  # 下载桌面版（原图 JPG）
  echo "  下载桌面版（原图）..."
  curl -sL --max-time 120 "$BG_URL" \
    -H 'User-Agent: Mozilla/5.0' \
    -o "$DESKTOP_DIR/latest.jpg"
  cp "$DESKTOP_DIR/latest.jpg" "$DESKTOP_DIR/${TIMESTAMP}_${BG_MD5:0:8}.jpg"
  DESKTOP_SIZE=$(du -h "$DESKTOP_DIR/latest.jpg" | cut -f1)
  echo "  ✅ 桌面版已保存 ($DESKTOP_SIZE)"

  # 下载手机版（压缩 webp）
  MOBILE_URL="${BG_URL}?x-oss-process=image/quality,Q_100/format,webp/resize,h_600"
  echo "  下载手机版（webp h=600）..."
  curl -sL --max-time 120 "$MOBILE_URL" \
    -H 'User-Agent: Mozilla/5.0' \
    -o "$MOBILE_DIR/latest.webp"
  cp "$MOBILE_DIR/latest.webp" "$MOBILE_DIR/${TIMESTAMP}_${BG_MD5:0:8}.webp"
  MOBILE_SIZE=$(du -h "$MOBILE_DIR/latest.webp" | cut -f1)
  echo "  ✅ 手机版已保存 ($MOBILE_SIZE)"

  # 保存新状态
  echo "[5/5] 更新状态文件..."
  python3 -c "
import json
state = {
    'md5': '$BG_MD5',
    'url': '$BG_URL',
    'last_check': '$(date -u '+%Y-%m-%dT%H:%M:%SZ')',
    'last_change': '$(date -u '+%Y-%m-%dT%H:%M:%SZ')'
}
with open('$STATE_FILE', 'w') as f:
    json.dump(state, f, indent=2, ensure_ascii=False)
print('  ✅ 状态已保存')
"
else
  echo "[4/5] 无需下载"
  python3 -c "
import json, os
state_file = '$STATE_FILE'
if os.path.exists(state_file):
    with open(state_file) as f: state = json.load(f)
else:
    state = {'md5': '$BG_MD5', 'url': '$BG_URL'}
state['last_check'] = '$(date -u '+%Y-%m-%dT%H:%M:%SZ')'
with open(state_file, 'w') as f:
    json.dump(state, f, indent=2, ensure_ascii=False)
"
  echo "[5/5] 检查时间已更新"
fi

# 输出结果
echo ""
echo "=== 结果 ==="
echo "changed=$CHANGED"
echo "md5=$BG_MD5"
echo "url=$BG_URL"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "changed=$CHANGED" >> "$GITHUB_OUTPUT"
  echo "md5=$BG_MD5" >> "$GITHUB_OUTPUT"
fi
