# Keep all SDL2 classes — native JNI registration depends on class/method names
-keep class org.libsdl.app.** { *; }

# Keep the MainActivity companion (loads SDL2 native lib)
-keep class org.simplec64.frodo_app.MainActivity { *; }

# Keep Apache Commons Compress classes used via reflection
-keep class org.apache.commons.compress.** { *; }
-dontwarn org.apache.commons.compress.**
