#!/usr/bin/env bash
# check_bg.sh — 检测 ys.mihoyo.com/cloud 背景图是否更新
# 数据来源: api-cloudgame.mihoyo.com getUIConfig?all=true API
# 返回尺寸: super_large / large / middle / long / short / pc
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STATE_FILE="$REPO_ROOT/images/.bg_state.json"
IMG_DIR="$REPO_ROOT/images"
README_FILE="$REPO_ROOT/README.md"
URL_LOG="$REPO_ROOT/url.txt"

SIZES=(super_large large middle long short)
for s in "${SIZES[@]}"; do
  mkdir -p "$IMG_DIR/$s"
done

echo "=== 云·原神背景图检测 ==="
echo "时间: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"

# ── 1. 调用 getUIConfig?all=true API ──
echo "[1/7] 调用 getUIConfig API (all=true)..."
REQUEST_TIME=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
API_RESP=$(curl -sL --max-time 30 \
  'https://api-cloudgame.mihoyo.com/hk4e_cg_cn/gamer/api/getUIConfig?all=true' \
  -H 'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36' \
  -H 'Accept: application/json')

RETCODE=$(echo "$API_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('retcode',''))" 2>/dev/null || echo "")
if [ "$RETCODE" != "0" ]; then
  echo "❌ API 返回错误: $RETCODE"
  echo "$API_RESP" | head -5
  exit 1
fi

# 保存API原始响应到url.txt
echo "[2/7] 记录API响应到 url.txt..."
{
  echo "=========================================="
  echo "请求时间: $REQUEST_TIME"
  echo "API: https://api-cloudgame.mihoyo.com/hk4e_cg_cn/gamer/api/getUIConfig?all=true"
  echo "------------------------------------------"
  echo "$API_RESP" | python3 -m json.tool 2>/dev/null || echo "$API_RESP"
  echo "=========================================="
  echo ""
} >> "$URL_LOG"
echo "  ✅ 已追加到 url.txt"

# 用 python3 解析所有尺寸
read -r DETECT_MD5 UPLOAD_DATE BG_URL < <(python3 -c "
import sys, json, re
data = json.load(sys.stdin)['data']['images']
large = data.get('large')
if not large or not large.get('url'):
    print('' '', '' '', sep=' ')
    sys.exit(0)
url = large['url']
md5 = large['md5']
m = re.search(r'(\d{4})/(\d{2})/(\d{2})', url)
date_str = (m.group(1)+m.group(2)+m.group(3)) if m else ''
print(md5, date_str, url)
" <<< "$API_RESP" 2>/dev/null || echo "  ")

if [ -z "$DETECT_MD5" ] || [ -z "$BG_URL" ]; then
  echo "❌ 未获取到背景图信息"
  exit 1
fi

echo "  大图 URL: $BG_URL"
echo "  MD5 (large): $DETECT_MD5"
echo "  上传日期: $UPLOAD_DATE"

# ── 2. 读取上次保存的状态 ──
echo "[3/7] 对比历史状态..."
OLD_MD5=""
if [ -f "$STATE_FILE" ]; then
  OLD_MD5=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('md5',''))" 2>/dev/null || echo "")
  echo "  上次 MD5: ${OLD_MD5:-无}"
else
  echo "  首次运行，无历史记录"
fi

# ── 3. 判断是否有变化 ──
CHANGED="false"
if [ "$DETECT_MD5" != "$OLD_MD5" ]; then
  CHANGED="true"
  echo ""
  echo "🔄 检测到背景图更新！"
  echo "  旧 MD5: ${OLD_MD5:-无}"
  echo "  新 MD5: $DETECT_MD5"
else
  echo ""
  echo "✅ 背景图未变化 (MD5: $DETECT_MD5)"
fi

# ── 4. 如果变化，下载所有尺寸 ──
if [ "$CHANGED" = "true" ]; then
  echo ""
  echo "[4/7] 下载新背景图（所有尺寸）..."

  python3 -c "
import json, sys
data = json.load(sys.stdin)['data']['images']
for s in ['super_large','large','middle','long','short']:
    item = data.get(s)
    if item and item.get('url'):
        print(f\"{s} {item['md5']} {item['url']}\")
    else:
        print(f\"{s} NONE NONE\")
" <<< "$API_RESP" | while read -r SIZE MD5 URL; do
    if [ "$MD5" = "NONE" ]; then
      echo "  ⏭️ $SIZE: 无数据"
      continue
    fi
    FILENAME="${UPLOAD_DATE}_${MD5:0:8}.jpg"
    echo "  ⬇️ $SIZE → $FILENAME ..."
    if curl -sL --max-time 120 "$URL" \
      -H 'User-Agent: Mozilla/5.0' \
      -o "$IMG_DIR/$SIZE/$FILENAME"; then
      cp "$IMG_DIR/$SIZE/$FILENAME" "$IMG_DIR/$SIZE/latest.jpg"
      SIZE_H=$(du -h "$IMG_DIR/$SIZE/$FILENAME" | cut -f1)
      echo "  ✅ $SIZE 保存完成 ($SIZE_H)"
    else
      echo "  ❌ $SIZE 下载失败"
    fi
  done

  # 保存新状态
  echo "[5/7] 更新状态文件..."
  python3 -c "
import json
state = {
    'md5': '$DETECT_MD5',
    'upload_date': '$UPLOAD_DATE',
    'last_check': '$REQUEST_TIME',
    'last_change': '$REQUEST_TIME'
}
with open('$STATE_FILE', 'w') as f:
    json.dump(state, f, indent=2, ensure_ascii=False)
print('  ✅ 状态已保存')
"

  # 更新 README（在 HISTORY_START 标记后、表格分隔行后插入新行）
  echo "[6/7] 更新 README.md..."
  python3 - "$README_FILE" "$UPLOAD_DATE" "$DETECT_MD5" <<'PYEOF'
import sys, os, re

readme_path = sys.argv[1]
upload_date = sys.argv[2]
bg_md5 = sys.argv[3]

date_fmt = f"{upload_date[:4]}-{upload_date[4:6]}-{upload_date[6:8]}"
md5_short = bg_md5[:8]
filename = f"{upload_date}_{md5_short}"

with open(readme_path, 'r', encoding='utf-8') as f:
    content = f.read()

marker_start = "<!-- HISTORY_START -->"
marker_end = "<!-- HISTORY_END -->"

new_entry = (
    f"| {date_fmt} "
    f"| ![{md5_short}](images/large/{filename}.jpg) "
    f"| [超大](images/super_large/{filename}.jpg) · "
    f"[大图](images/large/{filename}.jpg) · "
    f"[中图](images/middle/{filename}.jpg) · "
    f"[长图](images/long/{filename}.jpg) · "
    f"[短图](images/short/{filename}.jpg) "
    f"| `{md5_short}` |"
)

if marker_start in content and marker_end in content:
    pattern = re.escape(marker_start) + r'(.*?)' + re.escape(marker_end)
    match = re.search(pattern, content, re.DOTALL)
    if match:
        old_block = match.group(1)
        if md5_short in old_block:
            print(f"  ⏭️ README 中已有 {md5_short} 的记录，跳过")
        else:
            lines = old_block.strip().split('\n')
            # 找到表格分隔行（包含 --- 的行），在其后插入
            insert_idx = 0
            for i, line in enumerate(lines):
                stripped = line.strip()
                if stripped.startswith('|') and '---' in stripped:
                    insert_idx = i + 1
                    break
            if insert_idx > 0:
                lines.insert(insert_idx, new_entry)
            else:
                # 没找到分隔行，追加到末尾
                lines.append(new_entry)
            new_block = '\n'.join(lines)
            content = content.replace(match.group(0), marker_start + '\n' + new_block + '\n' + marker_end)
            print(f"  ✅ README 已更新，新增 {date_fmt} 记录")
else:
    history_section = f"""
## 📜 背景图历史

{marker_start}
| 日期 | 预览 (large) | 下载 | MD5 |
|------|-------------|------|-----|
{new_entry}
{marker_end}
"""
    content = content.rstrip() + '\n' + history_section
    print(f"  ✅ README 已创建历史区域，新增 {date_fmt} 记录")

with open(readme_path, 'w', encoding='utf-8') as f:
    f.write(content)
PYEOF

else
  echo "[4/7] 无需下载"
  python3 -c "
import json, os
state_file = '$STATE_FILE'
if os.path.exists(state_file):
    with open(state_file) as f: state = json.load(f)
else:
    state = {'md5': '$DETECT_MD5', 'upload_date': '$UPLOAD_DATE'}
state['last_check'] = '$REQUEST_TIME'
with open(state_file, 'w') as f:
    json.dump(state, f, indent=2, ensure_ascii=False)
"
  echo "[5/7] 检查时间已更新"
  echo "[6/7] 无需更新 README"
fi

# ── 5. 输出结果 ──
echo ""
echo "=== 结果 ==="
echo "changed=$CHANGED"
echo "md5=$DETECT_MD5"
echo "upload_date=$UPLOAD_DATE"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "changed=$CHANGED" >> "$GITHUB_OUTPUT"
  echo "md5=$DETECT_MD5" >> "$GITHUB_OUTPUT"
  echo "upload_date=$UPLOAD_DATE" >> "$GITHUB_OUTPUT"
fi
