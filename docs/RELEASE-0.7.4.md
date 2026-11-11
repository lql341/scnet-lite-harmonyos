# SCNet Agent 0.7.4 (HarmonyOS + 原生 Android)

> **两端设置页同步**：把 HAP 与 APK 的差异做了中和，各自吸收对方的优点。

## 同步后的设置页（HAP = APK）

| 区块 | 说明 |
| --- | --- |
| 头像卡 | 居中 72px 头像 + 姓名 + `已登录 · 超算互联网` |
| 信息卡 | **6 行**：账号 / 集群账号 / 集群（N 个可选，点击切换）/ 当前通道 / 集群调度器 / **网关 key（打码）** |
| 自定义模型 | 单行 → 面板（7 预设 + 名称/URL/Key/模型） |
| 外观 | 三组分段：跟随·浅色·深色 / 主题色（色点）/ 字体 小·标准·大 / 语言 |
| 检查更新 | **应用内比对**（不再只打开网页）：有新版 → 显示版本 + 更新说明 + 「打开下载页」；无新版 → 「已是最新版本」；失败 → 说明原因 |
| 关于 | 弹层：版本 + 非官方声明 + 作者 + 项目 + 「查看 Releases」「作者主页」 |
| 算力密钥（AK/SK） | 设置页一行（作业页右上也有入口） |
| 调试区 | 更新源 JSON（留空走 GitHub）/ 网关 key 状态 / 构建版本 |
| 退出登录 | 浅红底按钮 |

## 本版新增（HAP 侧）

- `service/Update.ets`：应用内检查更新（GitHub Releases API + 自定义 JSON 源），与 Android 版同一套逻辑
- 设置页：检查更新改为应用内比对（去掉「仓库私有」文案）、新增调试区（更新源 / 网关 key / 构建）
- 更新源输入弹层（底部抽屉式，留空即走 GitHub）
- `Store` 新增 `updateUrl`

## 本版新增（Android 侧）

- 信息卡新增「网关 key」（前 5 位 + 后 3 位打码，与 HAP 同一格式）

## 产物

| 文件 | 大小 |
| --- | --- |
| `scnet-agent-android-0.7.4.apk` | 205 691 B |
| `scnet-agent-0.7.4-release-signed.hap` | 834 KB |
| `scnet-agent-0.7.4-release-unsigned.hap` | 786 KB |
| `scnet-agent-0.7.4-debug-signed/unsigned.hap` | 1.8 MB |

## 测试

- HAP：51 条全绿 · Android：46 条全绿
