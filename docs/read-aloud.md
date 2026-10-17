# 听书（朗读）

对照原版 Legado（`legado-E-main` 中 `ReadAloud.kt`、`BaseReadAloudService.kt`、
`TTSReadAloudService.kt`、`HttpReadAloudService.kt`、`HttpTTS.kt`、
`SpeakEngineDialog.kt`、`ReadAloudDialog.kt`）移植的听书功能。

## 用法

- 阅读页底部菜单 **听书** → 打开朗读面板；面板打开时若未在朗读，立即从
  当前页位置开始读，章末自动进入下一章。
- 面板控件（对齐原版）：上一章 / 上一句 / 播放暂停 / 停止 / 下一句 / 下一章、
  语速 −/＋（显示 (v+5)/10 倍）、定时（0/5/10/15/30/45/60/90/180 分钟）、
  朗读引擎入口。
- 进度跟随：朗读到哪段，翻页模式就翻到含该段的页，滚动模式滚动到该段
  （按一屏左右节流），同时保存阅读进度，退出后能从朗读处续读。
- 后台播放：申请音频会话 .playback + .spokenAudio，锁定屏幕继续读；
  锁屏控制中心显示书名和章节，播放/暂停/上/下一段都能遥控。
- 来电/音频中断自动暂停，可恢复时自动继续；拔掉耳机自动暂停。

## 朗读引擎

- **系统语音**：AVSpeechSynthesizer，zh-CN 声部，语速默认值 = 1.0（原版默认）。
- **HTTP 引擎**（对齐原版 HttpTTS）：名称、URL、Content-Type 正则校验、
  并发率（N/M 或纯毫秒数）、请求头、登录地址、登录界面、登录检查JS、jsLib、CookieJar。
- URL 规则同书源 URL：`{{speakText}}`/`{{speakSpeed}}`、任意 `{{JS 表达式}}`、
  `@js:` 调用 jsLib 里的函数、`,{...}` 选项（method/body/headers）。
- 带 `loginUrl`/`loginUi` 的引擎可以点「登录」，复用书源登录页（信息按
  `httpTts:<id>` 键存在登录存储里）；引擎 header 与登录头合并后发请求。
- 引擎管理入口：听书面板 → 朗读引擎、我的 → 书库管理 → 朗读引擎管理、
  阅读设置 → 朗读引擎管理。支持新建、文本/文件/URL/剪贴板导入、
  导入默认（原版自带的那三条）、导出全部到剪贴板、清空音频缓存。

## 合成与播放

- 逐段请求 → 校验 Content-Type（text/json 视为服务端报错，正文向用户提示）
  → 按 `md5(章名)_md5(引擎URL|语速|文本)` 缓存到 Caches/httpTTS（上限 128MB
  循环淘汰，同键不重下，改语速/引擎换新键）。
- 在后台任务里预下载后面 10 段；有并发率的引擎按平均请求间隔限速。
- 连续 5 次下载失败自动暂停并提示；单次失败跳过本段继续下一段。

## 与原版的行为差异

- 原版 ExoPlayer 边下边播（streamReadAloudAudio=true 时），此处统一下载后播，
  无开关；效果差异仅在单段首响延迟，队列与缓存行为一致。
- loginCheckJs 已支持：result.body().bytes()、result.newBuilder()…build()、java.post().bodyAsBytes()、
  Packages.java.util.HashMap/Arrays.copyOfRange、okio.Buffer、okhttp3.MediaType/ResponseBody.create 的最小子集；
  请求失败时（原版 getErrResponse）不再调用脚本。阿里云、Next 这类带 loginCheck 的引擎，
  登录信息正确时可用，自动恢复/自动换接口一次走不通。
- 原版界面有「跟随系统语速」与「按页朗读」开关；这里去掉，语速直接由
  面板/设置管理，单元始终是段落。
- 原版唤起（Save Defaults）分「本书/通用」，这里只有全局一项。
- 定时行为一致（只计播放时长，暂停时暂停倒计，走完自动停止）。

## 文件

| 文件 | 说明 |
| --- | --- |
| Sources/Engine/HttpTTS.swift | 引擎模型、列表存储、语速/定时配置、`speakText` 判定 |
| Sources/Engine/HttpTTSDefaults.swift | 原版 httpTTS.json 逐字拷贝 |
| Sources/Engine/AloudAudio.swift | 音频抓取 + 错误分类 + 128MB 缓存 |
| Sources/App/ReaderAloud.swift | ReaderAloudController：全播放状态机 |
| Sources/App/ReaderAloudPanel.swift | 听书面板 + 引擎管理 + 导入导出 |
| Sources/App/HttpTTSEditView.swift | 引擎编辑表单 |
| Tools/SourceTest/HttpTTSRegression.swift | 离线回归（含回环服务器） |
| docs/read-aloud.md | 本文 |
