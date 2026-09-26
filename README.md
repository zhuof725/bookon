# BookOn

开源阅读（Legado）风格的 iOS 阅读 App，SwiftUI 编写。

## 构建
- 推送到 `main` 后，GitHub Actions 自动用 macOS 编译出**未签名 IPA**
- 下载：Releases → `latest` → `BookOn.ipa`，自行签名安装

## 路线图
- [x] 阶段 1：最小可运行 App + 云端编译
- [x] 阶段 2：本地 TXT 阅读（UIKit 文件选择器导入、自动分章、滚动阅读、字号/主题、进度记忆）
- [x] 阶段 3：Legado 书源（导入、多源并发搜索、详情、目录、正文、换源）
- [ ] 阶段 4：书架与进度保存
- [ ] 阶段 5：EPUB、朗读、替换规则等
