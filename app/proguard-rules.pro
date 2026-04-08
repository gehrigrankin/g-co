# Keep serialization classes
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.AnnotationsKt

-keepclassmembers class kotlinx.serialization.json.** {
    *** Companion;
}
-keepclasseswithmembers class kotlinx.serialization.json.** {
    kotlinx.serialization.KSerializer serializer(...);
}

-keep,includedescriptorclasses class com.gehrig.g.**$$serializer { *; }
-keepclassmembers class com.gehrig.g.** {
    *** Companion;
}
-keepclasseswithmembers class com.gehrig.g.** {
    kotlinx.serialization.KSerializer serializer(...);
}
