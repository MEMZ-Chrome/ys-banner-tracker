# 云·原神背景图追踪器

自动检测 [ys.mihoyo.com/cloud](https://ys.mihoyo.com/cloud/) 首页背景图更新，保存到仓库。

## 工作原理

云·原神网页版首页背景图由后端 API 动态下发，非前端打包资源。

```
GET https://api-cloudgame.mihoyo.com/hk4e_cg_cn/gamer/api/getUIConfig
→ { data: { bg_image: { url, md5 } } }
```

检测脚本通过 MD5 判断图片是否变化，变化时下载两个版本：

| 版本 | 路径 | 说明 |
|------|------|------|
| 桌面 | `images/desktop/latest.jpg` | 原图 JPEG（~2MB） |
| 手机 | `images/mobile/latest.webp` | 压缩 WebP（h=600，~200KB） |

## 文件结构

```
├── .github/workflows/check-bg.yml
├── scripts/check_bg.sh
├── images/
│   ├── .bg_state.json              # 状态（URL、MD5、时间）
│   ├── desktop/
│   │   ├── latest.jpg              # 最新桌面背景
│   │   └── YYYYMMDD_HHMMSS_md5.jpg # 历史存档
│   └── mobile/
│       ├── latest.webp             # 最新手机背景
│       └── YYYYMMDD_HHMMSS_md5.webp
└── README.md
```

## 使用

```bash
# 手动检测
bash scripts/check_bg.sh

# GitHub Action: 每周一自动运行，或 Actions 页面手动触发
```
