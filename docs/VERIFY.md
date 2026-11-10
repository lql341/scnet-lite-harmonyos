# VERIFY — 真机验证记录与待验清单

> **2026-11-10 已跑一轮**（PLA-AL10 / HarmonyOS / API 26，USB 连接）。结果见文末「验证记录」。



> 环境：`hdc list targets` 有 `Connected` 设备后执行。
> 构建/签名/安装三连见 `docs/NEXT.md` §0。

```bash
. ~/opt/module-init.sh && module load harmonyos jdk
hvigorw assembleHap --mode module -p product=default -p buildMode=debug --no-daemon
./scripts/sign.sh --install
hdc shell aa start -a EntryAbility -b cn.scnet.hmos
```

---

## 0. 登录过期（新改动，优先验）

**前置**：清掉登录态 —— 在 App 里「抽屉 → 退出登录」。

| 步骤 | 期望 |
| --- | --- |
| 退出登录 | 回到登录页，**不应**出现「登录已过期」黄卡 |
| 强制重启 App（`aa force-stop` + `aa start`） | 仍停在登录页，仍**没有**黄卡（因为是主动退出） |
| 用 `scripts/probe.sh` 无关操作后手动清 prefs 里的 token：`hdc shell` 无法直改，改为：登录成功一次 → 杀进程 → 让 token 过期（或临时改 `store.clearCloudAuth` 调试） | 出现黄卡「登录已过期 · 长时间未使用需要重新登录」，且**账号已带出** |
| 登录成功后 | 黄卡消失，进对话页 |

> 黄卡判定逻辑：`Auth.restore()` 里 `store.hadSession() == true` 且 token 为空 → `expired`。

## 1. 作业列表 → 详情 → 日志

**前置**：作业页填好 AK/SK（抽屉 → 作业 → 右上 `AK`，一次粘贴 `AccessKey:SecretKey`）。

| 步骤 | 期望 |
| --- | --- |
| 抽屉 → 作业 | 集群名、空闲核、配额、队列列表（6 个）、运行中作业 |
| 点任一作业行 | 进「作业详情」：状态徽标、14 项字段（作业名/状态/队列/提交时间/核数/工作目录/outputPath…） |
| 点「读取」 | 日志出现在深色等宽卡片里（真正跑着的作业可能为空，属正常） |
| 运行中作业右上「取消作业」→ 弹层 | 弹层显示 jobId + 状态；点「保留」不动；**不要点确认**（会真取消） |

## 2. 文件浏览

| 步骤 | 期望 |
| --- | --- |
| 作业页 → 右上「文件」 | 列出 `/public/home/luql` 下的目录（`apprepo` / `BASE` / `cases` / `kylinflow` …） |
| 点目录 | 进入下一级；左上 `‹` 返回上一级；到 home 后再 `‹` 回作业页 |
| 点文件 | 文件内容显示在深色卡片（可复制） |

> 已知：efile 返回里**没有 `isDirectory`**，代码是「先按目录试，失败当文件读」，所以点一个空目录会落到"读文件"分支——这是预期的降级。

## 3. 作业提交（**不要打开红色开关**）

| 步骤 | 期望 |
| --- | --- |
| 作业页 → 右上「提交」 | 表单：队列 chips、节点/核/DCU/GPU 步进器、作业名/时长/内存/工作目录/命令 |
| 看「等价 sbatch」 | 随表单实时变化，`#SBATCH --nodes=` / `--ntasks-per-node=` 与步进器一致 |
| 故意把时长改成 `10:00` | 点提交 → 提示「运行时长格式应为 HH:MM:SS」 |
| 改回 `00:10:00`，保持红色开关**关闭** → 点「校验并生成提交体」→ 确认 | 顶部提示「已生成提交体（试运行，未真正提交）」，hilog 里有 `submit dry-run body=…` |

## 4. 插件市场

| 步骤 | 期望 |
| --- | --- |
| 抽屉 → 插件 | 连接器 Tab：精选（8 条左右）/ 推荐 / 社区三段；「共 13617 个」 |
| 切「技能」Tab | 共 17792 个；第一条应为「海光CPU性能优化SKILL」之类 |
| 点「最热」切排序 | 变为「最新」→「最多下载」→「最热」循环 |
| 搜索「论文」→ 搜索 | 结果收敛（约 52 条） |
| 点任一卡片 | 内嵌 Web 打开 AIHub 详情页，且**已登录**（不需要二次登录） |

## 5. 首页场景

| 步骤 | 期望 |
| --- | --- |
| 新建对话 | 7 个分类 chips：文献阅读 / 材料科学 / 工业仿真 / 生物信息 / 学术写作 / 平台助手 / 办公创作 |
| 切「材料科学」 | 3 张场景卡（标题 + 摘要 + 可能的「附件 N」标记） |
| 点「换一批」 | 卡片顺序轮换 |
| 点一张无附件的卡 | 直接把预置 prompt 发出，走智能体通道 |
| 点一张带附件的卡（无附件时） | 只预填不发送，提示「需要 N 个附件，请点 ＋ 选择文件」 |

## 6. OCR

| 步骤 | 期望 |
| --- | --- |
| 抽屉 → 文字识别 → 右上「自检」 | 提示「自检通过（trace xxxxxxxx，无文字属正常）」 |
| 相册选一张有字的图 → 选「印刷文字」→ 开始识别 | 出识别文字，行数正确；「复制」「发送到对话」可用 |

## 7. 本轮新增（2026-11-10）— 真机已验

| 项 | 结果 |
| --- | --- |
| Markdown 表格 | ✅ 首版做成「三列平分+横滑」→ 实测**第三列被截断、嵌套滚动抢手势**；改成「每行一张卡（首列标题 + 表头:值）」后可读性正常 |
| 长按复制 | ✅ 首版 `LongPressGesture` 被列表手势吃掉，改用 `bindContextMenu(ResponseType.LongPress)`；点「复制」后系统剪贴板内容与表格原文一致 |

原清单（保留）：



| 步骤 | 期望 |
| --- | --- |
| 抽屉里长按本机会话 | 弹「重命名会话」，改名后列表立即更新 |
| 长按任一条消息 | 顶部提示「已复制」，粘贴到别处内容完整 |
| 让模型输出一张 Markdown 表格（如「用表格对比 SLURM/PBS」） | 渲染成带表头、可横向滚动的表格，不是一堆竖线文本 |
| 长对话（>24000 字符）再发消息 | 顶部提示「上下文较长，已省略最近 N 条之前的历史」 |
| 作业页 → 提交 →（开关关闭）生成 | 提示 dry-run；开启开关真提交后 1.5s 会自动回读状态 |

## 8. 回归（每次改动都过一遍）

- [ ] 切主题（含 SCNet 红）→ **返回对话页颜色跟着变**
- [ ] 字号 大/小 → Markdown 正文跟着变
- [ ] 语言切 English → 顶栏/输入区/抽屉/面板双语
- [ ] 杀进程重进 → 会话恢复、模型/通道选择保持
- [ ] 附件：＋ 选文件 → chip 出现 → 发送「附件有几行数据」→ 回答与文件一致
- [ ] 停止生成：长回答中途点 ■ → 截断保留、不崩、按钮回 ↑

---

## 验证记录（2026-11-10）

设备：PLA-AL10，`hdc` USB `Connected`（需要 udev 规则，见「环境问题」）。

| # | 项目 | 结果 |
| --- | --- | --- |
| 1 | 登录态恢复 | ✅ `restore: token=235 cookie=99` → 直接进对话页 |
| 2 | 双通道对话 | ✅ 网关 `SCNet Max` 出字正常 |
| 3 | Markdown 表格 | ✅ 首版三列横滑不可用（第三列截断、滚动手势被外层 List 抢）→ 改「每行一张卡」后完整可读 |
| 4 | 长按复制 | ✅ 首版 `LongPressGesture` 被吃掉 → 改 `bindContextMenu`；复制后剪贴板内容与表格 Markdown 原文一致 |
| 5 | 首页 7 类场景 | ✅ `scenarios: 7 categories, 32 items`；文献阅读选中，卡片含「附件 1」标记 |
| 6 | 插件市场 | ✅ 连接器 13617、精选分组生效（必应/MATLAB/Fetch/GitHub/高德/Blender） |
| 7 | OCR 自检 | ✅ `ocr selftest ok trace=0b54731f22c48c0c` |
| 8 | 作业页 | ✅ 两个集群实测：昆山 6 队列 / 哈尔滨 3 队列；空闲核、配额、队列列表正确 |
| 9 | 作业详情 | ✅ 作业 127501160：11 项字段全对（队列/用户/时间/节点 a01r1n18/8 核/workDir/outputPath） |
| 10 | 日志读取 | ✅ `job log … len=6`，作业未输出时显示「（日志为空）」不报错 |
| 11 | 文件浏览 | ✅ 31 个目录逐级进入到 5 层深（`kylinflow/evidence/1d-limiter-smoke/127037152`） |

### 这轮修掉的 3 个真机专属问题

1. **表格横滑不可用** —— 嵌套 `Scroll` 与外层消息 `List` 抢手势 → 改卡片式
2. **长按复制不触发** —— 同上，`LongPressGesture` 被列表滚动吃掉 → 改 `bindContextMenu`
3. **作业页顶部大片留白** —— `Scroll` 内容不足时垂直居中 → `.align(Alignment.Top)`

### 未验（受条件限制）

- **登录过期提示卡**：需要一次真实 token 过期，只能等自然过期或手动清凭据
- **作业提交**：dry-run 已验证请求体生成，真提交未执行（会真计费，需人工决定）
- **取消作业**：契约已用 curl 验证，UI 弹层未点确认（会真取消用户的作业）
- **附件上传完整链路**：本机 curl 端到端验过（智能体读到文件答 33），App 内选文件走系统 picker 待人工点一次

## 2026-11-10 下午这批改动（已真机验 / 待你验）

| 项 | 结果 |
| --- | --- |
| 抽屉顺序 算力服务→插件→AI社区→应用商城→文字识别 | ✅ 真机截图 |
| 应用商城（内嵌 `/ui/mall`） | ✅ 真机（能看到 Token Plan 专区、算力市场） |
| 首页 banner（`config/list.recommendAD`） | ✅ 真机（AI生态伙伴加速计划 / DeepSeek） |
| OCR 三模式（识别 / 文档解析 / 格式转换） | ✅ 真机（后两者给说明卡 + 打开平台页，不做假入口） |
| 网关设置移出抽屉 | ✅ 真机（抽屉里已无 API Key/Base URL） |
| 账号页新增「自定义模型」「充值 / 控制台」两行 | ✅ 真机 |
| 头像面板 | ✅ 真机：卡通6/风景4/字母2 三组，点选立即生效（hilog `avatar preset applied id=6`） |
| 应用图标 + 应用名 | ✅ 已换（三节点中性图标 / 「超级计算智能体」），装完可在桌面看到 |
| 自定义 provider 实际发消息 | ⏳ 需要你填一个真端点（默认仍是平台网关） |
| 附件两个入口（图片 / 文件）+ 失败原因直出 | ⏳ 需要你在真机上选一次图/文件 |

## 2026-11-10 用户反馈的 6 个问题（已修，真机验过）

| # | 现象 | 根因 | 修法 |
| --- | --- | --- | --- |
| 1 | 头像点不动 | `Avatar` 根节点无条件挂 `onClick`，吃掉外层预设项的点击 | 只在传了 `onTap` 时挂，选中逻辑统一走 `onTap` |
| 1b | 头像只有"名字首字" | — | 改成 12 款三组：卡通（🐼🦊🐳🦉🐙🌵）、风景（日落/海面/雪山/星空，程序绘制）、字母（2 种配色） |
| 2 | 插件没列出精选 | 精选（`suggestType=1`）不在"最热"前 64 条里 | 首屏额外按 `favoriteCount` 拉一次再筛 `suggestType=1`，并从主列表去重 |
| 3 | OCR 大加号没用 | 那个 `Column` 没挂 `onClick` | 补上，与「换一张」等效 |
| 4 | 算力服务离新对话太近 | 缺 `margin` | `.margin({ top: 12 })` |
| 5 | 会话输入区 ＋ 唤不起 | `showAttachSheet` 声明成普通字段，不是 `@State`（改状态不刷新 UI） | 改成 `@State` |

## 文件格式支持（2026-11-10 实测）

| 入口 | 支持 |
| --- | --- |
| 对话附件 ＋（文件） | pdf / doc / docx / xls / xlsx / ppt / pptx / txt / md / json / xml / yaml / csv / tsv / log / 常见代码 / 图片 / zip、tar、gz |
| 对话附件 ＋（图片） | 相册里的 png/jpg/webp/gif/bmp |
| OCR | **图片 + PDF**（PDF 由服务端转图）；docx/xlsx/pptx/md/csv 会报 `File type cannot be supported` |
| 文档解析 / 格式转换 | 走平台应用页（网关无对应枚举） |

MIME 表在 `service/Upload.ets:mimeOf()`，新增格式在那里加一行即可。

> 2026-11-10 复验：附件面板文案已更新为「相册图片 / PDF/Office/文本/代码/图片」；
> 头像改动后顶栏与抽屉会同步（`Index.onPageShow()` 重读 `store.getAvatar()`，
> 实测 🐼→🦊 切换后右上角立即变化，hilog `avatar preset applied id=1`）。

## 2026-11-10 用户第 2 轮反馈（已改，真机已验证的标注 ✅）

| 项 | 结果 |
| --- | --- |
| 附件不再分「图片/文件」 | ✅ 真机：面板只剩「选择文件」，系统选择器显示「Only show applicable file formats」（过滤生效） |
| 新会话 banner 去掉 | ✅ 已移除（`recommendAD` 拉取保留在 Scenes 里，随时可恢复） |
| 左侧「应用商城」入口去掉 | ✅ 已移除（手机端 `/ui/mall` 不是移动适配） |
| 自定义模型加知名 provider 预设 | ✅ DeepSeek / Moonshot / 阿里通义 / 智谱 GLM / OpenAI / SiliconFlow / Ollama，点一下填好 baseUrl+model |
| 设置里不显示网关 key | ✅ 换成「集群调度器 / 当前通道」 |
| 「充值 / 控制台」去掉 | ✅ 已移除 |
| 应用图标 + 主会话 logo 改回原 SCNet | ✅ `git checkout 9b98233 -- app_icon.png startIcon.png` |
| 设置页「检查更新」→ GitHub Releases | ✅ 真机（内嵌打开 releases 页）。⚠️ 仓库是 **private**（`gh repo view` 显示 visibility PRIVATE），所以无法匿名调 GitHub API 比版本；当前显示「当前版本 0.2.0 · 仓库私有，需在页面内登录 GitHub 查看」 |
| 设置页「关于」→ 作者 lql341 + GitHub 主页 | ✅ 真机（面板含图标/作者/GitHub/项目链接，均可点） |
| 登录页「非官方客户端」小字去掉 | ✅ 已移除 |
| 会话主窗口 AI 风险提示 | ✅ 空状态常驻一行「AI 生成内容可能不准确…请自行核实」 |
| 设置页顺序 | ✅ 自定义模型 → 主题 → 字号 → 语言 → 检查更新 → 关于 → 退出登录 |

## 2026-11-10 全量回归（用户授权后整体测试）

| # | 用例 | 结果 |
| --- | --- | --- |
| 1 | 构建 `assembleHap` | ✅ 无 ERROR |
| 2 | 单元测试 | ✅ 51/51（Markdown 30 / SSE 10 / 裁剪 13 / HMAC 8） |
| 3 | 深色模式（设置→外观→深色） | ✅ 背景/卡片/文字/主色/状态栏全部切换 |
| 4 | 深色下表格 + 正文 | 🐞 **发现 bug**：Markdown 内容保留深色文字色 → 已修（见下） |
| 5 | 切回浅色 | 🐞 **发现 bug**：表格标题/正文变近白不可见 → 已修 |
| 6 | 新会话首页 | ✅ 7 类场景 + AI 风险提示卡，banner 已移除 |
| 7 | 对话出字（智能体通道） | ✅ 流式 + 生成中指示 + 停止按钮 |
| 8 | Markdown 表格 | ✅ 表头 + 行标题 + 双列对照 + 斑马纹 |
| 9 | 算力服务（昆山） | ✅ 6 队列 / 作业列表 |
| 10 | 文件浏览 | ✅ 31 目录，可逐级进入 |
| 11 | 插件市场精选 | ✅ `featured picked: 8`（必应/FreeCAD/Fetch/Blender/COMSOL/MATLAB…） |
| 12 | OCR 自检 | ✅ `ocr selftest ok trace=c2b68c2f969c444b` |
| 13 | 崩溃扫描（全流程后） | ✅ JSCRASH / Fatal / TypeError 均无 |

### 这轮修掉的 2 个 bug（都是深色模式相关）

1. **深色下 Markdown 变暗**：`MarkdownView` 是子组件，静态 `Theme.xxx` 不参与依赖追踪，
   父级 `bumpRev` 重建时它没跟着重建 → 给 `MarkdownView` 加 `@Prop rev` 并作根 `.key()`。
2. **切回浅色后文字近白**：从设置页 `router.back()` 回到的是**已有**的 Index 实例，
   它的 `themeRev` 还是旧值 → `onPageShow()` 里对比 `store.getColorMode()` 与 `Theme.dark`，
   不一致就 `applyDark` + `bumpRev` 强制重建。

## 环境问题（会挡住后来者）

`hdc` 需要 udev 规则才能以普通用户访问 USB 设备，否则 `hdc list targets` 一直是 `[Empty]`：

```bash
sudo tee /etc/udev/rules.d/99-harmonyos-hdc.rules >/dev/null <<'EOF'
SUBSYSTEM=="usb", ATTR{idVendor}=="12d1", MODE="0666"
EOF
sudo udevadm control --reload-rules && sudo udevadm trigger
```

症状对照：`lsusb` 能看到 `12d1:5000 Huawei HDC Device`，但 `hdc` 日志报
`libusb: error [get_usbfs_fd] libusb couldn't open USB device, errno=13`（权限拒绝）。
