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
# MediaPipe loads task runners, calculators, and JNI bridges by reflected class
# name at runtime. Stripping any of these causes a silent crash the moment the
# PoseLandmarker is initialised in release builds.
-keep class com.google.mediapipe.** { *; }
-keep interface com.google.mediapipe.** { *; }
-keepclassmembers class com.google.mediapipe.** { *; }
# Proto classes referenced by framework internals but not shipped in tasks-vision AAR
-dontwarn com.google.mediapipe.**

# Protocol Buffers — MediaPipe model options are deserialised via proto reflection
-keep class com.google.protobuf.** { *; }
-keep interface com.google.protobuf.** { *; }
-keepclassmembers class com.google.protobuf.** { *; }
-dontwarn com.google.protobuf.**

# ── TensorFlow Lite ────────────────────────────────────────────────────────────
# Used by both YOLO (direct) and MediaPipe (internally). JNI delegates resolve
# interpreter and delegate classes by name.
-keep class org.tensorflow.lite.** { *; }
-keep interface org.tensorflow.lite.** { *; }
-keepclassmembers class org.tensorflow.lite.** { *; }
-dontwarn org.tensorflow.lite.**
