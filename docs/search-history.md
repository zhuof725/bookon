# 搜索历史

搜索页提交非空书名或作者后记录到本机 UserDefaults（`bookSearch.history.v1`），即使没有可用书源也保留。输入但未提交的文字不记录；去除首尾空白／换行，大小写不敏感去重，重复搜索移到最前并保留最新拼写，最多 20 条。

搜索页空态展示历史，右上角时钟入口随时打开历史弹窗。点击记录会回填关键词并再次搜索；叉号单条删除；清空需确认，取消不变。不影响书架、正文或阅读进度。界面沿用全局字体和单色主题。

异步搜索通过 requestID 隔离；停止、离开和新搜索使旧请求失效，旧任务结束不能重置新任务的 searching 状态。

## 验证

`reader-interaction.yml` 的 `search-history` suite 仅运行 `SearchHistoryTests` 三项：

1. 未提交／空白不记入、trim、大小写去重、最新优先，终止进程再启动保留，点击生产历史弹窗触发真实回调并持久化。
2. 单条删除后重启、清空取消与确认、清空后重启为空。
3. 生产模型八项检查：空白、规范化去重、20 条上限与顺序、新实例读取、删除与 reload、多实例最新写入、清空存储、脏数据 reload 清洗。

测试使用 UUID 隔离的 UserDefaults suite，无网络、不读写真实用户历史。模型和 Section／Sheet 直接编译生产文件；提交输入控件为 fixture，不声称覆盖完整 SearchView、真实书源请求或异步竞态 UI 自动化。完整正式 App 由 build.yml 编译。截图独立产物 `search-history-screenshots` 仅包含图像和 manifest.json。
