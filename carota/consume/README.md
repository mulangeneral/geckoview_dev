# 接入说明

构建机（Linux）产出：

```
carota/maven-repo/org/mozilla/geckoview/geckoview-beta/157.0b5-carota1/
    geckoview-beta-157.0b5-carota1.aar
    geckoview-beta-157.0b5-carota1.pom
    geckoview-beta-157.0b5-carota1.aar.sha1
```

## 1. 把仓库同步到 Android 构建机

```bash
# 在 Linux 构建机上，仓库根目录执行
scp -r carota/maven-repo/* <user>@<windows-host>:D:/carotaapp/geckoview-m2/
```

Windows 侧目录结构应为
`D:\carotaapp\geckoview-m2\org\mozilla\geckoview\geckoview-beta\157.0b5-carota1\...`。

## 2. 让工程用上定制包（二选一）

### A. 零工程文件改动（推荐）

```powershell
# 放到用户级 init 脚本，对所有构建生效
Copy-Item carota\consume\init-carota-geckoview.gradle.kts `
          "$env:USERPROFILE\.gradle\init.d\carota-geckoview.init.gradle.kts"

# 或在命令行显式指定（CI 友好）
.\gradlew.bat -I D:\carotaapp\geckoview_work\carota\consume\init-carota-geckoview.gradle.kts `
    :n80ks:assembleN60-btk8676Release
```

脚本做两件事：
1. 在 settings 级注入本地 Maven 仓库（工程是 `RepositoriesMode.FAIL_ON_PROJECT_REPOS`，只能在 settings 级加）；
2. 把 `org.mozilla.geckoview:geckoview-beta` 的版本强制为 `157.0b5-carota1`。

校验：

```powershell
.\gradlew.bat -I <init 脚本路径> :n80ks:dependencies --configuration N60-btk8676ReleaseRuntimeClasspath |
    Select-String geckoview
# 期望看到 org.mozilla.geckoview:geckoview-beta:157.0b5-carota1 -> ...（或 geckoview-beta-carota）
```

### B. 只改一行依赖（不用 init 脚本）

把 `n80ks/build.gradle.kts` 里的

```kotlin
implementation(libs.gv.beta)
```

换成

```kotlin
implementation("org.mozilla.geckoview:geckoview-beta:157.0b5-carota1") // 需要本地/内网 Maven
```

并在 `settings.gradle.kts` 的 `dependencyResolutionManagement.repositories` 里加本地仓库。
注意：工程里针对 `geckoview-beta` 的 `resolutionStrategy`（androidx.core/lifecycle 钉版本）不依赖坐标名，仍生效。

### C. 直接吃 AAR 文件（最省事但会丢传递依赖，不推荐）

```kotlin
implementation(files("libs/geckoview-beta-157.0b5-carota1.aar"))
```

`files()` 不会带传递依赖，需要自己补：
`androidx.annotation:annotation:1.10.0`、`androidx.annotation:annotation-experimental:1.6.0`、
`androidx.collection:collection:1.6.0`、`androidx.core:core:1.19.0`（工程已钉 1.17.0）、
`androidx.lifecycle:lifecycle-common/process:2.11.0`（工程已钉 2.10.0）、
`com.google.android.gms:play-services-fido:21.3.1`、`org.yaml:snakeyaml:2.2`、`androidx.media3:*:1.11.0`。
</br>其中 play-services-fido 是工程当前没有的，漏了会在 WebAuthn/Passkey 场景运行时报错。