plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.hoza_send"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications uses java.time on all API levels, which
        // only exists natively from API 26. Desugaring back-ports it, so the
        // app can still run on older phones.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.example.hoza_send"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // The desugared library plus the plugin set pushes past the 64k method
        // limit on older API levels.
        multiDexEnabled = true
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
    // Required by the compileOptions flag above. Must be 2.1.x or newer for
    // the AGP version Flutter 3.44 ships with.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")

    // FileProvider, for handing a received file to the app that opens its
    // kind. Declared rather than inherited from a plugin: the host code
    // compiles against it, and a transitive dependency can be dropped by
    // whichever plugin happened to be bringing it in.
    implementation("androidx.core:core:1.13.1")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
