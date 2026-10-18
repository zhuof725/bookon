import SwiftUI
import UIKit

/// 整页翻页容器：横向（可从右到左 / 从左到右）与纵向翻页共用。
/// 一页一屏、按页对齐；拖过章末 / 章首回弹时自动切到相邻章。
struct MangaPagedView: UIViewControllerRepresentable {
    let pages: [String]
    let chapter: Int
    let mode: MangaReadingMode
    let request: MangaScrollRequest?
    let background: UIColor
    let foreground: UIColor
    let chromeVisible: Bool
    let onVisible: (_ chapter: Int, _ page: Int, _ count: Int) -> Void
    let onNextChapter: () -> Void
    let onPrevChapter: () -> Void
    let onToggleChrome: () -> Void

    func makeUIViewController(context: Context) -> MangaPagedController {
        let controller = MangaPagedController()
        controller.update(self)
        return controller
    }

    func updateUIViewController(_ controller: MangaPagedController, context: Context) {
        controller.update(self)
    }
}

final class MangaPagedController: UIViewController {
    private var collectionView: UICollectionView!
    private let layout = UICollectionViewFlowLayout()

    private var pages: [String] = []
    private var chapter = -1
    private var mode: MangaReadingMode = .leftToRight
    private var pendingRequest: MangaScrollRequest?
    private var appliedRequestID: UUID?
    private var currentPage = 0
    private var lastReportedPage = -1
    /// 一次拖动只触发一次跨章，避免回弹过程中连续切章。
    private var edgeTriggered = false
    private var appliedItemSize: CGSize = .zero

    private var containerBackground: UIColor = .black
    private var containerForeground: UIColor = .white

    private var onVisible: ((Int, Int, Int) -> Void)?
    private var onNextChapter: (() -> Void)?
    private var onPrevChapter: (() -> Void)?
    private var onToggleChrome: (() -> Void)?
    private var chromeVisible = true

    private var pageSize: CGSize {
        CGSize(width: max(view.bounds.width, 1), height: max(view.bounds.height, 1))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        layout.sectionInset = .zero
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.isPagingEnabled = true
        collectionView.alwaysBounceHorizontal = true
        collectionView.alwaysBounceVertical = false
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.showsVerticalScrollIndicator = false
        collectionView.scrollsToTop = false
        collectionView.delaysContentTouches = false
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.prefetchDataSource = self
        collectionView.register(MangaPageCell.self, forCellWithReuseIdentifier: MangaPageCell.reuseID)
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
        tap.delegate = self
        collectionView.addGestureRecognizer(tap)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let size = pageSize
        guard size.width > 1, size.height > 1 else { return }
        guard size != appliedItemSize else { return }
        appliedItemSize = size
        layout.itemSize = size
        layout.invalidateLayout()
        collectionView.layoutIfNeeded()
        if !pages.isEmpty {
            // 布局变化后按当前页重新对齐（这里已经在布局周期里，不再触发 layoutIfNeeded）。
            let index = MangaPaging.itemIndex(forPage: currentPage, count: pages.count, mode: mode)
            collectionView.setContentOffset(offset(for: IndexPath(item: index, section: 0)), animated: false)
        }
    }

    // MARK: - 配置更新

    func update(_ config: MangaPagedView) {
        loadViewIfNeeded()
        onVisible = config.onVisible
        onNextChapter = config.onNextChapter
        onPrevChapter = config.onPrevChapter
        onToggleChrome = config.onToggleChrome
        chromeVisible = config.chromeVisible

        if containerBackground != config.background {
            containerBackground = config.background
            view.backgroundColor = config.background
            collectionView.backgroundColor = config.background
        }
        containerForeground = config.foreground
        pendingRequest = config.request

        var modeChanged = false
        if config.mode != mode {
            mode = config.mode
            layout.scrollDirection = mode == .vertical ? .vertical : .horizontal
            collectionView.alwaysBounceVertical = mode == .vertical
            collectionView.alwaysBounceHorizontal = mode != .vertical
            collectionView.showsHorizontalScrollIndicator = false
            collectionView.showsVerticalScrollIndicator = false
            modeChanged = true
        }

        let chapterChanged = config.chapter != chapter
        let pagesChanged = config.pages != pages
        guard chapterChanged || pagesChanged || modeChanged else {
            _ = applyPendingRequest()
            return
        }
        let previousPage = currentPage
        pages = config.pages
        chapter = config.chapter
        if chapterChanged || pagesChanged {
            currentPage = chapterChanged ? 0 : min(previousPage, max(pages.count - 1, 0))
            lastReportedPage = -1
        }
        collectionView.reloadData()
        collectionView.layoutIfNeeded()
        if !applyPendingRequest() {
            scroll(to: currentPage, animated: false)
            report(force: true)
        }
    }

    /// 应用会话发来的跳转请求（进度条拖动、目录跳转、切章）。
    /// 目标章还没加载出来时先不消费，等页数据到位后同一请求会再次被应用。
    @discardableResult
    private func applyPendingRequest() -> Bool {
        guard let request = pendingRequest, request.id != appliedRequestID else { return false }
        guard request.chapter < 0 || request.chapter == chapter else { return false }
        guard request.page >= 0, !pages.isEmpty else { return false }
        appliedRequestID = request.id
        scroll(to: request.page, animated: request.animated)
        return true
    }

    private func scroll(to page: Int, animated: Bool) {
        guard !pages.isEmpty else { return }
        let clamped = min(max(page, 0), pages.count - 1)
        currentPage = clamped
        let index = MangaPaging.itemIndex(forPage: clamped, count: pages.count, mode: mode)
        collectionView.layoutIfNeeded()
        let indexPath = IndexPath(item: index, section: 0)
        if animated {
            collectionView.scrollToItem(at: indexPath,
                                        at: mode == .vertical ? .top : .left,
                                        animated: true)
        } else {
            collectionView.setContentOffset(offset(for: indexPath), animated: false)
        }
        report(force: true)
    }

    private func offset(for indexPath: IndexPath) -> CGPoint {
        let size = pageSize
        if mode == .vertical {
            return CGPoint(x: 0, y: CGFloat(indexPath.item) * size.height)
        }
        return CGPoint(x: CGFloat(indexPath.item) * size.width, y: 0)
    }

    // MARK: - 页码 / 章节

    private func pageAtCurrentOffset() -> Int {
        guard !pages.isEmpty else { return 0 }
        let offset = mode == .vertical ? collectionView.contentOffset.y : collectionView.contentOffset.x
        let length = mode == .vertical ? pageSize.height : pageSize.width
        let index = Int((offset / max(length, 1)).rounded())
        return MangaPaging.page(forItem: index, count: pages.count, mode: mode)
    }

    private func settle() {
        guard !pages.isEmpty else { return }
        currentPage = pageAtCurrentOffset()
        report()
    }

    private func report(force: Bool = false) {
        guard chapter >= 0, !pages.isEmpty else { return }
        guard force || currentPage != lastReportedPage else { return }
        lastReportedPage = currentPage
        let chapter = self.chapter, page = currentPage, count = pages.count
        // 不能在同一次 SwiftUI update 里直接回写会话状态，挪到下一拍执行。
        DispatchQueue.main.async { [weak self] in
            self?.onVisible?(chapter, page, count)
        }
    }

    private func advance(_ step: Int) {
        guard !pages.isEmpty else { return }
        let target = currentPage + step
        if target < 0 {
            onPrevChapter?()
            return
        }
        if target >= pages.count {
            onNextChapter?()
            return
        }
        scroll(to: target, animated: true)
    }

    // MARK: - 点按分区

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: collectionView)
        if let indexPath = collectionView.indexPathForItem(at: point),
           let cell = collectionView.cellForItem(at: indexPath) as? MangaPageCell,
           cell.isFailed {
            return // 失败图点按走重试
        }
        if chromeVisible {
            onToggleChrome?()
            return
        }
        let fraction: Double
        if mode == .vertical {
            fraction = Double(point.y / max(pageSize.height, 1))
        } else {
            fraction = Double(point.x / max(pageSize.width, 1))
        }
        let step = MangaPaging.tapStep(fraction: fraction, mode: mode)
        if step == 0 {
            onToggleChrome?()
        } else {
            advance(step)
        }
    }
}

// MARK: - 数据源 / 代理

extension MangaPagedController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout,
                                UICollectionViewDataSourcePrefetching {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        pages.count
    }

    /// 集合视图下标对应的图片地址：从右到左时整章是倒序铺开的。
    private func url(atItem index: Int) -> String? {
        guard !pages.isEmpty else { return nil }
        let page = MangaPaging.page(forItem: index, count: pages.count, mode: mode)
        guard pages.indices.contains(page) else { return nil }
        return pages[page]
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: MangaPageCell.reuseID, for: indexPath) as! MangaPageCell
        let page = MangaPaging.page(forItem: indexPath.item, count: pages.count, mode: mode)
        cell.configure(url: url(atItem: indexPath.item) ?? "", page: page, count: pages.count,
                       foreground: containerForeground) { [weak self] in
            self?.collectionView.collectionViewLayout.invalidateLayout()
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        pageSize
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        (cell as? MangaPageCell)?.startLoadingIfNeeded()
    }

    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths {
            guard let url = url(atItem: indexPath.item) else { continue }
            MangaImageLoader.shared.load(url: url, progress: { _ in }, completion: { _ in })
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        guard let url = url(atItem: indexPath.item) else { return }
        if let cell = collectionView.cellForItem(at: indexPath) as? MangaPageCell, cell.isFailed {
            MangaImageLoader.shared.retry(url: url)
            cell.restartLoading { [weak self] in
                self?.collectionView.collectionViewLayout.invalidateLayout()
            }
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !pages.isEmpty, !edgeTriggered else { return }
        let length = mode == .vertical ? pageSize.height : pageSize.width
        let maxOffset = max(CGFloat(pages.count - 1) * length, 0)
        let offset = mode == .vertical ? scrollView.contentOffset.y : scrollView.contentOffset.x
        if offset < -40 {
            edgeTriggered = true
            let step = MangaPaging.chapterStep(atLeadingEdge: true, mode: mode)
            step > 0 ? onNextChapter?() : onPrevChapter?()
        } else if offset > maxOffset + 40 {
            edgeTriggered = true
            let step = MangaPaging.chapterStep(atLeadingEdge: false, mode: mode)
            step > 0 ? onNextChapter?() : onPrevChapter?()
        }
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        edgeTriggered = false
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { settle() }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        edgeTriggered = false
        settle()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        settle()
    }
}

// MARK: - 手势

extension MangaPagedController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        other === collectionView.panGestureRecognizer
    }
}
