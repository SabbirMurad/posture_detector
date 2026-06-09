# ── Suppress compile-time-only annotation processor warnings ──────────────────
-dontwarn javax.annotation.processing.AbstractProcessor
-dontwarn javax.annotation.processing.SupportedAnnotationTypes
-dontwarn javax.lang.model.SourceVersion
-dontwarn javax.lang.model.element.Element
-dontwarn javax.lang.model.element.ElementKind
-dontwarn javax.lang.model.element.Modifier
-dontwarn javax.lang.model.type.TypeMirror
-dontwarn javax.lang.model.type.TypeVisitor
-dontwarn javax.lang.model.util.SimpleTypeVisitor8
-dontwarn org.tensorflow.lite.gpu.GpuDelegateFactory$Options$GpuBackend
-dontwarn org.tensorflow.lite.gpu.GpuDelegateFactory$Options

# ── MediaPipe Tasks ────────────────────────────────────────────────────────────
-keep class com.google.mediapipe.** { *; }
-keep interface com.google.mediapipe.** { *; }
-keep enum com.google.mediapipe.** { *; }
-keepclassmembers class com.google.mediapipe.** { *; }
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod
-dontwarn com.google.mediapipe.**

# Protocol Buffers
-keep class com.google.protobuf.** { *; }
-keep interface com.google.protobuf.** { *; }
-keep enum com.google.protobuf.** { *; }
-keepclassmembers class com.google.protobuf.** { *; }
-dontwarn com.google.protobuf.**

# ── TensorFlow Lite ────────────────────────────────────────────────────────────
-keep class org.tensorflow.** { *; }
-keep interface org.tensorflow.** { *; }
-keep enum org.tensorflow.** { *; }
-keepclassmembers class org.tensorflow.** { *; }
-dontwarn org.tensorflow.**

# ── Guava — used internally by MediaPipe ──────────────────────────────────────
-keep class com.google.common.** { *; }
-dontwarn com.google.common.**

# ── AutoValue — generated option classes used by MediaPipe Tasks ──────────────
-keep class * extends com.google.auto.value.AutoValue { *; }
-dontwarn com.google.auto.**
