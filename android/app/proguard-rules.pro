# Pixora IA — R8/ProGuard keep rules.
#
# R8 runs on release builds (Flutter enables it). The rules below fix a real
# crash and are all additive (they only PRESERVE things), so they cannot make
# the shrink more aggressive.

# ── Generic signatures ───────────────────────────────────────────────────────
# flutter_local_notifications (de)serializes scheduled notifications with Gson.
# Without the generic type signature, Gson's TypeToken loses its parameter and
# the boot receiver crashes on reboot / app update with:
#   java.lang.RuntimeException: Missing type parameter.
#   at FlutterLocalNotificationsPlugin.loadScheduledNotifications
# Keeping Signature (+ annotations/inner-class metadata) fixes it.
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes InnerClasses,EnclosingMethod

# ── flutter_local_notifications + Gson ───────────────────────────────────────
-keep class com.dexterous.** { *; }
-keep class com.google.gson.** { *; }
-keep class com.google.gson.reflect.TypeToken
-keep class * extends com.google.gson.reflect.TypeToken

# Gson-serialized model classes: keep their fields from being stripped/renamed.
-keepclassmembers,allowobfuscation class * {
  @com.google.gson.annotations.SerializedName <fields>;
}
