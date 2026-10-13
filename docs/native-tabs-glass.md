# iOS 26 原生底栏与毛玻璃修复

- iOS26+主界面使用真正SwiftUI TabView/系统UITabBar，链接iOS26 SDK，不盖自绘胶囊或toolbar背景。iOS16–18保持原LibraryDock。
- 保留三Tab切换与自定义SF Symbol/图片图标，原生标签布局由系统决定；旧版仅图标/仅文字偏好保留但不伪称可以任意控制系统26布局。
- NavigationStack位于Tab容器外，push替换根界面，阅读仍隐藏tabBar。新原生导航测试验证push/返回。
- 毛玻璃失效根因：ultraThinMaterial之上叠加max(surfaceOpacity,72–100%可读性遮罩)，近似实色遮住blur。现在原生材质之上仅0…18%主题底色；透明度=1-surfaceOpacity，降低透明度仍实色。照片画布scrim未取消；没有宣称任意背景/自定颜色都达到固定对比比率。
- 系统原生底栏的Liquid Glass由系统控制，不接受应用卡片的光晕/透明度参数，设置有明确说明。卡片毛玻璃不是对原生底栏的重画。

## 验证
native-tabs-glass工作流强制Xcode26和iOS26模拟器。NativeTabsGlassTests检查真实tabBars、三Tab切换、图标修改后选择不变、push隐藏返回恢复。
真实屏幕截图在同一细格双色背景比较透明/毛玻璃/实色，检查高频边缘被模糊但低频颜色仍保留；不是ImageRenderer图片非空断言。
结果须读取CI日志后才能宣称通过。离线fixture不等于用户真机与全部书源端到端。
