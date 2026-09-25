# Flutter specific
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep Supabase
-keep class com.supabase.** { *; }

# Keep ZEGO
-keep class im.zego.** { *; }

# Keep WebView
-keep class android.webkit.** { *; }

# Keep EncryptedImageProvider
-keep class **.EncryptedImageProvider { *; }

# Keep serialization models
-keep class com.ahlalive.app.** { *; }

# General Flutter engine
-dontwarn io.flutter.embedding.**
-keep class io.flutter.embedding.** { *; }

# Keep all native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep ZEGO underlying avkit2 layer (com.zego.*) - required by official docs
-keep class com.zego.** { *; }
-dontwarn com.zego.**
