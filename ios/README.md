# ZFxF · Love Map — 原生 iPhone App

这是 **SwiftUI + MapKit + PhotosPicker** 开发的原生 iOS App，**不是 WebView/PWA**。最低系统：iOS 17。

已接入 Fork 仓库的 Node 服务端：
- 藏宝地图：真实地图、神秘信封、到附近才解锁；地图内容从 `/api/travel-map` 加载
- 约会板：原生拍立得列表、原生相册选图、日期 / 地点 / 日记；数据通过 `/api/dates` 持久化
- 服务连接：手动填写 HTTPS 地址和服务端密码；密码存进 iOS Keychain
- 相片：iPhone 本地压缩成 JPEG 后上传，服务端存入私有 `data/date-photos/`，只有认证请求才能读取

暂未做：地铁提醒、导航、约会邀请函、地图回忆关联、后台定位自动推送、正式 App 图标。

## 用 Xcode 安装到 iPhone

1. 在 Mac 上安装 **Xcode**。下载本仓库的 `feature/zfxf-date-board-mvp` 分支代码。
2. 安装 XcodeGen（Mac 终端执行 `brew install xcodegen`）。
3. 进入本仓库 `ios/` 目录，执行 `xcodegen generate`，打开生成的 `ZFxFLoveMap.xcodeproj`。
4. 在 Xcode 的 **Signing & Capabilities** 中选自己的 Apple Developer Team；如果 Bundle ID 冲突，改为自己唯一的 ID。
5. 用数据线或 Xcode 无线连接自己的 iPhone，按 Xcode 提示信任设备；如系统要求，打开「开发者模式」。
6. 在 Xcode 设备列表选择自己的 iPhone，按 ▶︎ Run。App 将安装到手机上。
7. 首次打开需填写**自己部署的 HTTPS 服务器地址**及 `.env` 中的 `PASSWORD`。如果还没有服务器，App 会停留在连接页面（不会虚构已连通的约会数据）。

### 服务端（需要先部署才能实测藏信、相册同步）

仓库根目录要求 Node.js 20.6+：

```bash
npm ci
cp .env.example .env
# 编辑 .env：设置强 PASSWORD、HIDER_NAME=Finnian、FINDER_NAME=念念、DATA_DIR 等
npm test
npm run build
npm start
```

需要用 HTTPS 反向代理对外提供地址，且仅对自己可信的人开放。服务端持久化 `data/` 目录并定期备份，严禁把 `.env` 或照片目录推到 GitHub。

**安全注意**：上游仓库采用共用密码，移动端复用它作为 Bearer 凭据。正式长期使用前建议拆分权限、加请求限速、加强会话管理，并采取图片/位置的保留与删除策略。

### 自动检查

GitHub Actions 的 `ZFxF MVP checks` 会跑 JS 测试和 Vite 构建，并使用 macOS 生成 Xcode 工程，执行一次 iOS 模拟器无签名编译。这只能证明代码通过编译，**不代表已经在真 iPhone 上验证**。

## 第二阶段：约会邀请与回执（原生，已连接 API）

ZFxF 的第三个原生 tab 是「约会来信」。它会向已登录的 Node 后端请求 `GET /api/date-cards`。
有支持 MCP 的 agent 调用 `create_date_card` 创建卡片后，下拉刷新或点击右上角刷新即可看见。

- `invitation`（约会前）：填「想去哪里」「期待」「心情」「希望照顾的事情」。
- `review`（约会后）：五类 1～5 星（半星）、最喜欢的事、下次希望、留言。全部可跳过评分。
- 原生 UI 调用 `POST /api/date-cards/:id/submit`；提交后服务器返回最终状态，页面变只读。
- Agent 可调用 `date_card_recent` 阅读原话，用 `date_card_agent_note` 写在卡片背面；下次 iPhone 刷新显示。
- 原生 APNs 推送尚未实现。创建卡片 **不会自动弹出 iPhone 通知**。
- 只有配置并部署受信任的 `DATE_CARD_WEBHOOK_URL` 时，提交后才会通知你自己的 Agent 服务；**当前没有自动通往 ChatGPT 的回调**。

### 当前 VPS 部署状态
开发中的 VPS 独立实例监听在 `127.0.0.1:5168`（非公开地址）。要在 iPhone 上连接，还需要给现有域名设置 **HTTPS 反向代理**。在验证外部访问携带密码确实返回 JSON 前，不要把 `https://ryanecho.xyz/zfxf` 当成可用 URL。域名和登录密码不写入源码。
