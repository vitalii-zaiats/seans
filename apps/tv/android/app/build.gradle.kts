import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The upload key, when there is one.
//
// `key.properties` is never committed — it names a keystore and holds its
// passwords. CI writes both from secrets before it builds; a checkout without
// them still builds, with the debug key, so `flutter run --release` works on a
// laptop that has no business holding the release key.
val keyProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val signed = keyProperties.getProperty("storeFile") != null

android {
    // Renamed with the rest of the brand, and that was only free because
    // nothing has shipped yet: to Android an `applicationId` *is* the app.
    // Changing it after a release renames nothing — it publishes a second,
    // unrelated app, and every box holding the old one keeps it, side by side,
    // with its own settings and its own watch list.
    //
    // `api.settings.android_package` has to say the same string, or the store
    // link the API hands out in `/init` points at an app that does not exist.
    namespace = "tv.seans.launcher"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "tv.seans.launcher"
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

    signingConfigs {
        if (signed) {
            create("release") {
                storeFile = rootProject.file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // The upload key where one is configured, the debug key otherwise.
            //
            // Falling back rather than failing is deliberate: a release build
            // that refuses to run without the signing key makes every developer
            // machine need a copy of it, which is the fastest way for a signing
            // key to end up somewhere it should not be. An APK signed with the
            // debug key installs on a box and cannot be published — which is
            // exactly the distinction worth having.
            signingConfig = signingConfigs.getByName(if (signed) "release" else "debug")
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
