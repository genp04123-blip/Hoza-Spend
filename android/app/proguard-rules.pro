# R8 keep rules for the HozaSend release build.
#
# R8 removes every class it cannot see a reference to. It reads bytecode, so
# anything reached by reflection, by name from a manifest, or across the JNI
# boundary is invisible to it and has to be named here.
#
# The Dart half of the app is not affected by any of this: it is AOT-compiled
# into libapp.so long before R8 runs. These rules only concern the Java and
# Kotlin side - the plugins, the embedding, and this app's own platform code.

# --- Flutter embedding ----------------------------------------------------
# The engine loads these over JNI, so nothing in the bytecode refers to them.
# (The Flutter AAR ships consumer rules covering most of this; these are the
# belt to those braces, and cost nothing if they are redundant.)
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# --- This app's platform code ---------------------------------------------
# MainActivity and TransferService are named in AndroidManifest.xml, so AGP
# generates keep rules for them automatically. DocumentFiles is reached only
# from Kotlin, so R8 keeps it by reachability. Named anyway: these classes are
# the far side of every MethodChannel in lib/core/services, and a wrong answer
# here is a release-only crash that no debug build would ever show.
-keep class com.rahozosman.hozasend.** { *; }

# --- flutter_local_notifications ------------------------------------------
# Serialises scheduled notifications through Gson, which resolves the model
# classes reflectively at runtime. Without this, scheduling a notification
# fails only in release, with a TypeToken error that points nowhere useful.
-keep class com.dexterous.** { *; }
-keep class com.dexterous.flutterlocalnotifications.models.** { *; }
-dontwarn com.dexterous.**

# --- Gson -----------------------------------------------------------------
# Gson reads generic type parameters at runtime, and R8 strips the Signature
# attribute that carries them unless told otherwise.
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes InnerClasses
-keepattributes EnclosingMethod
-dontwarn sun.misc.**
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class * extends com.google.gson.reflect.TypeToken

# --- Core library desugaring ----------------------------------------------
# java.time on API levels that never had it. AGP wires the rules in, but the
# backport references JDK internals that are not on the Android bootclasspath.
-dontwarn java.lang.invoke.**
-dontwarn build.IgnoreJava8API
-dontwarn com.google.devtools.build.android.desugar.**

# --- androidx.core / FileProvider -----------------------------------------
# Named in the manifest, so kept automatically; the dontwarn covers the
# optional APIs androidx compiles against but does not require at runtime.
-dontwarn androidx.**

# --- Diagnostics ----------------------------------------------------------
# Keep line numbers so a release stack trace is still readable, but rename the
# source file so it does not leak local paths.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
