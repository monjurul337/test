# ProGuard & R8 rules for Gemini HD Studio

# Mozilla GeckoView 128
-keep class org.mozilla.geckoview.** { *; }
-keep class org.mozilla.gecko.** { *; }
-dontwarn org.mozilla.geckoview.**
-dontwarn org.mozilla.gecko.**

# SnakeYAML & java.beans (SnakeYAML uses java.beans.* from desktop Java SE which does not exist on Android)
-dontwarn java.beans.**
-dontwarn org.yaml.snakeyaml.**
-keep class org.yaml.snakeyaml.** { *; }

# Flutter core & plugins
-keep class io.flutter.** { *; }
-dontwarn io.flutter.**
-dontwarn com.google.errorprone.annotations.**

