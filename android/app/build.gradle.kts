plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.ytdownloader.app"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.ytdownloader.app"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
        ndk {
            abiFilters += setOf("arm64-v8a")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            // Keep release stable for native/reflection-heavy youtubedl stack.
            // R8 obfuscation causes startup crash in ZipUtils on launch.
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                // Non-optimize rules: proguard-android-optimize can break JNI/reflection
                // edge cases (e.g. youtubedl-android) that only show up in release.
                getDefaultProguardFile("proguard-android.txt"),
                "proguard-rules.pro",
            )
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
            doNotStrip += setOf(
                "**/libffmpeg.zip.so",
                "**/libpython.zip.so",
            )
        }
    }

    applicationVariants.all {
        val variant = this
        outputs.all {
            val appName = "yt-dlp"
            val versionName = variant.versionName ?: "0.0.0"
            val buildType = variant.buildType.name
            val newName = "$appName-$versionName-$buildType.apk"
            @Suppress("DEPRECATION")
            (this as com.android.build.gradle.internal.api.BaseVariantOutputImpl)
                .outputFileName = newName
        }
    }
}

dependencies {
    implementation("androidx.multidex:multidex:2.0.1")
    implementation("io.github.junkfood02.youtubedl-android:library:0.18.1")
    implementation("io.github.junkfood02.youtubedl-android:ffmpeg:0.18.1")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
}

flutter {
    source = "../.."
}
