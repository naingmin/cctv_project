# ProGuard/R8 rules for release builds.
#
# Flutter's own engine rules are contributed by the Gradle plugin, so this file
# only needs app-specific keeps. R8 runs with `proguard-android-optimize.txt`,
# which already applies the standard shrinking optimizations.

# --- Flutter embedding ---
# The engine reflectively instantiates these; R8 cannot see the references.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# --- App-specific keeps ---
# Keep the app's own classes and Riverpod/GoRouter related code.
# The app package and all its classes must be preserved.
-keep class com.cctvmanager.app.** { *; }

# Riverpod state management
-keep class riverpod.** { *; }
-keep class **Notifier { *; }
-keep class **StateNotifier { *; }

# GoRouter routing
-keep class go_router.** { *; }

# --- Deferred components (Play Feature Delivery) ---
# FlutterPlayStoreSplitApplication extends a Play Core class that ships with the
# Play Core library, which this app does not depend on. It is only ever
# reached when deferred components are enabled; we ship a single APK, so the
# reference is dead. -dontwarn rather than -keep because there is no code to
# keep - AGP generated this rule itself.
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.**

# --- Kotlin coroutines ---
-dontwarn kotlinx.coroutines.**

# --- Keep line numbers for readable crash reports ---
# Crashlytics/symbolicated stack traces need this; the file name mapping is
# stripped by the default optimize file, which is what we want.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile