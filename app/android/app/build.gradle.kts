// 必须显式 import java.util.Properties，不能写 java.util.Properties()：
// Gradle Kotlin DSL 里 `java` 会解析成项目级 Java 扩展（JavaPluginExtension），
// 于是 `java.util` 被当成该扩展的属性访问 → 报"Unresolved reference 'util'"，
// 连带 getProperty/load 全部失效，最终整个 assembleRelease 编译中断。
// 注意：import 必须放在 plugins {} 块之前，放在后面同样编译失败。
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ── release 签名：从 android/key.properties 读取（该文件不入库）──
// 为什么必须改：原来 release 直接用 debug 签名（下面的 TODO），后果是
// ① 任何人都能用同一把 debug key 生成同包名包覆盖你的安装；
// ② debug 签名过不了任何应用商店审核。
// 对存放私密照片的 App 这是硬伤，所以这里改成「缺配置就明确失败」。

val keystorePropsFile = rootProject.file("key.properties")
val keystoreProps = Properties().apply {
    if (keystorePropsFile.exists()) {
        keystorePropsFile.inputStream().use { load(it) }
    }
}
val hasReleaseSigning = keystoreProps.getProperty("storeFile")?.isNotBlank() == true

android {
    namespace = "com.dapei.dapei_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.dapei.dapei_app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = keystorePropsFile.parentFile.resolve(
                    keystoreProps.getProperty("storeFile"),
                )
                storePassword = keystoreProps.getProperty("storePassword")
                keyAlias = keystoreProps.getProperty("keyAlias")
                keyPassword = keystoreProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                // 缺 key.properties 时直接中断构建。早年那句
                // 「Signing with the debug keys for now」让问题彻底隐形——
                // 构建照过、装到手机上也没人发现，直到某天商店拒审或包被顶替。
                throw GradleException(
                    "缺少 android/key.properties，release 签名未配置，拒绝用 debug 签名出包。" +
                        "照 key.properties.example 填好（keystore 文件别提交进 git）；" +
                        "仅本地跑 demo 可用 flutter run --debug，不受此限制。",
                )
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
