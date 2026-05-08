# Flutter wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# TFLite
-keep class org.tensorflow.** { *; }
-keep class org.tensorflow.lite.** { *; }

# flutter_midi_pro
-keep class com.miditranslator.** { *; }

# Flutter references these Play Core classes for deferred components (split APKs)
# which this app does not use — suppress R8 missing-class errors
-dontwarn com.google.android.play.core.**
