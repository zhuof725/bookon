import SwiftUI
import UIKit
import ImageIO

// MARK: - 扁平化条目（阅读器与滚动容器之间的最小数据）

struct MangaFlatItem: Identifiable, Equatable {
    enum Kind: Equatable {
        /// 章节开始标记「阅读 X」。
        case chapterStart(title: String)
        /// 章节结束标记「已读完 X」。
        case chapterEnd(title: String)
        /// 一张图片。index 本章第几张（0 起），count 本章总数。
        case page(chapter: Int, index: Int, count: Int, url: String)
        case loadingPrev
        case retryPrev
        case loadingNext
        case retryNext
        case noMore
    }

    let id: String
    /// 所属章节（哨兵条目取相邻章节号）。
    let chapter: Int
    let kind: Kind

    var pageURL: String? {
        if case .page(_, _, _, let url) = kind { return url }
        return nil
    }
}

struct MangaScrollRequest: Equatable {
    let id: UUID
    let itemID: String
    var animated: Bool = false
}

// MARK: - 图片加载（内存缓存 + 降采样 + 进度）

/// 漫画图片加载器。对应原版 Glide 的用法：按屏幕宽度降采样、只在内存里保留少量图片。
@MainActor
final class MangaImageLoader {
    static let shared = MangaImageLoader()

    private let cache = NSCache<NSString, UIImage>()
    private var aspects: [String: CGSize] = [:]
    private var progressByURL: [String: Double] = [:]
    private var lastFailed: [String: Date] = [:]
    private var tasks: [String: Task<Void, Never>] = [:]
    private var callbacks: [String: [(Double) -> Void]] = [:]
    private var completions: [String: [(UIImage?) -> Void]] = [:]

    /// 屏幕物理宽度；原版 loadManga 的 override(displayMetrics.widthPixels, SIZE_ORIGINAL)。
    private var targetPixelWidth: CGFloat {
        let width = UIScreen.main.bounds.width
        let scale = UIScreen.main.scale
        return min(max(width * scale, 480), 1600)
    }

    private init() {
        cache.totalCostLimit = 96 * 1024 * 1024
        cache.countLimit = 24
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.cache.removeAllObjects() }
        }
    }

    func cachedImage(for url: String) -> UIImage? { cache.object(forKey: url as NSString) }
    /// 图片像素尺寸（宽×高）。已知宽高比后，布局可以先用真实高度，减少加载完成后的位置跳动。
    func aspect(for url: String) -> CGSize? { aspects[url] }
    func progress(for url: String) -> Double? { progressByURL[url] }
    func hasFailed(for url: String) -> Bool { lastFailed[url] != nil }

    /// 开始（或加入）一张图片的加载。progress/completion 可能被调用多次，调用方自行按 URL 过滤。
    func load(url: String, progress: @escaping (Double) -> Void, completion: @escaping (UIImage?) -> Void) {
        if let image = cache.object(forKey: url as NSString) {
            completion(image)
            return
        }
        if tasks[url] != nil {
            callbacks[url, default: []].append(progress)
            completions[url, default: []].append(completion)
            if let p = progressByURL[url] { progress(p) }
            return
        }
        // data: 图片（原版 flowImages 保留 data: 地址）本地解码，不经过 URLSession。
        if url.lowercased().hasPrefix("data:") {
            callbacks[url] = [progress]
            completions[url] = [completion]
            if let data = DataURIDecode.data(url), let image = UIImage(data: data) {
                finish(url: url, result: .success(image))
            } else {
                finish(url: url, result: .failure(URLError(.cannotDecodeContentData)))
            }
            return
        }
        guard let requestURL = URL(string: url) else { completion(nil); return }
        callbacks[url] = [progress]
        completions[url] = [completion]
        tasks[url] = Task { [weak self] in
            let result = await Self.fetch(requestURL: requestURL) { [weak self] fraction in
                Task { @MainActor in
                    guard let self, self.tasks[url] != nil else { return }
                    let previous = self.progressByURL[url] ?? 0
                    guard fraction - previous >= 0.02 || fraction >= 1 else { return }
                    self.progressByURL[url] = fraction
                    for callback in self.callbacks[url] ?? [] { callback(fraction) }
                }
            }
            self?.finish(url: url, result: result)
        }
    }

    /// 用户在失败图上点按重试。
    func retry(url: String) {
        lastFailed[url] = nil
    }

    private func finish(url: String, result: Result<UIImage, Error>) {
        tasks[url] = nil
        progressByURL[url] = nil
        callbacks.removeValue(forKey: url)
        let completions = self.completions.removeValue(forKey: url) ?? []
        switch result {
        case .success(let image):
            let cost = Int(image.size.width * image.scale * image.size.height * image.scale * 4)
            cache.setObject(image, forKey: url as NSString, cost: cost)
            aspects[url] = CGSize(width: image.size.width * image.scale,
                                  height: image.size.height * image.scale)
            lastFailed[url] = nil
            for completion in completions { completion(image) }
        case .failure:
            lastFailed[url] = Date()
            CrashReporter.note("漫画图片失败 \(String(url.prefix(140)))")
            for completion in completions { completion(nil) }
        }
    }

    private nonisolated static func fetch(requestURL: URL, progress: @escaping (Double) -> Void) async -> Result<UIImage, Error> {
        do {
            let (data, response) = try await downloadWithProgress(requestURL: requestURL, progress: progress)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let target = await MainActor.run { MangaImageLoader.shared.targetPixelWidth }
            guard let image = await downsample(data: data, targetPixelWidth: target) else {
                throw URLError(.cannotDecodeContentData)
            }
            return .success(image)
        } catch {
            return .failure(error)
        }
    }

    /// URLSessionDownloadTask 自带 Progress，可以在下载过程中回报百分比（原版显示百分比）。
    private nonisolated static func downloadWithProgress(requestURL: URL,
                                                         progress: @escaping (Double) -> Void) async throws -> (Data, URLResponse) {
        final class TaskBox: @unchecked Sendable {
            var task: URLSessionDownloadTask?
            var observation: NSKeyValueObservation?
        }
        let box = TaskBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = URLSession.shared.downloadTask(with: requestURL) { fileURL, response, error in
                    defer { box.observation = nil }
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let fileURL, let response else {
                        continuation.resume(throwing: URLError(.badServerResponse))
                        return
                    }
                    defer { try? FileManager.default.removeItem(at: fileURL) }
                    do {
                        let data = try Data(contentsOf: fileURL)
                        continuation.resume(returning: (data, response))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
                box.task = task
                var lastReported: Double = -1
                box.observation = task.progress.observe(\.fractionCompleted, options: [.new]) { _, change in
                    guard let value = change.newValue, value.isFinite else { return }
                    guard value - lastReported >= 0.02 || value >= 1 else { return }
                    lastReported = value
                    progress(value)
                }
                task.resume()
            }
        } onCancel: {
            box.task?.cancel()
        }
    }

    /// 按目标宽度降采样（保持宽高比），避免原图整张进内存。
    nonisolated static func downsample(data: Data, targetPixelWidth: CGFloat) async -> UIImage? {
        await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            let width = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? 0
            let height = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? 0
            if width > 0, height > 0, width <= Double(targetPixelWidth) {
                return UIImage(data: data)
            }
            let ratio = width > 0 ? min(1, Double(targetPixelWidth) / width) : 1
            let thumbMax = max(Double(targetPixelWidth), max(width, height) * ratio)
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: thumbMax,
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return UIImage(data: data)
            }
            return UIImage(cgImage: cgImage)
        }.value
    }
}

// MARK: - SwiftUI 包装

struct MangaScrollView: UIViewControllerRepresentable {
    let items: [MangaFlatItem]
    let request: MangaScrollRequest?
    let background: UIColor
    let foreground: UIColor
    /// 面板当前是否显示：显示时点任意位置收起，隐藏时点任意位置（翻页区除外）呼出。
    let chromeVisible: Bool
    let onVisible: (_ chapter: Int, _ page: Int, _ count: Int) -> Void
    let onNearEnd: () -> Void
    let onNearStart: () -> Void
    /// 相邻章加载失败哨兵点按：按章号重试。
    let onRetryNeighbor: (_ chapter: Int) -> Void
    let onToggleChrome: () -> Void

    func makeUIViewController(context: Context) -> MangaScrollController {
        let controller = MangaScrollController()
        controller.update(self)
        return controller
    }

    func updateUIViewController(_ controller: MangaScrollController, context: Context) {
        controller.update(self)
    }
}

// MARK: - 滚动容器（UICollectionView：图片懒加载 + 复用，对应原版 RecyclerView）

final class MangaScrollController: UIViewController {
    private var collectionView: UICollectionView!
    private var items: [MangaFlatItem] = []
    private var itemIndexByID: [String: Int] = [:]
    private var appliedRequestID: UUID?
    private var lastReported: (chapter: Int, page: Int) = (-1, -1)
    private var containerBackground: UIColor = .black
    private var containerForeground: UIColor = .white

    private var onVisible: ((Int, Int, Int) -> Void)?
    private var onNearEnd: (() -> Void)?
    private var onNearStart: (() -> Void)?
    private var onRetryNeighbor: ((Int) -> Void)?
    private var onToggleChrome: (() -> Void)?
    private var chromeVisible = true

    /// 程序化跳转后锁定锚点：目标图片加载导致高度变化时保持目标位置不动。
    private struct ScrollAnchor { let itemID: String; let delta: CGFloat }
    private var lockedAnchor: ScrollAnchor?
    private var lockReleaseWork: DispatchWorkItem?
    private var lastScrollTick = Date.distantPast
    /// 图片加载后的重排合并成一拍，避免在 UIKit 布局周期内重入。
    private var layoutRefreshScheduled = false

    private static let markerHeight: CGFloat = 64
    private static let sentinelHeight: CGFloat = 88
    /// 图片未加载时的估高比例（宽 → 高）。常见条漫 800×1131 ≈ 1.41。
    private static let placeholderAspect: CGFloat = 1.42

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        layout.sectionInset = .zero
        layout.estimatedItemSize = .zero
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.showsVerticalScrollIndicator = false
        collectionView.scrollsToTop = false
        // 不要延迟把触摸事件转给内容视图，点按分区响应更即时。
        collectionView.delaysContentTouches = false
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(MangaPageCell.self, forCellWithReuseIdentifier: MangaPageCell.reuseID)
        collectionView.register(MangaMarkerCell.self, forCellWithReuseIdentifier: MangaMarkerCell.reuseID)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.cancelsTouchesInView = false
        // 与滚动手势并行识别：手指轻微移动时点按不被滚动起手吞掉，面板更容易呼出。
        tap.delegate = self
        collectionView.addGestureRecognizer(tap)
    }

    func update(_ config: MangaScrollView) {
        onVisible = config.onVisible
        onNearEnd = config.onNearEnd
        onNearStart = config.onNearStart
        onRetryNeighbor = config.onRetryNeighbor
        onToggleChrome = config.onToggleChrome
        chromeVisible = config.chromeVisible
        if containerBackground != config.background {
            containerBackground = config.background
            view.backgroundColor = config.background
            collectionView.backgroundColor = config.background
        }
        containerForeground = config.foreground
        apply(items: config.items)
        apply(request: config.request)
    }

    // MARK: 列表更新（保留滚动位置的差量更新）

    private func apply(items newItems: [MangaFlatItem]) {
        let oldIDs = items.map(\.id)
        let newIDs = newItems.map(\.id)
        guard oldIDs != newIDs else {
            items = newItems
            itemIndexByID = Dictionary(uniqueKeysWithValues: newItems.enumerated().map { ($0.element.id, $0.offset) })
            return
        }
        let anchor = lockedAnchor ?? captureAnchor()
        let oldCount = oldIDs.count, newCount = newIDs.count
        var prefix = 0
        while prefix < oldCount, prefix < newCount, oldIDs[prefix] == newIDs[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < oldCount - prefix, suffix < newCount - prefix,
              oldIDs[oldCount - 1 - suffix] == newIDs[newCount - 1 - suffix] { suffix += 1 }
        let removed = Array(prefix..<(oldCount - suffix)).map { IndexPath(item: $0, section: 0) }
        let inserted = Array(prefix..<(newCount - suffix)).map { IndexPath(item: $0, section: 0) }

        items = newItems
        itemIndexByID = Dictionary(uniqueKeysWithValues: newItems.enumerated().map { ($0.element.id, $0.offset) })

        if oldIDs.isEmpty || newIDs.isEmpty {
            collectionView.reloadData()
            collectionView.layoutIfNeeded()
            if let anchor, itemIndexByID[anchor.itemID] != nil {
                reanchor(anchor)
            }
            return
        }
        if removed.isEmpty && inserted.isEmpty {
            // 只有顺序变化，重建即可（不会出现在当前使用方式里）。
            collectionView.reloadData()
            if let anchor { reanchor(anchor) }
            return
        }
        if prefix == 0 && suffix == 0 && !oldIDs.isEmpty && !newIDs.isEmpty {
            collectionView.reloadData()
            collectionView.layoutIfNeeded()
            if let anchor, itemIndexByID[anchor.itemID] != nil {
                reanchor(anchor)
            } else {
                collectionView.setContentOffset(.zero, animated: false)
            }
            return
        }
        collectionView.performBatchUpdates {
            if !removed.isEmpty { collectionView.deleteItems(at: removed) }
            if !inserted.isEmpty { collectionView.insertItems(at: inserted) }
        } completion: { [weak self] _ in
            self?.collectionView.layoutIfNeeded()
            if let anchor { self?.reanchor(anchor) }
        }
    }

    private func apply(request: MangaScrollRequest?) {
        guard let request, request.id != appliedRequestID else { return }
        appliedRequestID = request.id
        guard let index = itemIndexByID[request.itemID] else { return }
        let indexPath = IndexPath(item: index, section: 0)
        collectionView.layoutIfNeeded()
        collectionView.scrollToItem(at: indexPath, at: .top, animated: request.animated)
        lockedAnchor = ScrollAnchor(itemID: request.itemID, delta: 0)
        scheduleLockRelease()
    }

    private func scheduleLockRelease() {
        lockReleaseWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.lockedAnchor = nil
        }
        lockReleaseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }

    /// 图片加载完成、高度变化后调用：调整偏移保持当前可见内容不动。
    /// 统一延后一拍执行：UIKit 可能在 cellForItemAt / 预取 / 布局周期里同步回调，
    /// 当场 layoutIfNeeded 会重入 UICollectionView 的内部更新并触发断言崩溃。
    func imageDidLoad() {
        guard !layoutRefreshScheduled else { return }
        layoutRefreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.layoutRefreshScheduled = false
            self.refreshLayoutAfterImageLoad()
        }
    }

    private func refreshLayoutAfterImageLoad() {
        guard isViewLoaded, collectionView.window != nil else { return }
        let anchor = lockedAnchor ?? captureAnchor()
        collectionView.collectionViewLayout.invalidateLayout()
        collectionView.setNeedsLayout()
        collectionView.layoutIfNeeded()
        if let anchor { reanchor(anchor) }
        reportVisible(force: true)
    }

    private func captureAnchor() -> ScrollAnchor? {
        let offsetY = collectionView.contentOffset.y
        for indexPath in collectionView.indexPathsForVisibleItems.sorted() {
            guard indexPath.item < items.count,
                  let attributes = collectionView.layoutAttributesForItem(at: indexPath) else { continue }
            if attributes.frame.maxY > offsetY + 0.5 {
                return ScrollAnchor(itemID: items[indexPath.item].id, delta: offsetY - attributes.frame.minY)
            }
        }
        return nil
    }

    private func reanchor(_ anchor: ScrollAnchor) {
        guard let index = itemIndexByID[anchor.itemID],
              let attributes = collectionView.layoutAttributesForItem(at: IndexPath(item: index, section: 0)) else { return }
        let maximum = max(collectionView.contentSize.height - collectionView.bounds.height, 0)
        let target = min(max(attributes.frame.minY + anchor.delta, 0), maximum)
        if abs(collectionView.contentOffset.y - target) > 0.5 {
            collectionView.setContentOffset(CGPoint(x: 0, y: target), animated: false)
        }
    }

    // MARK: 点击分区（与原版一致：中央=菜单；左下/右下=上下翻一屏）

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: collectionView)
        if let indexPath = collectionView.indexPathForItem(at: point), indexPath.item < items.count {
            if let cell = collectionView.cellForItem(at: indexPath) as? MangaPageCell, cell.isFailed {
                return // 失败图点按走重试，不触发翻屏/菜单
            }
            switch items[indexPath.item].kind {
            case .retryPrev, .retryNext:
                return // 交给 didSelectItemAt 触发重试
            default:
                break
            }
        }
        // 面板显示时：点任意位置收起。
        if chromeVisible {
            onToggleChrome?()
            return
        }
        // 面板隐藏时：左下 / 右下翻一屏；其余任意位置都呼出面板（不再要求点在正中）。
        let width = max(collectionView.bounds.width, 1)
        let height = max(collectionView.bounds.height, 1)
        let xf = point.x / width, yf = point.y / height
        if yf > 0.66 {
            if xf < 0.33 { scrollPage(-1); return }
            if xf > 0.66 { scrollPage(1); return }
        }
        onToggleChrome?()
    }

    func scrollPage(_ direction: Int) {
        let height = collectionView.bounds.height
        let maximum = max(collectionView.contentSize.height - collectionView.bounds.height, 0)
        let target = min(max(collectionView.contentOffset.y + CGFloat(direction) * height, 0), maximum)
        guard abs(target - collectionView.contentOffset.y) > 1 else { return }
        collectionView.setContentOffset(CGPoint(x: 0, y: target), animated: true)
    }

    // MARK: 可见项回报

    private func reportVisible(force: Bool = false) {
        var chapter = -1, page = 0, count = 0
        for indexPath in collectionView.indexPathsForVisibleItems.sorted() where indexPath.item < items.count {
            let item = items[indexPath.item]
            switch item.kind {
            case .page(let c, let index, let total, _):
                chapter = c; page = index; count = total
            case .chapterStart, .chapterEnd:
                if chapter == -1 { chapter = item.chapter; page = 0 }
            default:
                break
            }
            if chapter != -1 { break }
        }
        guard chapter != -1 else { return }
        if !force, chapter == lastReported.chapter, page == lastReported.page { return }
        lastReported = (chapter, page)
        onVisible?(chapter, page, count)
    }

    private func checkEdges() {
        let offsetY = collectionView.contentOffset.y
        let height = collectionView.bounds.height
        let remaining = collectionView.contentSize.height - (offsetY + height)
        if remaining < height * 1.5 { onNearEnd?() }
        if offsetY < height * 0.9 { onNearStart?() }
    }
}

// MARK: - 数据源 / 代理

extension MangaScrollController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let item = items[indexPath.item]
        switch item.kind {
        case .page(_, let index, let count, let url):
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: MangaPageCell.reuseID, for: indexPath) as! MangaPageCell
            cell.configure(url: url, page: index, count: count, foreground: containerForeground) { [weak self] in
                self?.imageDidLoad()
            }
            return cell
        case .chapterStart(let title):
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: MangaMarkerCell.reuseID, for: indexPath) as! MangaMarkerCell
            cell.configure(text: MangaBook.chapterStartTitle(title), foreground: containerForeground)
            return cell
        case .chapterEnd(let title):
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: MangaMarkerCell.reuseID, for: indexPath) as! MangaMarkerCell
            cell.configure(text: MangaBook.chapterEndTitle(title), foreground: containerForeground)
            return cell
        case .loadingPrev:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: MangaMarkerCell.reuseID, for: indexPath) as! MangaMarkerCell
            cell.configure(text: "正在加载上一章…", foreground: containerForeground)
            return cell
        case .retryPrev:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: MangaMarkerCell.reuseID, for: indexPath) as! MangaMarkerCell
            cell.configure(text: "上一章加载失败，点按重试", foreground: containerForeground)
            return cell
        case .loadingNext:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: MangaMarkerCell.reuseID, for: indexPath) as! MangaMarkerCell
            cell.configure(text: "正在加载下一章…", foreground: containerForeground)
            return cell
        case .retryNext:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: MangaMarkerCell.reuseID, for: indexPath) as! MangaMarkerCell
            cell.configure(text: "下一章加载失败，点按重试", foreground: containerForeground)
            return cell
        case .noMore:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: MangaMarkerCell.reuseID, for: indexPath) as! MangaMarkerCell
            cell.configure(text: "暂无章节了！", foreground: containerForeground)
            return cell
        }
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let width = max(collectionView.bounds.width, 1)
        switch items[indexPath.item].kind {
        case .page(_, _, _, let url):
            if let aspect = MangaImageLoader.shared.aspect(for: url), aspect.width > 0 {
                return CGSize(width: width, height: ceil(width * aspect.height / aspect.width))
            }
            // 未加载：按常见条漫比例占位。用一屏高度占位时，图片按比例居中会在上下留下
            // 大片空白（浅色主题下就是白带）；用 1.42 估高，误差只有几个点。
            return CGSize(width: width, height: max(ceil(width * Self.placeholderAspect), 320))
        case .chapterStart, .chapterEnd:
            return CGSize(width: width, height: Self.markerHeight)
        default:
            return CGSize(width: width, height: Self.sentinelHeight)
        }
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        if let cell = cell as? MangaPageCell {
            cell.startLoadingIfNeeded()
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        guard indexPath.item < items.count else { return }
        switch items[indexPath.item].kind {
        case .page(_, _, _, let url):
            if let cell = collectionView.cellForItem(at: indexPath) as? MangaPageCell, cell.isFailed {
                MangaImageLoader.shared.retry(url: url)
                cell.restartLoading { [weak self] in self?.imageDidLoad() }
            }
        case .retryNext, .retryPrev:
            onRetryNeighbor?(items[indexPath.item].chapter)
        default:
            break
        }
    }

    func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
        guard indexPath.item < items.count else { return false }
        switch items[indexPath.item].kind {
        case .retryPrev, .retryNext: return true
        case .page(_, _, _, _): return true
        default: return false
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let now = Date()
        guard now.timeIntervalSince(lastScrollTick) > 0.2 else { return }
        lastScrollTick = now
        reportVisible()
        checkEdges()
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        lockReleaseWork?.cancel()
        lockedAnchor = nil
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        reportVisible(force: true)
        checkEdges()
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        reportVisible(force: true)
        checkEdges()
    }
}

// MARK: - 点按手势

extension MangaScrollController: UIGestureRecognizerDelegate {
    /// 与滚动并行识别：手指轻微移动（未达到滚动阈值）时点按仍然有效，面板呼出更灵敏；
    /// 真正开始滚动时 tap 会因为位移超过容差而失败，不会误触。
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        other === collectionView.panGestureRecognizer
    }
}

// MARK: - 单元格

final class MangaMarkerCell: UICollectionViewCell {
    static let reuseID = "MangaMarkerCell"
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.numberOfLines = 2
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -24),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(text: String, foreground: UIColor) {
        label.text = text
        label.textColor = foreground.withAlphaComponent(0.6)
    }
}

final class MangaPageCell: UICollectionViewCell {
    static let reuseID = "MangaPageCell"

    private let imageView = UIImageView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let progressLabel = UILabel()
    private let failLabel = UILabel()

    private(set) var currentURL: String = ""
    private(set) var isFailed = false
    private var onLoaded: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .clear

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        contentView.addSubview(imageView)

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = true
        contentView.addSubview(spinner)

        progressLabel.translatesAutoresizingMaskIntoConstraints = false
        progressLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        progressLabel.textAlignment = .center
        contentView.addSubview(progressLabel)

        failLabel.translatesAutoresizingMaskIntoConstraints = false
        failLabel.font = .systemFont(ofSize: 14, weight: .medium)
        failLabel.textAlignment = .center
        failLabel.text = "图片加载失败，点按重试"
        failLabel.isHidden = true
        contentView.addSubview(failLabel)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            spinner.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            progressLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            progressLabel.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 8),
            failLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            failLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepareForReuse() {
        super.prepareForReuse()
        currentURL = ""
        isFailed = false
        onLoaded = nil
        imageView.image = nil
        spinner.stopAnimating()
        progressLabel.text = nil
        failLabel.isHidden = true
    }

    func configure(url: String, page: Int, count: Int, foreground: UIColor, onLoad: @escaping () -> Void) {
        currentURL = url
        onLoaded = onLoad
        isFailed = false
        imageView.image = nil
        failLabel.isHidden = true
        spinner.color = foreground.withAlphaComponent(0.8)
        progressLabel.textColor = foreground.withAlphaComponent(0.7)
        failLabel.textColor = foreground.withAlphaComponent(0.7)
        if let image = MangaImageLoader.shared.cachedImage(for: url) {
            apply(image, notify: false)
            return
        }
        if MangaImageLoader.shared.hasFailed(for: url) {
            showFailure()
            return
        }
        // 只展示加载态；真正的下载在 willDisplay 时开始，保证完成回调里 onLoaded 已经就位。
        // 否则图片完成时没人通知外层重排，单元格会一直停在一屏高的占位尺寸（图片上下留白）。
        spinner.startAnimating()
        progressLabel.text = nil
    }

    /// willDisplay 时调用：开始（或加入）当前 URL 的图片加载。
    func startLoadingIfNeeded() {
        guard imageView.image == nil, !isFailed, !currentURL.isEmpty else { return }
        loadImage(url: currentURL)
    }

    func restartLoading(_ onLoad: @escaping () -> Void) {
        onLoaded = onLoad
        isFailed = false
        failLabel.isHidden = true
        imageView.image = nil
        spinner.startAnimating()
        progressLabel.text = nil
        loadImage(url: currentURL)
    }

    private func loadImage(url: String) {
        guard !url.isEmpty else { return }
        spinner.startAnimating()
        MangaImageLoader.shared.load(url: url, progress: { [weak self] fraction in
            guard let self, self.currentURL == url, !self.isFailed else { return }
            self.progressLabel.text = "\(Int((fraction * 100).rounded()))%"
        }, completion: { [weak self] image in
            guard let self, self.currentURL == url else { return }
            if let image {
                self.apply(image)
            } else {
                self.showFailure()
            }
        })
    }

    private func apply(_ image: UIImage, notify: Bool = true) {
        spinner.stopAnimating()
        progressLabel.text = nil
        failLabel.isHidden = true
        isFailed = false
        imageView.image = image
        // 缓存命中时（cellForItemAt 里同步走到这里）不能回调 onLoaded：
        // 那会在 UIKit 正在更新可见单元格时重入 layoutIfNeeded，触发内部断言崩溃。
        // 缓存命中说明宽高比已知，布局本来就已经正确，不需要再重排。
        if notify { onLoaded?() }
    }

    private func showFailure() {
        spinner.stopAnimating()
        progressLabel.text = nil
        imageView.image = nil
        failLabel.isHidden = false
        isFailed = true
    }
}
