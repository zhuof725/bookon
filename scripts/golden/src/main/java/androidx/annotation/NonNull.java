package androidx.annotation;

import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

/**
 * golden 适配：legado 的 icu4j 源码（原路径 app/src/main/java/io/legado/app/lib/icu4j/）
 * 使用 androidx.annotation.NonNull / Nullable 标注。golden 工程不依赖 Android，
 * 这里提供零依赖的最小等价声明，仅为让同一份源码原样编译通过；注解不影响运行期行为。
 */
@Retention(RetentionPolicy.CLASS)
@Target({ElementType.METHOD, ElementType.PARAMETER, ElementType.FIELD, ElementType.LOCAL_VARIABLE})
public @interface NonNull {
}
