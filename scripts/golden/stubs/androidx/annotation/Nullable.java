// ⚠️ JVM 桩（golden 专用）：legado 的 icu4j 源码引用 androidx.annotation.Nullable，
// 这里提供最小可编译替代实现（仅注解声明，无任何行为）。
package androidx.annotation;

import java.lang.annotation.Documented;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;

@Documented
@Retention(RetentionPolicy.CLASS)
public @interface Nullable {
}
