# 图片超分（Core ML）

把 Aidoku 的超分辨率能力接到漫画页与书籍封面上：Core ML 模型在本机把小图放大 2 倍，
比普通插值清晰（补的是分辨率缺口，不是简单拉伸）。

## 能做什么

- **漫画页**：阅读器图片解码后按需放大（`MangaImageLoader`）。
- **封面**：书架/详情/阅读器封面按需放大（`LocalCoverImageLoader`），结果走内存 + 磁盘缓存。
- 模型来自 Aidoku 的公开模型仓库（`https://upscale.aidoku.app/models.json`）：
  - **快速**：waifu2x（`waifu2x_photo_noise0_scale2x.mlmodel`，约 1.1MB，2x + 去噪）
  - **高质量**：Real-ESRGAN（`RealESRGAN_x2plus.mlpackage`，约 34MB，2x）
- `.mlpackage` 在服务端是 zip，下载后用仓库自带的 `ZipReader` 解开；加载走
  `MLModel.compileModel(at:)`，`.mlmodel` / `.mlpackage` 都能在运行时编译。

## 什么时候放大（`UpscaleSettings.shouldUpscale`）

只放大「比显示目标还小」的图——原图本来就够大时放大只是浪费内存和时间：

- `pixelWidth < targetWidth`（显示目标宽度，像素）；
- `pixelWidth ≤ 1300`、`pixelHeight ≤ 2200`、`pixelWidth*pixelHeight ≤ 档位上限`
  （快速 180 万像素、高质量 120 万像素——Real-ESRGAN 慢得多，上限压更低）；
- 长条漫与超大图跳过：2 倍输出的解码体积是 4 倍，一张 800×1200 放大后约 15MB。

不满足就原样返回，不推理。没有安装模型时也直接回退原图。

## 失败处理（别把黑图塞给用户）

- 推理**串行**执行（`UpscaleGate`，封面/漫画各一条队列）：并发推理在内存吃紧时容易失败。
- 任何一块（tile）推理失败 → **整张放弃**，保持原图。
  早期版本在失败时会把输入缓冲当输出继续装配（输入 256²、输出 512²，尺寸对不上，
  读越界得到一片 0），表现就是「封面整张变黑」。
- 兜底：输出若退化成几乎全黑（抽样 4096 点），同样放弃、保持原图。
- 封面缓存目录带版本号（`upscaled-v2`），旧的坏缓存不会再被读到；
  设置页有「清除超分缓存」和「试跑一次」（用 64×64 测试图跑通链路并报耗时/错误）。

## 代码位置

- `Sources/Engine/UpscaleSettings.swift`：开关、档位、尺寸策略（纯 Foundation，可离线回归）。
- `Sources/App/Upscaling/`：
  - `UpscaleModelStore.swift`：模型清单/下载/安装/加载（actor）。
  - `UpscaleMultiArrayModel.swift`、`UpscaleImageModel.swift`、`UpscaleImageProcessing.swift`：
    移植自 Aidoku（GPLv3，文件头保留出处），多数组模型自己切块喂 `MLMultiArray`，
    小图直接整块（≤ blockSize），块间重叠仅在模型配置了 tileOverlap 时启用。
  - `UpscaleEngine.swift`：唯一入口（决定要不要放大 + 跑模型）。
  - `UpscaleImageCache.swift`：放大结果的内存 + 磁盘缓存（封面用）。
- `Sources/App/UpscaleSettingsView.swift`：设置页（我的 → 图片超分）。

## 开关与档位

- 设置 → 我的 → **图片超分**：漫画页超分 / 封面超分两个开关，档位（快速 / 高质量），
  以及模型下载与删除。
- 存储键：`reader.upscale.manga.v1`、`reader.upscale.cover.v1`、`reader.upscale.quality.v1`。

## 许可

- 推理层移植自 Aidoku（GPLv3）：https://github.com/Aidoku/Aidoku —— 本仓库保持开源即符合其条款。
- 模型文件另按各自许可分发（waifu2x / Real-ESRGAN）。
