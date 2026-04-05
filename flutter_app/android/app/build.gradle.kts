plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ---------------------------------------------------------------------------
// Rust / cargo-ndk integration
// ---------------------------------------------------------------------------
val rustDir = file("${rootProject.projectDir}/../rust/frodo_bridge")
val isWindows = System.getProperty("os.name").lowercase().contains("windows")
val cargoExe = System.getenv("CARGO")
    ?: if (isWindows) "${System.getenv("USERPROFILE")}\\.cargo\\bin\\cargo.exe"
       else "${System.getenv("HOME")}/.cargo/bin/cargo"
val enableRustNative = providers.gradleProperty("enableRustNative").orElse("true").get().equals("true", ignoreCase = true)
val hostSdl2Dir = file("${rootProject.projectDir}/../../android/app/build/intermediates/merged_native_libs/debug/mergeDebugNativeLibs/out/lib/arm64-v8a")
val hostSdl2So = file("${hostSdl2Dir}/libSDL2.so")
val appSdl2Dir = file("${projectDir}/src/main/jniLibs/arm64-v8a")
val appSdl2So = file("${appSdl2Dir}/libSDL2.so")
val androidSdkRoot = System.getenv("ANDROID_SDK_ROOT")
    ?: System.getenv("ANDROID_HOME")
    ?: "${System.getenv("LOCALAPPDATA")}\\Android\\Sdk"
val ndkHostTag = if (isWindows) "windows-x86_64" else "linux-x86_64"
val ndkLibCppSharedArm64 = file("${androidSdkRoot}/ndk/29.0.14206865/toolchains/llvm/prebuilt/${ndkHostTag}/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so")

fun resolveSdl2ForLink(): File {
    return if (hostSdl2So.exists()) {
        hostSdl2So
    } else {
        appSdl2So
    }
}

fun buildRustLib(abi: String, target: String) {
    exec {
        workingDir = rustDir
        if (abi == "arm64-v8a") {
            environment("SDL2_LIB_DIR", resolveSdl2ForLink().parentFile.absolutePath)
        }
        commandLine(cargoExe, "ndk", "--target", target, "--platform", "21", "--", "build", "--release")
    }
}

tasks.register("buildRustNative") {
    doLast {
        if (!resolveSdl2ForLink().exists()) {
            throw GradleException("Missing SDL2 library for Rust link. Expected either ${hostSdl2So.absolutePath} or ${appSdl2So.absolutePath}.")
        }
        if (!ndkLibCppSharedArm64.exists()) {
            throw GradleException("Missing libc++_shared.so at ${ndkLibCppSharedArm64.absolutePath}.")
        }
        // Build for arm64-v8a (primary target)
        buildRustLib("arm64-v8a", "aarch64-linux-android")
        // Uncomment for additional ABIs:
        // buildRustLib("armeabi-v7a", "armv7-linux-androideabi")
        // buildRustLib("x86_64", "x86_64-linux-android")
    }
}

// Copy .so files into jniLibs
tasks.register<Copy>("copyRustLibs") {
    dependsOn("buildRustNative")
    val releaseDir = "${rustDir}/target"
    from("${releaseDir}/aarch64-linux-android/release/libfrodo_bridge.so") {
        into("arm64-v8a")
    }
    from(resolveSdl2ForLink()) {
        into("arm64-v8a")
    }
    from(ndkLibCppSharedArm64) {
        into("arm64-v8a")
    }
    into("${projectDir}/src/main/jniLibs")
}

tasks.named("preBuild") {
    if (enableRustNative) {
        dependsOn("copyRustLibs")
    }
}

android {
    namespace = "org.simplec64.frodo_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "29.0.14206865"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "org.simplec64.frodo_app"
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

flutter {
    source = "../.."
}

dependencies {
    implementation("commons-io:commons-io:2.14.0")
    implementation("org.apache.commons:commons-compress:1.25.0")
    implementation("org.tukaani:xz:1.9")
}
