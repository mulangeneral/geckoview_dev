// Carota 定制 GeckoView 157 的「零工程改动」接入脚本。
//
// 用法（三选一）：
//   1) 放到 %USERPROFILE%\.gradle\init.d\carota-geckoview.init.gradle.kts （对本机所有构建生效）
//   2) ./gradlew -I carota/consume/init-carota-geckoview.gradle.kts :n80ks:assembleN60-btk8676Release
//   3) CI 里用 GRADLE_OPTS 或 wrapper 参数带上 -I
//
// 环境变量：
//   CAROTA_GECKOVIEW_MAVEN   本地 Maven 仓库目录，默认 D:/carotaapp/geckoview-m2
//   CAROTA_GECKOVIEW_VERSION 定制包版本，默认 157.0b5-carota1
//   CAROTA_GECKOVIEW_STRICT  设为 1 时，仓库里找不到定制包直接失败（CI 建议开启）

val carotaMavenUrl: String =
    System.getenv("CAROTA_GECKOVIEW_MAVEN") ?: "D:/carotaapp/geckoview-m2"
val carotaVersion: String =
    System.getenv("CAROTA_GECKOVIEW_VERSION") ?: "157.0b5-carota1"
val strict: Boolean = System.getenv("CAROTA_GECKOVIEW_STRICT") == "1"

settingsEvaluated {
    dependencyResolutionManagement {
        repositories.maven {
            name = "carotaGeckoview"
            url = uri(carotaMavenUrl)
            content { includeGroup("org.mozilla.geckoview") }
        }
    }

    val artifactDir = file(
        "$carotaMavenUrl/org/mozilla/geckoview/geckoview-beta/$carotaVersion"
    )
    if (!artifactDir.isDirectory) {
        val msg = "[carota-geckoview] 未在 $artifactDir 找到定制 GeckoView，" +
            "将回落到官方 geckoview-beta"
        if (strict) throw GradleException(msg) else logger.warn(msg)
    }
}

gradle.allprojects {
    configurations.all {
        resolutionStrategy.eachDependency {
            if (requested.group == "org.mozilla.geckoview" &&
                requested.name == "geckoview-beta"
            ) {
                useVersion(carotaVersion)
                because("Carota 定制 GeckoView 157：媒体控制只对视频注册（含静音视频）")
            }
        }
    }
}