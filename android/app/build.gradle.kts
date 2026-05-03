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
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            // Keep release stable for native/reflection-heavy youtubedl stack.
            // R8 obfuscation causes startup crash in ZipUtils on launch.
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
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
        resources.excludes += setOf(
            "**/kotlin/**",
            "**/*.kotlin_module",
            "**/META-INF/*.version",
            "**/META-INF/proguard/**",
            "**/META-INF/androidx.*",
        )
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
