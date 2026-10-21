import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 发布签名：android/key.properties 存在时使用稳定密钥；否则沿用 debug 签名，
// 仅适合本地调试。应用内更新要求相邻版本使用同一签名，正式发布必须配置此文件。
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseSigning = keystorePropertiesFile.exists()
val keystoreProperties = Properties().apply {
    if (hasReleaseSigning) {
        FileInputStream(keystorePropertiesFile).use { load(it) }
    }
}

android {
    namespace = "top.zonwe.simul_groove_player"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "top.zonwe.simul_groove_player"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        // Flutter 会按 ABI 给 versionCode 加千位偏移（例如 arm64 的 4 变成 2004）。
        // 应用内更新比较的是 pubspec 的构建号，因此把 `+build` 写进 versionName，
        // 让 package_info_plus 在 Android 上返回 1.1.0+4，而不是 1.1.0+2004。
        versionName = "${flutter.versionName}+${flutter.versionCode}"
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                val storeFilePath = keystoreProperties.getProperty("storeFile")
                    ?: error("android/key.properties 缺少 storeFile")
                storeFile = file(storeFilePath)
                storePassword = keystoreProperties.getProperty("storePassword")
                    ?: error("android/key.properties 缺少 storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                    ?: error("android/key.properties 缺少 keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                    ?: error("android/key.properties 缺少 keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // 没有 key.properties 时保持原有的可运行调试行为；但这样的 APK
            // 不能用于应用内更新（每次 CI 的 debug 证书都不同）。
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
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
