# Carota GeckoView 157 定制构建（方案 A）

用 **Firefox 157.0b5 全量源码 + 一条媒体控制补丁**，重建一份可替代官方
`org.mozilla.geckoview:geckoview-beta` 的 AAR，保留原本地定制 AAR
（`n80ks/libs/geckoview-release-ad.aar`，142.0a1）的行为。

## 1. 版本对应关系（已核对）

| 项 | 值 |
|---|---|
| Git 提交（mozilla-firefox/firefox） | `46056a25c157e52da994bef01ae29463aa0dba9a` |
| hg revision（mozilla-beta） | `1d349a6de68c5b3e8e0db2493d871eef1926d837` |
| 标签 | `FIREFOX_157_0b5_RELEASE` |
| `browser/config/version.txt` | `157.0` |
| `browser/config/version_display.txt` | `157.0b5` |
| 对应官方 AAR | `org.mozilla.geckoview:geckoview-beta:157.0.20260923115834` |

> 核对方式：官方 AAR 的 POM `scm.tag` 是 hg `1d349a6d…`，hg JSON API 返回
> `git_commit: 46056a25…`，与上面 git 提交一致；AAR 版本号里的时间戳
> `20260923115834` 与该提交的 push 时间（2026-09-23 11:58 UTC）吻合。

## 2. 定制内容

唯一改动：`dom/media/mediaelement/HTMLMediaElement.cpp` 的
`HTMLMediaElement::StartMediaControlKeyListenerIfNeeded()`（157 里
`HTMLMediaElement.cpp` 已从 `dom/html/` 搬到 `dom/media/mediaelement/`，
`ShouldStartMediaControlKeyListener()` 也被重构成了这个函数）。

改后语义：

1. **纯音频不注册媒体控制** —— GeckoView 的 `MediaSession.Delegate.onPlay` 只代表视频；
2. **视频豁免上游的可听性延迟检查** —— 静音/零音量/autoplay-muted 的 `<video>` 也会注册，
   从而照常触发 `onPlay`；
3. 实时流（`mSrcStream`）不注册；时长过短的视频仍由
   `MediaControlKeyListener::Start()` 里的 `ControlType::eUncontrollable` 分支过滤
   （等价于 142 定制包里的 duration 阈值）。

行为对照（关键）：

| 场景 | 142 定制 AAR | 官方 157 beta | 本定制 157 |
|---|---|---|---|
| 静音 / autoplay-muted 视频起播 → `onPlay` | ✅ | ❌（上游延迟启动过滤掉） | ✅ |
| 纯音频（音乐/播客）起播 → `onPlay` | ❌ | ✅（会被行车抑制误暂停） | ❌ |
| `RedirectPrompt`（跨域 iframe 重定向顶层） | 私有补丁 | **157 官方已内置**（`PromptController.java` + `toolkit/actors/PopupAndRedirectBlocking*`） | 用官方实现，不再打补丁 |
| `MediaSession.isVideo()` | 源码有、AAR 未编入；应用未调用 | 无 | 未提供（应用未用） |

> 应用侧依据：`n80ks/src/main/java/com/carota/bjev/ui/activity/MainActivity.kt`
> 的 `MediaSessionDelegate.onPlay` 只要 `isDrivingVideoRestricted` 就 `mediaSession.pause()`，
> 且全工程没有调用 `isVideo()`，所以「onPlay 只代表视频」这条必须在引擎侧保证。

## 3. 准备源码分支（Linux）

> **现状（已生成并推送）**：`geckoview-157-src` 分支已在 origin 上，
> 导入树与上游 `46056a25…` 逐字节一致（根树 `4815090c0043a4cd6421ee6e3a1fda9c80154356`、
> 480,474 个文件、1,834 个可执行位），并在其上叠了 1 个定制补丁提交 + 1 个脚本提交。
> Linux 构建机**不需要再跑本脚本**，直接：
>
> ```bash
> git fetch origin geckoview-157-src
> git checkout geckoview-157-src
> ```
>
> 脚本保留给以后升级内核版本（换 `BASE_REV`）时复用。

```bash
git clone git@github.com:mulangeneral/geckoview_dev.git
cd geckoview_dev
git checkout geckoview-157-carota

./carota/prepare-157-src.sh          # 生成 geckoview-157-src 分支
# PUSH=1 ./carota/prepare-157-src.sh # 顺便推送到 origin
```

脚本做四件事：

1. `git fetch --depth 1 <mozilla-firefox/firefox> 46056a25…`（整棵树，约 500MB）；
2. 新建 `geckoview-157-src` 分支，`git read-tree --reset -u FETCH_HEAD`
   把工作区整棵替换成 157 源码，并提交为 `Import Firefox 157.0b5 GeckoView source`；
3. 应用 `carota/patches/0001-media-control-video-only-157.patch`；
4. 把 `carota/` 构建脚本带回源码分支并提交。

> 补丁已用 157 原始文件验证过 `git apply --check` 通过（无 fuzz）。
> 磁盘：157 源码树约 9GB，构建 objdir 约 25-40GB。

## 4. 构建 AAR（Linux）

```bash
git checkout geckoview-157-src
cp carota/mozconfig-android mozconfig     # 按构建机改 SDK/NDK/JDK 路径
./mach bootstrap                          # 首次
./carota/build-aar.sh
```

脚本流程：

1. `./mach build`（首次 40-120 分钟）；
2. `./mach gradle geckoview:assembleRelease`（`machStagePackage` 会把 `libxul.so`、
   `omni.ja` 等塞进 AAR）；
3. 校验 AAR 里有 `jni/arm64-v8a/libxul.so`、`assets/omni.ja`，并且在 `libxul.so` 中
   能搜到定制字符串 `Not listening because it's an audio element`；
4. 产出本地 Maven 布局：

```
carota/out/geckoview-beta-157.0b5-carota1.aar
carota/maven-repo/org/mozilla/geckoview/geckoview-beta/157.0b5-carota1/
    geckoview-beta-157.0b5-carota1.{aar,pom,sha1}
```

`mozconfig-android` 关键项：`--enable-application=mobile/android`、
`--target=aarch64-linux-android`（只出 arm64，和现有 `abiFilters` 一致，避免 APK 被 4 ABI 撑大）、
`--enable-optimize`、`--disable-debug`。
**不要**加 `--enable-geckoview-lite`：工程用了 `WebExtension`（`BrowserRuntimeManager.kt`），需要 omni 包。

## 5. 接入产品工程

见 `carota/consume/README.md`：把 `carota/maven-repo` 同步到
`D:\carotaapp\geckoview-m2`，用 `carota/consume/init-carota-geckoview.gradle.kts`
做依赖替换——**不改工程任何文件**。

```powershell
.\gradlew.bat -I D:\carotaapp\geckoview_work\carota\consume\init-carota-geckoview.gradle.kts `
    :n80ks:assembleN60-btk8676Release
```

## 6. 验收清单

1. `gradlew :n80ks:dependencies --configuration N60-btk8676ReleaseRuntimeClasspath`
   里 geckoview 是 `157.0b5-carota1`；
2. APK 里 `lib/arm64-v8a/libxul.so` 含 `Not listening because it's an audio element`；
3. 车机 logcat：静音/自动播放视频起播要出现 `onPlay:...`；纯音频（音乐/播客）起播不能出现；
4. 回归：抖音（`geckoview_config.yaml` 的 `layers.gpu-process.enabled=false` 是否仍必要）、
   Web Speech、AdBlock 白名单、HLS/DRM、扩展安装、前进/后退不黑屏；
5. 换内核后必须 `:n80ks:clean`（增量打包会残留上一版内核中间产物）。

## 7. 常见问题

- **`assembleRelease` 产物里没有 libxul.so**：说明不是 full build（`COMPILE_ENVIRONMENT` 为 false），
  或 objdir 是旧的；确认 `./mach build` 真正跑完，必要时删 objdir 重来。
- **AAR 体积异常/行为没变化**：多半是增量构建残留，`rm -rf obj-carota-157` 后重建。
- **`./mach bootstrap` 装不上**：构建机需要 JDK 17、Android SDK/NDK、rust、clang、python3。
- **想要 `MediaSession.isVideo()`**：需要额外移植 142 的 Java/JS/C++ 三层补丁
  （`ec8f9d9df4` + `806d1bac9b` + `f97502958e`）；当前应用未使用该 API，所以没有移植。

## 8. 目录

```
carota/
├── README.md                               # 本文
├── prepare-157-src.sh                      # 拉 157 源码 + 打补丁，生成 geckoview-157-src
├── build-aar.sh                            # mach build + assembleRelease + 本地 Maven 布局
├── mozconfig-android                       # mozconfig 模板
├── patches/
│   └── 0001-media-control-video-only-157.patch
├── maven/pom-template.xml                  # AAR 的 POM（依赖表抄官方 157 POM）
└── consume/
    ├── init-carota-geckoview.gradle.kts    # 零工程改动的依赖替换脚本
    └── README.md                           # 接入说明
```
## 9. isVideo / 音频媒体控制（增补）

`geckoview-157-src` 在 157 重构后的媒体控制代码上补齐了 main 分支的 isVideo 能力
（对应 main 的 `ec8f9d9df4` + `806d1bac9b` + `f97502958e`）：

- `MediaSession.isVideo()` 与事件里的 `isVideo` 字段：app 用它区分音视频；
- 视频元素（含静音 / 音量 0）不受可听性限制，照常触发 `onPlay`；
- 可听音频也会注册媒体控制，因此可被 `MediaSession.pause()/play()` 暂停和续播；
- 视频起播/停播但聚合播放态未变时补发 `videomediachange`，避免“音频在播时视频起播”漏报。

配套的应用侧约束：`MainActivity.onPlay` 必须按 `mediaSession.isVideo` 门控行车抑制，
否则“受限状态下音频起播”会被误暂停。

补丁文件：`carota/patches/0002-media-control-isvideo-157.patch`（在 `9359b6ac5b` 之上）。