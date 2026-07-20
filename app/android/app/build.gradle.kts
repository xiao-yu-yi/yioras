plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.yiora.yiora"
    compileSdk = flutter.compileSdkVersion
    // 纯 Dart/Kotlin 工程无 C/C++ 代码，不声明 ndkVersion（本机未装 NDK 且
    // dl.google.com 不可达无法下载）；引入含原生 .so 的插件时再恢复此配置。
    // Flutter Gradle 插件会通过空 CMake 工程强制 AGP 下载 NDK（forceNdkDownload），
    // 这里反向清除该配置，避免离线环境构建失败。
    externalNativeBuild {
        cmake {
            path = null
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.yiora.yiora"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
