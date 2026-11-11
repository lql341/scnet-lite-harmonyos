# ANDROID-DEV — 原生 Android 版开发/调试

> `android/` 是**原生实现**（Java + 框架控件，不用 Gradle / AndroidX / Compose）。
> 这里只记「怎么跑起来、怎么在没有账号的情况下验 UI」。

## 1. 环境

| 需要 | 说明 |
| --- | --- |
| JDK 17+ | 本机 `~/opt/apps/jdk/21.0.13+9`（`javac --release 8` 也可） |
| Android SDK | `platforms;android-34` + `build-tools;35.0.0`（34.0.0 的 d8 有 NPE bug） |
| `ANDROID_HOME` | 指向 SDK 根（本机 `~/android-sdk`；脚本也会找 `~/Android/Sdk`、`/tmp/asdk/sdk`） |

装 SDK（只需一次）：

```bash
export ANDROID_HOME=~/android-sdk
mkdir -p "$ANDROID_HOME/cmdline-tools" && cd "$ANDROID_HOME/cmdline-tools"
curl -LO https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip
unzip -q commandlinetools-linux-*.zip && mv cmdline-tools latest
yes | ./latest/bin/sdkmanager --sdk_root="$ANDROID_HOME" --licenses >/dev/null
./latest/bin/sdkmanager --sdk_root="$ANDROID_HOME" \
  "platforms;android-34" "build-tools;35.0.0" "platform-tools"
```

## 2. 构建 / 自检

```bash
scripts/test-android.sh      # 纯 JVM：Markdown / SSE / 裁剪 / HMAC，43 条
scripts/build-apk.sh         # → dist/android/scnet-agent-android-<ver>.apk（约 8 s / 165 KB）
DEBUG=1 scripts/build-apk.sh # 可调试包（android:debuggable=true，能 run-as）
```

签名 keystore 默认放在 `~/.android/scnet-agent.keystore`（**不要**放构建目录，否则每次 key 都变、
用户无法覆盖升级）。要换：`APK_KEYSTORE=/path/to.keystore`。

## 3. 模拟器（无设备时）

```bash
export ANDROID_HOME=~/android-sdk ANDROID_AVD_HOME=~/avd
$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager --sdk_root=$ANDROID_HOME \
  "emulator" "system-images;android-30;default;x86_64"
echo no | $ANDROID_HOME/cmdline-tools/latest/bin/avdmanager create avd \
  -n scnet -k "system-images;android-30;default;x86_64" -d pixel_5 --force
$ANDROID_HOME/emulator/emulator -avd scnet -no-window -no-audio -no-boot-anim \
  -gpu swiftshader_indirect -no-snapshot &
$ANDROID_HOME/platform-tools/adb wait-for-device
adb install -r dist/android/scnet-agent-android-0.4.0.apk
adb shell am start -n cn.scnet.agent/.MainActivity
adb exec-out screencap -p > /tmp/shot.png
```

> 系统镜像约 3.2 GB，放 `/tmp`（tmpfs）会 "Disk quota exceeded"，务必放真实磁盘。

## 4. 没有账号怎么验 UI

登录态只是 SharedPreferences 里的 `cloudToken`/`cloudCookie`，用 **debug 包**注入即可：

```bash
adb uninstall cn.scnet.agent
adb install -r /tmp/apkdebug/scnet-agent-android-0.4.0-debugtest.apk
adb shell "run-as cn.scnet.agent mkdir -p shared_prefs"
adb shell "run-as cn.scnet.agent sh -c 'cat > shared_prefs/scnet_lite.xml'" <<'EOF'
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<map>
  <string name="cloudToken">dummy</string>
  <string name="cloudCookie">jsessionid=dummy</string>
  <string name="hadSession">1</string>
  <string name="platformUserName">张测试</string>
  <string name="themePalette">ocean</string>
</map>
EOF
```

再开飞行模式（避免假 token 触发的 401 跳回登录页）：

```bash
adb shell settings put global airplane_mode_on 1
adb shell am broadcast -a android.intent.action.AIRPLANE_MODE --ez state true
```

这样能验：空状态 / 抽屉 / 会话列表 / Markdown 渲染 / 深色模式 / 各页空态与错误卡。
**真实登录、流式出字、作业提交**仍然需要真机 + 真实账号。

## 5. 造一份 Markdown 会话（验渲染）

```bash
adb push s_mdtest.json /data/local/tmp/s.json
adb push index.json   /data/local/tmp/i.json
adb shell "run-as cn.scnet.agent sh -c 'mkdir -p files/sessions \
  && cp /data/local/tmp/s.json files/sessions/s_mdtest.json \
  && cp /data/local/tmp/i.json files/sessions/index.json'"
adb shell am force-stop cn.scnet.agent && adb shell am start -n cn.scnet.agent/.MainActivity
```

会话文件结构见 `svc/Sessions.java`：`{id,title,model,createdAt,updatedAt,messages[{role,content,via}]}`。

## 5.1 调试钩子（无常驻自动化时最有用）

MIUI 默认禁输入注入（`input tap` 报 `INJECT_EVENTS`），所以验证靠这些 Intent 参数：

```bash
# 打开某个页面（绕过点击）：profile / jobs / files / ocr / market / aihub
adb shell am start -n cn.scnet.agent/.MainActivity --es open jobs

# 渲染内置样张（行内图/表格/代码块）
adb shell am start -n cn.scnet.agent/.MainActivity --ez mdtest true

# 渲染任意 markdown：先推到 files/md.txt，再拉起
adb push md.txt /sdcard/Android/data/cn.scnet.agent/files/md.txt
adb shell am start -n cn.scnet.agent/.MainActivity --ez newchat true --ez mdfile true

# 自动发一条（验证真实 SSE / 图片帧）
adb shell am start -n cn.scnet.agent/.MainActivity \
  --es prefill "如何上传算例文件？" --ez autosend true

# 打开平台历史里某个会话
adb shell am start -n cn.scnet.agent/.MainActivity --es convid <conversationId>

# 把平台历史原始 JSON 落盘（排查图片/资源字段）
adb shell am start -n cn.scnet.agent/.MainActivity --ez dumphistory true
adb pull /sdcard/Android/data/cn.scnet.agent/files/stream.log
```

`stream.log` 还会记录每次流的非正文帧（`todolist` / `tool-*` / 资源卡片）与最终正文里的全部 URL。

## 6. 已知坑

| 现象 | 原因 |
| --- | --- |
| `INSTALL_FAILED_UPDATE_INCOMPATIBLE` | 签名 key 变了（keystore 被重建） |
| d8 `NullPointerException: String.length()` | build-tools 34.0.0 的 d8 对非静态内部类会崩；用 35.0.0 |
| 底部面板高度为 0 | Dialog 是 wrap_content，不能给 ScrollView 用 weight |
| `run-as` 报错 | 装的是 release 包（不可调试） |
| 网络请求全失败 | 模拟器飞行模式忘了关 |
| `adb install` 报 `INSTALL_FAILED_USER_RESTRICTED` | MIUI：开发者选项打开「USB 安装」 |
| 设备在 `adb devices` 里消失、`lsusb` 显示 `2717:ff40` | USB 用途被重置成 MTP；重新选「传输文件」，让 PID 回到 `ff08` |
| `input tap` 报 `INJECT_EVENTS` | 需要「USB 调试（安全设置）」；没开就用上面的 Intent 钩子 |
