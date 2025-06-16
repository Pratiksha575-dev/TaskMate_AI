# Keep everything for flutter_local_notifications
-keep class com.dexterous.flutterlocalnotifications.** { *; }

# Keep TypeToken used by notifications (this fixes your crash)
-keep class com.google.gson.reflect.TypeToken

# Keep annotations and signatures
-keepattributes Signature
-keepattributes *Annotation*
-keep class * extends java.lang.annotation.Annotation { *; }
