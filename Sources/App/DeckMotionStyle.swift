import UIKit

/// 卡片的两种滑动形态。
///
/// 两个模板的区别必须一眼看出来：
///  - `.stack`（卡片堆叠）：像手里捏着一叠牌。中间那张正对屏幕，
///    两侧依次转开、缩小、上浮、变暗，**整叠像被手指拨开**；
///  - `.arc`（弧形走廊）：卡片贴在一条圆弧上排开，按各自角度倾斜，
///    中间最大、向两侧沿弧线下沉，滑起来像沿圆形轨道转。
///
/// 数值都参照 CollectionViewPagingLayout 的 stack 实现（Apple 生态里这类效果的事实标准）：
/// 缩放用 1 - progress·factor，转角用 popAngle / stackRotateAngel，
/// 透明度分「前侧」和「后侧」两段，比单纯线性更自然。
enum DeckMotionStyle {
    case stack
    case arc

    /// 把一个 cell 改成该形态。
    /// - Parameter progress: 卡片中心相对轨道中心的偏移，单位「格」。
    ///   0 = 正中，±1 = 相邻一格。负数是左侧，正数是右侧。
    func apply(to view: UIView, progress: CGFloat) {
        switch self {
        case .stack:
            applyStack(to: view, progress: progress)
        case .arc:
            applyArc(to: view, progress: progress)
        }
    }

    // MARK: 卡片堆叠

    private func applyStack(to view: UIView, progress: CGFloat) {
        // 只看左右各 3 格，再远的交给透明度淡出
        let clamped = max(-3, min(3, progress))
        let depth = abs(clamped)

        // 1. 缩放：正中 1.0，相邻 0.90，再往外 0.86 封底
        var scale = 1 - depth * 0.10
        scale = max(scale, 0.86)

        // 2. 转角：两侧向外翻。用饱和曲线，第 3 格也不会侧成一条线。
        let angle: CGFloat = {
            let sign: CGFloat = clamped < 0 ? -1 : 1
            return sign * 52 * tanh(depth * 0.95) * .pi / 180
        }()

        // 3. 位移：连同缩放补偿一起做，让「上沿对齐」而不是「中心对齐」
        let w = view.bounds.width
        let h = view.bounds.height
        // 缩放会让卡片四周收缩，这里把收缩量补回去，卡片看起来是「往后缩」不是「变小飘走」
        let scaleFixX = (scale - 1) * w / 2
        let scaleFixY = (scale - 1) * h / 2
        // 两侧轻微上浮，形成弧顶
        let liftY = -min(depth, 2) * 5
        let tx = scaleFixX
        let ty = scaleFixY + liftY

        var transform = CGAffineTransform(translationX: tx, y: ty)
        transform = transform.scaledBy(x: scale, y: scale)
        // 绕竖轴 3D 翻转（m34 透视）
        var flip = CATransform3DMakeAffineTransform(transform)
        flip.m34 = -1.0 / 900
        flip = CATransform3DRotate(flip, angle, 0, 1, 0)
        view.layer.transform = flip

        // 4. 透明度：后面的卡压暗，最外侧淡出
        var alpha: CGFloat = 1 - depth * 0.17
        if depth > 2 { alpha *= max(0, 1 - (depth - 2) * 0.8) }
        view.alpha = max(0, alpha)

        // 5. 阴影：越靠后越淡，强化层次
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = Float(0.18 * max(0, 1 - depth * 0.35))
        view.layer.shadowRadius = 6
        view.layer.shadowOffset = CGSize(width: 0, height: 3)
    }

    // MARK: 弧形走廊

    private func applyArc(to view: UIView, progress: CGFloat) {
        let clamped = max(-3.4, min(3.4, progress))
        let depth = abs(clamped)

        // 每格 12°，贴在半径 R 的圆上（R 由「一格 68pt 对应 12°」定出来）
        let stepPoints: CGFloat = 68
        let radius = stepPoints / (12 * .pi / 180)
        let theta = clamped * 12 * .pi / 180

        // 卡片沿圆弧的真实位置与「线性排布」的差值：补上才不会飘出圆
        let arcX = radius * sin(theta) - clamped * stepPoints
        let arcY = radius * (1 - cos(theta))

        // 弧形走廊的卡片保持「立着」，只沿切线倾斜 + 轻微缩放
        let scale = 1 - min(depth, 3) * 0.045
        let w = view.bounds.width
        let h = view.bounds.height
        let scaleFixX = (scale - 1) * w / 2
        let scaleFixY = (scale - 1) * h / 2

        var transform = CGAffineTransform(translationX: arcX + scaleFixX, y: arcY + scaleFixY)
        transform = transform.rotated(by: theta)
        transform = transform.scaledBy(x: scale, y: scale)
        view.layer.transform = CATransform3DMakeAffineTransform(transform)

        view.alpha = max(0, 1 - depth * 0.13)
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = Float(0.16 * max(0, 1 - depth * 0.3))
        view.layer.shadowRadius = 6
        view.layer.shadowOffset = CGSize(width: 0, height: 3)
    }
}
