import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) load(FileInputStream(f))
}

android {
    namespace = "com.ahlalive.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.ahlalive.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Workaround for AndroidX Window compatibility with older emulators
        vectorDrawables.useSupportLibrary = true
    }

    // Workaround for AndroidX Window compatibility with older emulators
    // These classes are only available on API 31+ but Flutter 3.47+ requires them
    packagingOptions {
        resources {
            excludes += "/META-INF/INDEX.LIST"
            pickFirsts += "**/kotlin-reflect.jlibr"
        }
    }

    signingConfigs {
        if (keystoreProperties["storeFile"] != null) {
            create("release") {
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystoreProperties["storeFile"] != null)
                signingConfigs.getByName("release")
            else
                signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Firebase BOM
    implementation(platform("com.google.firebase:firebase-bom:33.9.0"))
    // ✅ SVGAPlayer Native — نفس المكتبة التي يستخدمها التطبيق الأصلي
    //    تُشغَّل عبر PlatformView (AndroidView) من Flutter لتحقيق سرعة Native
    implementation("com.github.yyued:SVGAPlayer-Android:2.6.1")
}
