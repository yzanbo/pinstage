import AppKit
import PinstageCore
import SwiftUI

struct WindowSection: View {
    let stage: StageController
    let thumbnails: ThumbnailStore
    let strip: StripController
    @State private var reorder = ReorderState()
    /// 一覧に使える高さ（ウインドウが少ないとき、行を大きくして埋めるのに使う）
    @State private var listHeight: CGFloat = 0
    /// 横長の帯で、一覧に使える幅（一覧のタブの幅を決めるのに使う）
    @State private var listWidth: CGFloat = 0

    /// 「ほかのウインドウ」のボタンの高さ（おおよそ）
    private static let footerHeight: CGFloat = 24
    /// 横長の帯の、「ほかのウインドウ」のボタンの幅
    private static let moreWidth: CGFloat = 30

    var body: some View {
        if strip.isHorizontal {
            bar
        } else {
            column
        }
    }

    /// 並べる数より多いウインドウを開く・たたむボタン
    /// - Parameters:
    ///   - hidden: たたんでいるウインドウの数
    ///   - short: 短く「+n」「−」で出すか（細い帯・横長の帯。長い説明は、ポインタを乗せると出す）
    private func moreButton(hidden: Int, short: Bool) -> some View {
        let title = stage.showsAllWindows ? "たたむ" : "ほかのウインドウ（\(hidden)）"
        return Button(short ? (stage.showsAllWindows ? "−" : "+\(hidden)") : title) {
            stage.showsAllWindows.toggle()
            thumbnails.captureNow()
        }
        .buttonStyle(.link)
        .font(.caption)
        .help(short ? title : "")
    }

    private var emptyMessage: some View {
        Text("ウインドウがありません")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    /// 上下に出したとき: ウインドウを横に並べる（多いときは横にスクロール）
    @ViewBuilder
    private var bar: some View {
        let limit = stage.stripSettings.visibleCount
        let rows = strip.rows
        let all = strip.candidates
        let kind = strip.rowKind
        let spacing = StripRowSizing.spacing(kind: kind)
        let hasMore = all.count > limit
        // 一覧は、ブラウザの横のタブのように、使える幅を同じ幅で分ける
        let itemWidth = StripRowSizing.barItemWidth(
            kind: kind,
            available: listWidth,
            count: rows.count,
            trailing: hasMore ? Self.moreWidth + spacing : 0
        )
        ScrollView(.horizontal) {
            HStack(spacing: spacing) {
                rowViews(rows, rowHeight: StripRowSizing.barRowHeight(kind: kind), width: itemWidth)
                if hasMore {
                    moreButton(hidden: all.count - limit, short: true)
                        .frame(width: Self.moreWidth)
                }
                if all.isEmpty, stage.isTrusted {
                    emptyMessage
                        .padding(.horizontal, 6)
                }
            }
            .coordinateSpace(.named(ReorderState.windowSpace))
            .overlay(alignment: .topLeading) { DropLine(reorder: reorder, count: rows.count, layout: .columns) }
        }
        .scrollIndicators(.never)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { listWidth = $0 }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 左右に出したとき: ウインドウを縦に並べる
    @ViewBuilder
    private var column: some View {
        let limit = stage.stripSettings.visibleCount
        // このストリップが置かれたデスクトップの一覧で並べる（ほかのデスクトップに切り替えている間も、この一覧のまま）
        let rows = strip.rows
        // ほかのウインドウの数は、ストリップに並べる候補（このデスクトップのウインドウ）で数える
        let all = strip.candidates
        let isIconOnly = strip.isCompact
        VStack(alignment: .leading, spacing: 6) {
            if !isIconOnly {
                SectionHeader(title: "ウインドウ", count: all.count)
            }
            // 一覧・アイコンは決まった高さ。サムネイルは、ウインドウが少ないとき、行を同じ高さで広げて縦いっぱいに並べる（多いときは中身の高さのままスクロール）
            let kind = strip.rowKind
            let spacing = StripRowSizing.spacing(kind: kind)
            let rowHeight = StripRowSizing.rowHeight(
                kind: kind,
                available: listHeight,
                count: rows.count,
                footer: all.count > limit ? Self.footerHeight : 0
            )
            let tiles = kind.showsIconOnly
            ScrollView {
                if tiles {
                    // アイコンだけを、ストリップの幅に入るだけ並べる（狭めると 1 列になる）
                    let tileWidth = kind.size.tileWidth
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: tileWidth), spacing: spacing)], spacing: spacing) {
                        rowViews(rows, rowHeight: rowHeight)
                    }
                    .coordinateSpace(.named(ReorderState.windowSpace))
                    .overlay(alignment: .topLeading) { DropLine(reorder: reorder, count: rows.count, layout: .grid) }
                }
                LazyVStack(spacing: spacing) {
                    if !tiles {
                        rowViews(rows, rowHeight: rowHeight)
                    }
                    if all.count > limit {
                        moreButton(hidden: all.count - limit, short: isIconOnly)
                            .padding(.top, 2)
                    }
                    if all.isEmpty, stage.isTrusted, !isIconOnly {
                        emptyMessage
                    }
                }
                .coordinateSpace(.named(ReorderState.windowSpace))
                .overlay(alignment: .topLeading) {
                    if !tiles { DropLine(reorder: reorder, count: rows.count) }
                }
            }
            .scrollIndicators(.never)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// ウインドウの行（アイコンの並びでも、一覧でも同じ行。rowHeight が 0 なら、中身の高さのまま）
    /// - Parameter width: 横長の帯に並べるときの、1 つ分の幅（縦に並べるときは nil で、幅いっぱい）
    private func rowViews(_ rows: [WindowItem], rowHeight: CGFloat, width: CGFloat? = nil) -> some View {
        ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
            WindowRow(
                item: item, index: index, count: rows.count, rowHeight: rowHeight, fixedWidth: width,
                reorder: reorder, stage: stage, thumbnails: thumbnails, strip: strip
            )
        }
    }
}

/// ウインドウ 1 つ分の行
///
/// - クリック: そのウインドウだけを出す
/// - ⌘＋クリック: 足す・外す
/// - ストリップの外（ステージ）へドラッグ: 足す
private struct WindowRow: View {
    let item: WindowItem
    let index: Int
    let count: Int
    /// 行のいちばん低い高さ（ウインドウが少ないときは大きくなる。0 なら中身の高さのまま）。横長の帯では、決まった高さ
    let rowHeight: CGFloat
    /// 横長の帯に並べるときの幅（縦に並べるときは nil で、幅いっぱい）
    var fixedWidth: CGFloat?
    let reorder: ReorderState
    let stage: StageController
    let thumbnails: ThumbnailStore
    let strip: StripController

    @State private var isHovering = false

    private var isOnStage: Bool { stage.stage(on: strip.screen).selection.contains(item.id) }
    /// 行の描き方（形式と大きさから決まる）
    private var kind: StripRowKind { strip.rowKind }
    /// アイコンの並び（タイル）の 1 つとして描くか
    private var isTile: Bool { kind.showsIconOnly }
    private var showsThumbnail: Bool { kind.isThumbnail }
    /// アイコンだけを描くか（アイコンの並びのとき）
    private var showsIconOnly: Bool { kind.showsIconOnly }
    /// 並べ替えのときの並べ方（横長の帯では横に、アイコンの並びでは格子に、ほかは縦に並んでいる）
    private var reorderLayout: ReorderLayout {
        if strip.isHorizontal { return .columns }
        return isTile ? .grid : .rows
    }

    /// サムネイルの高さ（大きさで決まる高さより低くはせず、行が大きくなったら、名前の行と余白の分を除いた高さまで広げる）
    private var scaledThumbnailHeight: CGFloat {
        max(kind.size.thumbnailHeight, rowHeight - StripRowSizing.thumbnailCaptionHeight)
    }

    /// サムネイルの下の、名前の文字
    private var thumbnailFont: Font {
        kind.size.thumbnailFontSize.map { .system(size: $0) } ?? .caption
    }

    var body: some View {
        content
            .padding(.horizontal, showsIconOnly ? 4 : 8)
            .padding(.vertical, kind.isList || showsIconOnly ? 4 : 6)
            .modifier(RowFrame(width: fixedWidth, height: rowHeight))
            .background(
                RoundedRectangle(cornerRadius: StripStyle.cornerRadius, style: .continuous)
                    .fill(isOnStage ? StripStyle.selectedFill : (isHovering ? StripStyle.rowHoverFill : StripStyle.rowFill))
            )
            .overlay(
                RoundedRectangle(cornerRadius: StripStyle.cornerRadius, style: .continuous)
                    .strokeBorder(isOnStage ? Color.accentColor.opacity(0.9) : .clear, lineWidth: 1.5)
            )
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovering)
            .modifier(ReorderDrag(
                index: index,
                count: count,
                space: ReorderState.windowSpace,
                layout: reorderLayout,
                reorder: reorder,
                strip: strip,
                onTap: handleClick,
                onMove: { stage.moveWindow(from: index, dropIndex: $0, visible: strip.rows.map(\.id)) },
                // ストリップの外（ステージ）で離したら、ステージに足す
                onDropOutside: { stage.add(item, on: StageController.screenUnderPointer ?? strip.screen) },
                // グループの行の上で離したら、そのグループに足す
                onDropOnGroup: { stage.addWindow(item, toGroup: $0) }
            ))
            .contextMenu {
                if isOnStage {
                    Button("ステージから外す") { stage.remove(item, on: strip.screen) }
                    Divider()
                }
                Button("ウインドウを閉じる") { stage.close(item) }
                Button("「\(item.appName)」を終了") { stage.quitApp(of: item) }
            }
            .help(helpText)
    }

    /// ほかのデスクトップのウインドウなら、そのデスクトップの名前（「ほかのデスクトップのウインドウも出す」のとき）
    private var desktopName: DesktopName? {
        stage.desktopName(of: item, except: strip.spaceID)
    }

    /// ポインタを乗せたときの説明（名前は行に収まらないことがあるので、ここにすべて出す。アプリの名前も添える）
    private var helpText: String {
        var operations = "クリックで出す・ダブルクリックで画面いっぱいに広げる・⌘＋クリックで足す/外す・ステージへドラッグで足す・グループの上へドラッグでグループに入れる"
        if let desktopName { operations = "\(desktopName.title)のウインドウです（クリックで、そのデスクトップへ移って出す）\n" + operations }
        let name = item.title.isEmpty ? item.appName : "\(item.title)（\(item.appName)）"
        return name + "\n" + operations
    }

    @ViewBuilder
    private var content: some View {
        if showsIconOnly {
            appIcon(size: kind.iconSize)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .bottomTrailing) { minimizedMark }
        } else if showsThumbnail {
            VStack(alignment: .leading, spacing: 4) {
                thumbnail
                HStack(spacing: 4) {
                    Text(item.displayTitle)
                        .font(thumbnailFont)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                    desktopMark
                    minimizedMark
                }
            }
        } else {
            HStack(spacing: 8) {
                appIcon(size: kind.iconSize)
                // ブラウザの縦のタブと同じく、アイコンと名前を 1 行で（アプリの名前は、ポインタを乗せると出る）
                Text(item.displayTitle)
                    .font(.system(size: kind.size.listFontSize))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                desktopMark
                minimizedMark
            }
        }
    }

    /// ウインドウの中身（まだ撮っていなければ、アプリのアイコン）。左下にアプリのアイコンを添える
    private var thumbnail: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let image = thumbnails.images[item.id] {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .shadow(radius: 1, y: 1)
                } else {
                    appIcon(size: kind.iconSize * 1.4)
                }
            }
            .frame(maxWidth: .infinity, minHeight: scaledThumbnailHeight, maxHeight: scaledThumbnailHeight)
            // サムネイルを撮れたときだけ、左下にアプリのアイコンを添える（撮れていないときは、真ん中のアイコンだけ）
            if thumbnails.images[item.id] != nil {
                appIcon(size: kind.size.thumbnailBadgeSize)
                    .offset(x: -2, y: 2)
            }
        }
    }

    @ViewBuilder
    private func appIcon(size: CGFloat) -> some View {
        if let icon = item.icon {
            Image(nsImage: icon)
                .resizable()
                .frame(width: size, height: size)
        }
    }

    /// ほかのデスクトップのウインドウの短い印（重なった四角と、デスクトップの番号。名前を押しのけないように短くする）
    @ViewBuilder
    private var desktopMark: some View {
        if let desktopName {
            HStack(spacing: 2) {
                Image(systemName: "rectangle.on.rectangle")
                Text(desktopName.shortLabel)
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Capsule().fill(Color.primary.opacity(0.08)))
        }
    }

    @ViewBuilder
    private var minimizedMark: some View {
        if item.isMinimized {
            Image(systemName: "arrow.down.right.and.arrow.up.left")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .help("しまってあるウインドウ")
        }
    }

    /// クリック（1 回目でそのウインドウだけを出し、2 回目＝ダブルクリックでステージいっぱいに広げる。⌘ なら足す・外す）
    private func handleClick() {
        if NSEvent.modifierFlags.contains(.command) {
            stage.toggle(item, on: strip.screen)
        } else if NSApp.currentEvent?.clickCount ?? 1 >= 2 {
            stage.showMaximized(item, on: strip.screen)
        } else {
            stage.showOnly(item, on: strip.screen)
        }
    }
}

/// 行の大きさ。縦に並べるときは幅いっぱい（高さは、いちばん低い高さだけ決める）、横長の帯に並べるときは決まった幅と高さ
private struct RowFrame: ViewModifier {
    let width: CGFloat?
    let height: CGFloat

    func body(content: Content) -> some View {
        if let width {
            content.frame(width: width, height: height, alignment: .leading)
        } else {
            content.frame(maxWidth: .infinity, minHeight: height, alignment: .leading)
        }
    }
}
