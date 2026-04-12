# 1. Protect the Flutter Path Provider (Fixes the download crash)
-keep class io.flutter.util.** { *; }
-keep class androidx.core.content.ContextCompat { *; }

# 2. Protect Audio Players & Record (Fixes the mic/audio crash)
-keep class com.audioplayers.** { *; }
-keep class com.llfbandit.record.** { *; }

# 3. Standard Flutter protections
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.view.** { *; }
-keep class java.lang.invoke.MethodHandle { *; }