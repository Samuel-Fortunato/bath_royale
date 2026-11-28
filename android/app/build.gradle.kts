plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val developmentBuild = System.getenv("BATH_BUILD_CHANNEL") == "development"
val fixtureTarget = project.findProperty("target").toString().let { it.endsWith("tool/local_development.dart") || it.endsWith("tool/auth_device_preview.dart") }
require(!fixtureTarget || developmentBuild) { "Isolated targets require the separate development package" }

val performanceProbe = System.getenv("BATH_PERFORMANCE_PROBE") == "true"
require(performanceProbe == project.findProperty("target").toString().endsWith("tool/performance_probe.dart")) {
    "The fictional performance target requires BATH_PERFORMANCE_PROBE=true and its separate application ID"
}

android {
    namespace = "com.example.bath_royale"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.bath_royale"
        // Isolated, fictional-data AOT probe; never replace the owner's app.
        if (developmentBuild) {
            applicationIdSuffix = ".development"
        } else if (performanceProbe) {
            applicationIdSuffix = ".performance"
        }
        manifestPlaceholders["applicationLabel"] = if (performanceProbe) "Bath Royale — Medição" else "Bath Royale"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Explicit preview signing never falls back to an automatically generated key.
    val signingMetadata = System.getenv("PREVIEW_SIGNING_CONFIG")?.let {
        groovy.json.JsonSlurper().parse(file(it)) as Map<*, *>
    }
    val previewKeystore = System.getenv("PREVIEW_KEYSTORE")
    signingConfigs {
        if (previewKeystore != null) {
            require(file(previewKeystore).isFile) { "Existing preview keystore required" }
            create("preview") {
                storeFile = file(previewKeystore)
                storePassword = (signingMetadata?.get("store_password") as? String) ?: "android"
                keyAlias = (signingMetadata?.get("alias") as? String) ?: "androiddebugkey"
                keyPassword = (signingMetadata?.get("key_password") as? String) ?: "android"
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(
                if (previewKeystore != null) "preview" else "debug"
            )
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
