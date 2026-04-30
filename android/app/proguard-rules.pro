# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn com.google.android.play.core.**
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable

# youtubedl-android
-keep class com.yausername.** { *; }
-keep class net.yausername.** { *; }

# Riverpod
-keep class dev.riverpod.** { *; }

# Permission handler
-keep class com.baseflow.permissionhandler.** { *; }

# File picker
-keep class com.mr.flutter.plugin.filepicker.** { *; }

# Connectivity plus
-keep class dev.fluttercommunity.plus.connectivity.** { *; }

# Kotlin
-keep class kotlin.** { *; }
-keep class kotlinx.** { *; }
-dontwarn kotlin.**

# Remove logging in release
-assumenosideeffects class android.util.Log {
  public static int d(...);
  public static int v(...);
  public static int i(...);
}
