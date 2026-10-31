import SwiftUI
import UIKit

/// 翻页动画类型（设置里选择）。
enum PageTurnStyle: Int, CaseIterable {
    case slide = 0   // UIPageViewController.TransitionStyle.scroll
    case curl = 1    // UIPageViewController.TransitionStyle.pageCurl

    var title: String {
        switch self {
        case .slide: return "滑动"
        case .curl: return "卷页"
        }
    }
}

/// 一页内容。放进 UIHostingController，由 UIPageViewController 负责翻页。
struct PageContentView: View {
    let page: BookPage
    let fontSize: Double
    let lineSpacing: Double
    let fg: Color
    let bg: Color
    var backgroundImage: UIImage? = nil
    var commentCardScale: CGFloat = 1
    var showCommentEntries: Bool = true
    let title: String
    let pageNumber: Int
    let pageCount: Int
    let onTapComment: (String?) -> Void
    /// 长按选词菜单动作；提为属性以免每次刷新都重建，导致选择状态丢失。
    var selection: ReaderTextSelectionActions? = nil
    /// 图片长按菜单；nil 时保持只响应点击（离线测试与预览）。
    var onCopyImage: ((String) -> Void)? = nil
    var onSaveImage: ((String) -> Void)? = nil
    var safeInsets = EdgeInsets()
    var paragraphSpacing: Double = 8
    var leftMargin: Double = 20
    var rightMargin: Double = 20
    var topMargin: Double = 16
    var bottomMargin: Double = 10
    var volumeTitle: String? = nil
    var showsChapterTitle = false
    /// 章节标题的 CSS 样式。
    var titleStyle: ChapterTitleStyle = .empty
    var aloudHighlight: AloudHighlightModel? = nil
    var aloudChapter: Int? = nil

    private var effectiveLineSpacing: CGFloat {
        CGFloat(lineSpacing) + CGFloat(page.justifiedGap ?? 0)
    }

    private func paragraphLeadingGap(at index: Int) -> CGFloat {
        guard index > 0 else { return 0 }
        if case .paragraph = page.blocks[index - 1], case .paragraph = page.blocks[index] {
            return ReaderTextLayout.paragraphGap(lineSpacing: effectiveLineSpacing, paragraphSpacing: CGFloat(paragraphSpacing))
        }
        return CGFloat(max(paragraphSpacing, 0))
    }

    private func renderedBlockHeight(at index: Int) -> CGFloat? {
        guard page.blockHeights.indices.contains(index), page.blockLineCounts.indices.contains(index) else { return nil }
        return CGFloat(page.blockHeights[index])
            + CGFloat(max(page.blockLineCounts[index] - 1, 0)) * CGFloat(page.justifiedGap ?? 0)
    }

    private var measuredTextHeight: CGFloat? {
        guard !page.blocks.isEmpty, page.blockHeights.count == page.blocks.count,
              page.blocks.allSatisfy({ if case .paragraph = $0 { return true }; return false }) else { return nil }
        let naturalGap = ReaderTextLayout.paragraphGap(lineSpacing: CGFloat(lineSpacing),
                                                       paragraphSpacing: CGFloat(paragraphSpacing))
        let rows = page.blockLineCounts.reduce(0, +)
        let extra = CGFloat(page.justifiedGap ?? 0) * CGFloat(max(rows - 1, 0))
        return CGFloat(page.blockHeights.reduce(0, +))
            + CGFloat(max(page.blocks.count - 1, 0)) * naturalGap + extra
    }

    private func bodyRegionHeight(in size: CGSize) -> CGFloat {
        let textWidth = max(size.width - CGFloat(leftMargin + rightMargin), 1)
        let header: CGFloat = showsChapterTitle && pageNumber == 1 && !title.isEmpty
            ? ChapterTitleLayout.height(title: title, fontSize: CGFloat(fontSize), width: textWidth,
                                        style: titleStyle)
                + ChapterTitleLayout.bottomSpacing(fontSize: CGFloat(fontSize), style: titleStyle)
                + CGFloat(paragraphSpacing)
            : 0
        return max(size.height - safeInsets.top - safeInsets.bottom
            - CGFloat(topMargin + bottomMargin) - 24 - header, 0)
    }

    var body: some View {
        ZStack(alignment: .top) {
            bg.ignoresSafeArea()
            if let backgroundImage {
                GeometryReader { geometry in
                    Image(uiImage: backgroundImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                }
                .ignoresSafeArea()
                .accessibilityHidden(true)
            }
            GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 0) {
                if let volumeTitle {
                    Spacer(minLength: 0)
                    VolumeTitleView(title: volumeTitle, foreground: fg)
                    Spacer(minLength: 8)
                } else {
                if showsChapterTitle && pageNumber == 1 && !title.isEmpty {
                    ChapterTitleView(title: title, fontSize: CGFloat(fontSize), color: UIColor(fg),
                                     style: titleStyle)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, ChapterTitleLayout.bottomSpacing(fontSize: CGFloat(fontSize),
                                                                          style: titleStyle) + CGFloat(paragraphSpacing))
                }
                VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(page.blocks.enumerated()), id: \.offset) { blockIndex, block in
                    switch block {
                    case .paragraph(let t, let count, let url):
                        let continuation = page.continuationIndices.contains(blockIndex)
                        InlineCommentParagraph(text: page.displayParagraphs[blockIndex] ?? t, count: count,
                                                fontSize: fontSize,
                                                lineSpacing: effectiveLineSpacing,
                                                color: UIColor(fg),
                                                continuation: continuation,
                                                fullJustify: page.fullJustify,
                                                zhLayout: page.zhLayout,
                                                paragraphEnd: page.blockLineCounts.count == page.blocks.count
                                                    ? page.paragraphEndIndices.contains(blockIndex) : true,
                                                selection: selection,
                                                highlightColor: ReaderAloudHighlightStyle.color(forBackground: UIColor(bg)),
                                                aloudHighlight: aloudHighlight,
                                                aloudChapter: aloudChapter,
                                                aloudPage: pageNumber - 1,
                                                aloudBlock: blockIndex,
                                                onTap: { onTapComment(url) })
                            .frame(maxWidth: .infinity, alignment: .leading)
                            // Use the exact measured row-box height. SwiftUI must
                            // not add UITextView's trailing line-fragment spacing.
                            .frame(height: renderedBlockHeight(at: blockIndex), alignment: .topLeading)
                            .padding(.top, paragraphLeadingGap(at: blockIndex))
                    case .hotComment(let label, let t, let click):
                        HStack(spacing: 10) {
                            Text(label).appFont(.system(size: max(fontSize - 5, 11), weight: .bold)).foregroundStyle(.white)
                                .padding(.horizontal, 10).padding(.vertical, 3)
                                .background(Capsule().fill(Color(red: 1, green: 0.27, blue: 0.27)))
                            Text(t).appFont(.system(size: max(fontSize - 3, 12))).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 22).fill(fg.opacity(0.07)))
                        .onTapGesture { onTapComment(click) }
                        .padding(.top, paragraphLeadingGap(at: blockIndex))
                    case .chapterComments(let t, let count, let items, let click):
                        if items.isEmpty,
                           ContentBlocks.isBareDiscussionEntry(title: t, count: count),
                           !showCommentEntries {
                            EmptyView()
                        } else {
                            ChapterCommentsCard(title: t, count: count, items: items,
                                                fontSize: fontSize, scale: commentCardScale,
                                                foreground: fg, background: bg,
                                                onTap: { onTapComment(click) })
                                .frame(height: renderedBlockHeight(at: blockIndex), alignment: .topLeading)
                                .padding(.top, paragraphLeadingGap(at: blockIndex))
                        }
                    case .image(let src, let click, _):
                        ContentImageView(src: src)
                            .onTapGesture { onTapComment(click) }
                            .contextMenu {
                                if let onCopyImage { Button { onCopyImage(src) } label: { Label("拷贝图像", systemImage: "doc.on.doc") } }
                                if let onSaveImage { Button { onSaveImage(src) } label: { Label("保存到相机胶卷", systemImage: "square.and.arrow.down") } }
                            }
                            .padding(.top, paragraphLeadingGap(at: blockIndex))
                    case .inlineBubble:
                        EmptyView()
                    }
                }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(height: measuredTextHeight, alignment: .topLeading)
                // Top origin never moves. Near-full pages reach the bottom
                // only through the paginator's small inter-row distribution.
                .frame(height: bodyRegionHeight(in: geometry.size), alignment: .topLeading)
                }
            }
            .foregroundStyle(fg)
            .padding(.leading, CGFloat(leftMargin))
            .padding(.trailing, CGFloat(rightMargin))
            .padding(.top, safeInsets.top + CGFloat(topMargin))
            .padding(.bottom, safeInsets.bottom + CGFloat(bottomMargin) + 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .overlay(alignment: .bottom) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).lineLimit(1).accessibilityIdentifier("reader-footer-title")
                    Spacer()
                    Text("\(pageNumber)/\(pageCount)").monospacedDigit().accessibilityIdentifier("reader-footer-page")
                }
                .appFont(.system(size: 11))
                .foregroundStyle(fg.opacity(0.45))
                .frame(maxWidth: .infinity, minHeight: 16, maxHeight: 16, alignment: .bottom)
                .padding(.leading, CGFloat(leftMargin))
                .padding(.trailing, CGFloat(rightMargin))
                .padding(.bottom, safeInsets.bottom + CGFloat(bottomMargin))
                .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
    }
}

/// 已按当前版式完成分页的相邻章节；接纳后 contentID 必须保持不变。
struct PageTurnChapter {
    let contentID: String
    let pages: [AnyView]
}

/// 保持调用接口稳定：滑动使用覆盖翻页，卷页继续交给系统容器。
struct PageTurnView: View {
    let pages: [AnyView]
    @Binding var current: Int
    let style: PageTurnStyle
    let background: UIColor
    let onEdge: (Int) -> Void
    let onTapCenter: () -> Void
    var contentID: String = ""
    var chapterDirection: Int = 0
    /// 每次内容替换稳定后调用（包括系统跳过动画），父层据此解除锁。
    var onContentTransitionCompleted: () -> Void = {}
    var previousChapter: PageTurnChapter? = nil
    var nextChapter: PageTurnChapter? = nil
    /// 仅原生翻页提交后调用；父层原子接纳对应快照和页码，不再发起第二次动画。
    var onChapterTransition: (_ direction: Int, _ pageIndex: Int) -> Void = { _, _ in }

    @ViewBuilder var body: some View {
        switch style {
        case .slide: ReaderCoverPageTurnView(model: self)
        case .curl: NativePageTurnView(model: self, transitionStyle: .pageCurl)
        }
    }

    private struct NativePageTurnView: UIViewControllerRepresentable {
        let model: PageTurnView
        let transitionStyle: UIPageViewController.TransitionStyle

        func makeCoordinator() -> PageTurnCoordinator { PageTurnCoordinator(model) }

        func makeUIViewController(context: Context) -> UIPageViewController {
            let vc = UIPageViewController(transitionStyle: transitionStyle, navigationOrientation: .horizontal,
                options: [.spineLocation: UIPageViewController.SpineLocation.min.rawValue])
            vc.view.backgroundColor = model.background
            // 双面仅提供不透明主题纸背；卷曲、阴影、曲线和跟手仍完全由 UIKit 绘制。
            vc.isDoubleSided = transitionStyle == .pageCurl
            vc.view.clipsToBounds = true
            vc.delegate = context.coordinator
            context.coordinator.attach(vc)

            let pan = ChapterTurnPanObserver(target: context.coordinator, action: #selector(PageTurnCoordinator.panned(_:)))
            pan.delegate = context.coordinator
            pan.maximumNumberOfTouches = 1
            pan.cancelsTouchesInView = false
            pan.delaysTouchesBegan = false
            pan.delaysTouchesEnded = false
            vc.view.addGestureRecognizer(pan)
            let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(PageTurnCoordinator.tapped(_:)))
            tap.delegate = context.coordinator
            tap.cancelsTouchesInView = false
            tap.require(toFail: pan)
            vc.view.addGestureRecognizer(tap)
            context.coordinator.update(model)
            return vc
        }

        func updateUIViewController(_ vc: UIPageViewController, context: Context) {
            context.coordinator.update(model)
        }
    }
}
