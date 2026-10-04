plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "dev.tailtap.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    sourceSets.getByName("main").assets.srcDir("../../build/license-assets")

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "dev.tailtap.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
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

dependencies {
    implementation("androidx.documentfile:documentfile:1.0.1")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

// jniLibs 不纳入版本控制，由 scripts/build-android-core.sh 生成。缺少目标 ABI 的原生核心时
// 直接让构建失败，避免打出装到设备上无法建立隧道的 APK。
val abiByFlutterPlatform = mapOf(
    "android-arm" to "armeabi-v7a",
    "android-arm64" to "arm64-v8a",
    "android-x64" to "x86_64",
)

val jniLibsDir = layout.projectDirectory.dir("src/main/jniLibs")

// scripts/build-android-core.sh 只能编译 arm64-v8a 与 x86_64。
val supportedNativeAbis = listOf("arm64-v8a", "x86_64")

val requestedNativeAbis: List<String> = run {
    if (project.findProperty("disable-abi-filtering")?.toString()?.toBoolean() == true) {
        emptyList()
    } else {
        val platforms = project.findProperty("target-platform")?.toString()
            ?.split(",")
            ?.map { it.trim() }
            ?.filter { it.isNotEmpty() }
            ?.takeIf { it.isNotEmpty() }
            ?: listOf("android-arm", "android-arm64", "android-x64")
        platforms.mapNotNull { abiByFlutterPlatform[it] }.distinct()
    }
}

val checkNativeCore = tasks.register("checkNativeCore") {
    group = "verification"
    description = "Checks that the native core exists for every requested ABI."
    doFirst {
        val unsupported = requestedNativeAbis.filterNot { it in supportedNativeAbis }
        val missing = requestedNativeAbis.filter { abi ->
            abi in supportedNativeAbis &&
                !(
                    jniLibsDir.file("$abi/libtailtap.so").asFile.isFile &&
                        jniLibsDir.file("$abi/libtailtap-jni.so").asFile.isFile
                )
        }
        val problems = buildList {
            if (unsupported.isNotEmpty()) {
                add(
                    "原生核心不支持 ${unsupported.joinToString(", ")}。请使用 " +
                        "--target-platform android-arm64 或 android-x64。",
                )
            }
            if (missing.isNotEmpty()) {
                add(
                    "缺少原生核心：" +
                        missing.joinToString(", ") { "src/main/jniLibs/$it/libtailtap.so" } +
                        "。先运行 ./scripts/build-android.sh，或执行 sh scripts/build-android-core.sh " +
                        missing.joinToString(" ") +
                        " 单独编译。",
                )
            }
        }
        if (problems.isNotEmpty()) throw GradleException(problems.joinToString("\n"))
    }
}

tasks.matching { it.name == "preBuild" }.configureEach { dependsOn(checkNativeCore) }
