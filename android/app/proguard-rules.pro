# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Riverpod
-keep class dev.flutter.** { *; }

# Keep yt-dlp binary references
-keep class com.ytdownloader.** { *; }

# youtubedl-android + ffmpeg + common (R8 strips/obfuscates these otherwise;
# init() loads libpython/libffmpeg from nativeLibraryDir.)
-keep class com.yausername.** { *; }
-keepclassmembers class com.yausername.** { *; }

# Permission handler
-keep class com.baseflow.permissionhandler.** { *; }

# File picker
-keep class com.mr.flutter.plugin.filepicker.** { *; }

# receive_sharing_intent (Kotlin plugin; registers at engine attach)
-keep class com.kasem.receive_sharing_intent.** { *; }

# connectivity_plus
-keep class dev.fluttercommunity.plus.connectivity.** { *; }

# Flutter deferred components / Play Core (referenced by embedding; optional at runtime)
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.SplitInstallException
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManager
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManagerFactory
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest$Builder
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest
-dontwarn com.google.android.play.core.splitinstall.SplitInstallSessionState
-dontwarn com.google.android.play.core.splitinstall.SplitInstallStateUpdatedListener
-dontwarn com.google.android.play.core.tasks.OnFailureListener
-dontwarn com.google.android.play.core.tasks.OnSuccessListener
-dontwarn com.google.android.play.core.tasks.Task
