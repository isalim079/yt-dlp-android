plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android plugin.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.ytdownloader.app"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion



    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.ytdownloader.app"
        minSdk = flutter.minSdkVersion
        targetSdk = 37
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    testOptions {
        unitTests.isReturnDefaultValues = true
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            // Keep release stable for native/reflection-heavy youtubedl stack.
            // R8 obfuscation causes startup crash in ZipUtils on launch.
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
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

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    implementation("androidx.multidex:multidex:2.0.1")
    implementation("io.github.junkfood02.youtubedl-android:library:0.18.1")
    implementation("io.github.junkfood02.youtubedl-android:ffmpeg:0.18.1")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
    // InnerTube browse / continuations for Home + Shorts feeds.
    implementation("com.github.TeamNewPipe:NewPipeExtractor:v0.24.8")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
}

flutter {
    source = "../.."
}
