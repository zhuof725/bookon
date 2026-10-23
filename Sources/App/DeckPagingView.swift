import SwiftUI
import UIKit

/// 逐帧跟手的横向卡片轨道。
///
/// 为什么不用纯 SwiftUI：
///  - `scrollTransition` 的 phase 相对整个视口算，卡片叠得越紧相位越小，
///    我们的卡片只隔 0.56 卡宽，相位几乎为 0，看起来就是「没有动画」；
///  - `GeometryReader` + preference 读偏移再回写 `@State` 会触发一次布局循环，
///    拖动时这个回环延迟一帧，加上 LazyHStack 复用，观感就是跳。
///
/// 业内成熟做法（CollectionViewPagingLayout 等）都是 UICollectionView：
/// 滚动时在 layout 里对每个 cell 直接算 transform。这里同样用 UICollectionView，
/// 只是把内容做成 SwiftUI 视图宿主，上层调用方式不变。
struct DeckPagingView<Card: View>: UIViewControllerRepresentable {
    let count: Int
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    /// 相邻卡片的槽位宽度（决定叠压程度）
    let step: CGFloat
    let stageHeight: CGFloat
    /// 是「叠牌」形态还是「弧形走廊」形态
    let style: DeckMotionStyle
    @Binding var index: Int?
    @ViewBuilder var card: (Int) -> Card

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> PagingController {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        // 用点分页：滚动吸附到每个格子中心
        layout.itemSize = CGSize(width: step, height: stageHeight)

        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = .clear
        view.showsHorizontalScrollIndicator = false
        view.decelerationRate = .fast
        // 露出两侧相邻卡片
        view.clipsToBounds = false
        view.dataSource = context.coordinator
        view.delegate = context.coordinator
        view.register(SwiftUIHostCell.self, forCellWithReuseIdentifier: "cell")

        let controller = PagingController(collectionView: view)
        controller.coordinator = context.coordinator
        context.coordinator.collectionView = view
        return controller
    }

    func updateUIViewController(_ controller: PagingController, context: Context) {
        context.coordinator.parent = self
        controller.collectionView.reloadData()
        context.coordinator.applyToVisibleCells()
        // 外部改了 index（比如点圆点跳页）时滚过去
        if let index, context.coordinator.reportedIndex != index {
            context.coordinator.reportedIndex = index
            context.coordinator.scroll(to: index, animated: true)
        }
    }

    // MARK: - 控制器

    /// 自绘容器：负责把 collectionView 的边距调到「首尾也能居中」。
    final class PagingController: UIViewController {
        let collectionView: UICollectionView
        weak var coordinator: Coordinator?

        init(collectionView: UICollectionView) {
            self.collectionView = collectionView
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func viewDidLoad() {
            super.viewDidLoad()
            collectionView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(collectionView)
            NSLayoutConstraint.activate([
                collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                collectionView.topAnchor.constraint(equalTo: view.topAnchor),
                collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            coordinator?.updateInsets(bounds: view.bounds)
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {
        var parent: DeckPagingView
        weak var collectionView: UICollectionView?
        /// 已经回报给 SwiftUI 的下标，避免回环
        var reportedIndex: Int?
        private var lastInsetWidth: CGFloat = -1

        init(_ parent: DeckPagingView) {
            self.parent = parent
            reportedIndex = parent.index
        }

        func numberOfSections(in collectionView: UICollectionView) -> Int { 1 }

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            max(parent.count, 0)
        }

        func collectionView(_ collectionView: UICollectionView,
                            cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath)
            guard let host = cell as? SwiftUIHostCell else { return cell }
            host.width = parent.cardWidth
            host.set(rootView: parent.card(indexPath.item)
                .frame(width: parent.cardWidth, height: parent.cardHeight))
            return cell
        }

        func collectionView(_ collectionView: UICollectionView,
                            layout collectionViewLayout: UICollectionViewLayout,
                            sizeForItemAt indexPath: IndexPath) -> CGSize {
            CGSize(width: parent.step, height: parent.stageHeight)
        }

        /// 首尾留白：让第一张和最后一张也能停在正中
        func updateInsets(bounds: CGRect) {
            guard let collectionView, bounds.width > 0 else { return }
            let inset = max((bounds.width - parent.step) / 2, 0)
            guard abs(inset - lastInsetWidth) > 0.5 else { return }
            lastInsetWidth = inset
            collectionView.contentInset = UIEdgeInsets(top: 0, left: inset, bottom: 0, right: inset)
            collectionView.collectionViewLayout.invalidateLayout()
        }

        // MARK: 逐帧变换

        /// 滚动中每一帧都对可见 cell 重算 transform —— 这是跟手的关键。
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            applyToVisibleCells()
            reportCurrentIndex()
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            snapToNearest(animated: true)
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate { snapToNearest(animated: true) }
        }

        func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            scroll(to: indexPath.item, animated: true)
            reportCurrentIndex(force: indexPath.item)
        }

        func applyToVisibleCells() {
            guard let collectionView else { return }
            let centerX = collectionView.contentOffset.x + collectionView.bounds.width / 2
            for case let cell as SwiftUIHostCell in collectionView.visibleCells {
                guard let path = collectionView.indexPath(for: cell) else { continue }
                // 卡片中心相对轨道中心的偏移，单位「格」：0 = 正中
                let cellCenterX = collectionView.layoutAttributesForItem(at: path)?.center.x ?? cell.center.x
                let progress = (cellCenterX - centerX) / max(parent.step, 1)
                parent.style.apply(to: cell.contentView, progress: progress)
                // 层级：越靠近中心越靠前（用 Int 层级，和 CollectionViewPagingLayout 一致，
                // 避免每帧一个浮点层级导致图层反复插序）
                cell.layer.zPosition = CGFloat(-abs(Int(progress.rounded())))
            }
        }

        private func reportCurrentIndex(force: Int? = nil) {
            if let force {
                reportedIndex = force
                if parent.index != force {
                    DispatchQueue.main.async { [weak self] in self?.parent.index = force }
                }
                return
            }
            guard let collectionView else { return }
            let centerX = collectionView.contentOffset.x + collectionView.bounds.width / 2
            let index = Int((centerX / max(parent.step, 1)).rounded())
            let clamped = max(0, min(parent.count - 1, index))
            guard clamped != reportedIndex else { return }
            reportedIndex = clamped
            DispatchQueue.main.async { [weak self] in self?.parent.index = clamped }
        }

        func scroll(to index: Int, animated: Bool) {
            guard let collectionView, parent.count > 0 else { return }
            let clamped = max(0, min(parent.count - 1, index))
            let x = CGFloat(clamped) * parent.step - collectionView.contentInset.left
            collectionView.setContentOffset(CGPoint(x: x, y: 0), animated: animated)
            if !animated { applyToVisibleCells() }
        }

        /// 停在最近一格
        private func snapToNearest(animated: Bool) {
            guard let collectionView else { return }
            let centerX = collectionView.contentOffset.x + collectionView.bounds.width / 2
            let nearest = Int((centerX / max(parent.step, 1)).rounded())
            scroll(to: nearest, animated: animated)
        }
    }
}

/// 用 UIHostingController 把 SwiftUI 卡片塞进 cell。
final class SwiftUIHostCell: UICollectionViewCell {
    private var host: UIHostingController<AnyView>?
    var width: CGFloat = 0

    func set<Content: View>(rootView: Content) {
        let wrapped = AnyView(rootView)
        if let host {
            host.rootView = wrapped
        } else {
            let controller = UIHostingController(rootView: wrapped)
            controller.view.backgroundColor = .clear
            controller.view.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(controller.view)
            NSLayoutConstraint.activate([
                controller.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                controller.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                controller.view.topAnchor.constraint(equalTo: contentView.topAnchor),
                controller.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
            ])
            host = controller
        }
        // 卡片居中：槽位比卡窄时，卡片会向两侧溢出（这正是叠压的来源）
        contentView.clipsToBounds = false
        clipsToBounds = false
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // 卡片实际宽度可能大于槽位：用 anchorPoint 居中，避免被 cell 裁掉
        if let view = host?.view {
            view.bounds = CGRect(x: 0, y: 0, width: view.bounds.width, height: view.bounds.height)
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        // 变换状态要清干净，否则复用的 cell 会带着上一张的角度
        contentView.transform = .identity
        contentView.alpha = 1
    }
}
