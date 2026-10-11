# ZFxF · Love Map — 原生 iPhone App

这是 **SwiftUI + MapKit + PhotosPicker** 开发的原生 iOS App，**不是 WebView/PWA**。最低系统：iOS 17。

已接入 Fork 仓库的 Node 服务端：
- 藏宝地图：真实地图、神秘信封、到附近才解锁；地图内容从 `/api/travel-map` 加载
- 约会板：原生拍立得列表、原生相册选图、日期 / 地点 / 日记；数据通过 `/api/dates` 持久化
- 服务连接：手动填写 HTTPS 地址和服务端密码；密码存进 iOS Keychain
- 相片：iPhone 本地压缩成 JPEG 后上传，服务端存入私有 `data/date-photos/`，只有认证请求才能读取

暂未做：地铁提醒、导航、地图回忆关联、后台定位自动推送、正式 App 图标。约会邀请函功能已在第二阶段实现。

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

### 当前 VPS 部署状态（2026-10-11 已验证）
独立 Node 实例在 `127.0.0.1:5168` 监听，通过 Nginx 提供正式可访问的 **`https://memory.ryanecho.xyz/zfxf`**。该主机的 DNS 直连服务器，避免主域名的 Cloudflare Flexible 模式使密钥在源站链路上通过 HTTP 传输。HTTP 请求会重定向到 HTTPS，TLS 证书已验证有效。

真实测试：`GET /zfxf/api/travel-map`、`/zfxf/api/dates`、`/zfxf/api/date-cards` 使用 Bearer 密码返回 200，未授权请求返回 401。原有 `memory.ryanecho.xyz` 首页和 `/api/journal-data` 也仍正常。服务端密码随机生成，仅存 `/etc/zfxf-love-map.env`，没有推送到 GitHub；**不要把密码发送到 GitHub 或贴在公开聊天里**。

首次连接：在 iPhone 的 ZFxF 登录页输入 `https://memory.ryanecho.xyz/zfxf`，并填写服务器本机 `/etc/zfxf-love-map.env` 里的 `PASSWORD`。旧版 iPhone App 也可以手动输入新地址，无需等待重新安装；新编译版本会自动预填该 URL。

注意：现有 Cloudflare 代理的 `ryanecho.xyz` 不能作为已安全就绪的 ZFxF 地址，只有上述直连 HTTPS 主机通过了端到端验证。

## 原生定位单次分享（2026-10-11）

**地图自动定位不代表分享**。原生「藏宝地图」页面新增浅粉色「分享我的位置给 Finnian ♡」卡片。用户主动点击「分享这一次」，再在系统确认弹窗按「确认分享这一次」，才会读取新鲜的 `CLLocation` 并调用 `POST /api/location/share`。如果尚未获得定位，会再请求一次定位；20 秒内获取成功就发，失败提示重试。没有后台分享，也没有定时上报。

- `GET /api/location/share`：显示是否有未过期的最近一次分享，`{ "shared": null }` 表示没有。
- `POST /api/location/share`：发送 `{ "lat": ..., "lon": ..., "acc": ... }`，服务端基于**自己时钟**记录分享时间，覆盖上一次位置。
- `DELETE /api/location/share`：立即撤回并从服务器上删除共享文件。
- 每次分享 **24 小时有效**；过期后不再返回，而且后台定时清理硬盘文件。
- 数据仅存于 `DATA_DIR/manual-location.json`（0600 权限），不会新增历史轨迹，不会触发藏宝到访，不调用外部位置服务。已授权的用户/Agent 才能通过同一套服务器凭据读取。
- MCP 新增 `shared_location`，可供配置好的 AI 客户端读取有效的主动分享。当前普通 ChatGPT 对话不会被自动推送实时坐标；需要请求时通过已连接的私有 VPS 或 Agent 工具读取。
- 验证 `https://memory.ryanecho.xyz/zfxf/api/location/share`：无密码 401，有密码 GET 200，非法坐标 POST 400；服务端 JS 20 项测试全部通过。**只有重新安装新原生版本后，手机才能显示这个按钮。**


## Our Little Universe · 私人地点库（2026-10-11）

最新原生 App 的「设置 → 秘密地点 ♡」可以创建、修改或删除自己的私人地点：

- 家、学校、上海迪士尼、熟悉的公共步道等只需命名一次；可点击「用当前定位」、使用 Apple Maps 搜索，或拖动地图并点「选用地图中心」来定坐标。
- 只有点击**保存**才会发送选定位置；搜索框是用户主动请求的系统地图搜索服务，私人家/学校地址可直接用 GPS 或地图选择，无须发送给搜索。
- 原生「藏宝地图」会显示仅登录者可见的私人粉色图钉。输入“我在家”，代理可通过保存的地点别名知道指的是哪处参考坐标，但**这不是即时定位，也不能证明用户此刻在家**。
- 私人坐标保存在美国 VPS `DATA_DIR/private-places.json`（文件 0600 权限），未提交 GitHub。新增/编辑/删除经鉴权的 `GET/POST /api/places`、`PUT/DELETE /api/places/:id`；接口禁止 HTTP 缓存、验证坐标与重复名称，最多 60 个地点。
- 新 MCP 工具 `list_saved_places` 读取已保存的地点别名（不把坐标直接输出给模型），`hide_at_saved_place` 可按别名藏信。只指定 `near_alias: "家"`、不指定 `alias` 时，会从已保存的**公共且适合步行**的类型 `walk` 地点中，选择直线距离约 100–800 米的可用藏宝点。先保存真实的散步地点才可自动规划，不会随机生成落在车道、建筑内部的坐标。直线距离不等于道路距离，实际路况需要用户确认。
- 藏宝信保持原本“模糊范围＋提示”机制；**只有 iPhone 的新鲜定位**能按原有逻辑拆信，不会因为文字里说“我在家”就自动解锁。
- **第一次安装后地点库为空**，不会凭空知道用户住所或学校坐标。当前 ChatGPT 会话若未连接该 MCP，需要通过现有 VPS 管理工具代为查询和藏信；并非自然语言消息自动触发 App 事件。
- VPS 部署已测试，22 项 Node 测试全过；最终 iOS 编译请查看 GitHub Actions，真机体验仍需用户更新版本。


## 藏宝地图实时定位和方向跟随（2026-10-11）

修复真实找信时看不到自己在地图上的问题：

- 使用 MapKit 原生 `UserAnnotation()` 绘制系统蓝色定位点（及设备支持的方向提示），不使用服务器上一次分享的坐标冒充当前位置。
- 「藏宝地图」在屏幕显示期间才通过 `CLLocationManager.startUpdatingLocation()` 和 `startUpdatingHeading()` 获取 GPS／朝向；切换走这个页面即停止更新。仅供本机地图显示与按键解锁，**不上传到 VPS**。原来「分享这一次」依旧必须二次确认。
- 进入地图自动尝试跟随本人；右下角位置按钮依次在**跟随位置 → 跟随朝向 → 跟随位置**间切换。手动拖动地图退出跟随，再点击即可重新定位。
- iOS MapKit 原生 `MapCameraPosition.userLocation(followsHeading:fallback:)` 控制相机，避免旧逻辑每次位置刷新就强行切回静态地图中心。重新加载藏宝列表也不会抢走用户正在看的位置。
- 如果打开一封仍封着的信，且设备具有新鲜 GPS，详情显示**距离模糊线索标记中心**的约数，不假装这就是精确藏宝坐标；真实解锁由后端当场定位判定。
- 地图蓝点和朝向需要 iPhone 允许「使用 App 期间」定位、设备本身的 GPS/磁力计；模拟器不代表真机定位行为。

更新原生 App：`cd ~/Projects/ZFxF && git pull --ff-only && cd ios && xcodegen generate && open ZFxFLoveMap.xcodeproj`，随后在 Xcode 选设备按 Run。若未安装 xcodegen，首次通过 `brew install xcodegen` 安装（如 Homebrew 缺失需先完成环境配置）。
