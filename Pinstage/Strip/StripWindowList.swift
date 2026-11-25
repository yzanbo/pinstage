import AppKit
import PinstageCore
import SwiftUI

struct WindowSection: View {
    /// 一覧の両端（縦なら上下、横長の帯なら左右）の余白。いちばん上・下へドラッグしたときの線を、行に重ねずに、ここに引く
    private static let dropMargin: CGFloat = 4

    let stage: StageController
    let thumbnails: ThumbnailStore
    let strip: StripController
    /// 並べ替えの状態はウインドウバーが持つ（別のディスプレイのウインドウバーから持ってきたときも、同じ線を出すため）
    private var reorder: ReorderState { strip.windowReorder }
    /// 一覧に使える幅（横長の帯では一覧のタブの幅、左右のアイコンの並びでは列の数を決めるのに使う）
    @State private var listWidth: CGFloat = 0
    /// 「視差効果を減らす」がオンなら、動きを付けない
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// ウインドウが増えた・減った・並びが変わったときの動き（Chrome のタブと同じく、ほかの行がすべるように詰まる）
    private var listAnimation: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.25)
    }

    var body: some View {
        if strip.isHorizontal {
            bar
        } else {
            column
        }
    }

    /// 行が現れる・消えるときの動き（縦に並べるときは上から、横に並べるときは左から広がる）
    private static func rowTransition(horizontal: Bool) -> AnyTransition {
        let anchor: UnitPoint = horizontal ? .leading : .top
        return .asymmetric(
            insertion: .scale(scale: 0.85, anchor: anchor).combined(with: .opacity),
            removal: .scale(scale: 0.85, anchor: anchor).combined(with: .opacity)
        )
    }

    private var emptyMessage: some View {
        Text("ウインドウがありません")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    /// 上下に出したとき: ウインドウを横に並べる（多いときは横にスクロール）
    @ViewBuilder
    private var bar: some View {
        let rows = strip.rows
        let kind = strip.rowKind
        let spacing = StripRowSizing.spacing(kind: kind)
        // 一覧は、ブラウザの横のタブのように、使える幅（両端の余白を除いた分）を同じ幅で分ける
        let itemWidth = StripRowSizing.barItemWidth(kind: kind, available: listWidth - Self.dropMargin * 2, count: rows.count)
        ScrollView(.horizontal) {
            // 行の間は、行ごとに空ける（同じアプリのウインドウは詰めてつなぐ）
            HStack(spacing: 0) {
                rowViews(rows, rowHeight: StripRowSizing.barRowHeight(kind: kind), width: itemWidth, arrangement: .horizontal, spacing: spacing)
                if rows.isEmpty, stage.isTrusted {
                    emptyMessage
                        .padding(.horizontal, 6)
                }
            }
            .modifier(reorderList(rows, layout: .columns))
            .animation(listAnimation, value: rows.map(\.id))
        }
        .scrollIndicators(.never)
        // いちばん左・右へドラッグしたときの線を引く余白
        .contentMargins(.horizontal, Self.dropMargin, for: .scrollContent)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { listWidth = $0 }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 左右に出したとき: ウインドウを縦に並べる
    @ViewBuilder
    private var column: some View {
        // このウインドウバーが置かれたデスクトップの一覧で並べる（ほかのデスクトップに切り替えている間も、この一覧のまま。数で区切らず、多いときはスクロール）
        let rows = strip.rows
        let isIconOnly = strip.isCompact
        VStack(alignment: .leading, spacing: 6) {
            if !isIconOnly {
                SectionHeader(title: "ウインドウ", count: rows.count)
                    .contentShape(Rectangle())
                    .desktopListContextMenu(stage: stage)
            }
            // どの形式も、大きさで決まった高さ（ウインドウが少なくても縦いっぱいには広げない。多ければスクロール）
            let kind = strip.rowKind
            let spacing = StripRowSizing.spacing(kind: kind)
            let rowHeight = StripRowSizing.rowHeight(kind: kind)
            let tiles = kind.showsIconOnly
            // アイコンだけのときの格子（ストリップの幅に入るだけ並べる。狭めると 1 列になる）。
            // 同じアプリのアイコンを枠でつなぐのに折り返しの位置が要るので、列の数は自分で決める（決まりは PinstageCore の StripRowSizing.gridLayout）
            let grid = StripRowSizing.gridLayout(width: listWidth, tileWidth: kind.size.tileWidth, spacing: spacing, sideMargin: Self.dropMargin)
            ScrollView {
                VStack(spacing: 0) {
                    if tiles {
                        let arrangement = RowJoin.Arrangement.grid(columns: grid.columns)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: grid.columns), spacing: spacing) {
                            rowViews(rows, rowHeight: rowHeight, arrangement: arrangement, spacing: spacing)
                        }
                        .modifier(reorderList(rows, layout: ReorderLayout(arrangement)))
                    } else {
                        // 行の間は、行ごとに空ける（同じアプリのウインドウは詰めてつなぐ）
                        LazyVStack(spacing: 0) {
                            rowViews(rows, rowHeight: rowHeight, arrangement: .vertical, spacing: spacing)
                        }
                        .modifier(reorderList(rows, layout: .rows))
                    }
                    if rows.isEmpty, stage.isTrusted, !isIconOnly {
                        emptyMessage
                    }
                }
                .animation(listAnimation, value: rows.map(\.id))
            }
            .scrollIndicators(.never)
            // いちばん上・下へドラッグしたときの線を引く余白（アイコンが複数の列のときは、左右の端の線のために、左右も空ける）
            .contentMargins(.vertical, Self.dropMargin, for: .scrollContent)
            .contentMargins(.horizontal, tiles ? grid.sideMargin : 0, for: .scrollContent)
            // アイコンの格子の列の数を決めるのに使う
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { listWidth = $0 }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// 行を並べたビューを、並べ替えられる一覧にする（一覧の座標・落とす位置の線）
    private func reorderList(_ rows: [WindowItem], layout: ReorderLayout) -> ReorderList {
        ReorderList(reorder: reorder, space: ReorderState.windowSpace, keys: rows.map(\.appKey), layout: layout, margin: Self.dropMargin)
    }

    /// ウインドウの行（アイコンの並びでも、一覧でも同じ行。rowHeight が 0 なら、中身の高さのまま）
    /// - Parameters:
    ///   - width: 横長の帯に並べるときの、1 つ分の幅（縦に並べるときは nil で、幅いっぱい）
    ///   - arrangement: 並べ方（となり合った同じアプリのウインドウを、1 つの枠につなぐ向きが決まる）
    ///   - spacing: 行の間（一覧・帯では、つながない行の間はこの幅、つなぐ行の間は RowJoin.spacing。格子では、タイルの間）
    private func rowViews(_ rows: [WindowItem], rowHeight: CGFloat, width: CGFloat? = nil, arrangement: RowJoin.Arrangement, spacing: CGFloat) -> some View {
        let apps = rows.map(\.appKey)
        // 格子は、行の間を格子が空ける（行ごとには空けない）
        let isGrid = if case .grid = arrangement { true } else { false }
        return ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
            let join = RowJoin(index: index, apps: apps, arrangement: arrangement, gap: spacing)
            WindowRow(
                item: item, index: index, count: rows.count, rowHeight: rowHeight, fixedWidth: width, join: join,
                reorderLayout: ReorderLayout(arrangement), reorder: reorder, stage: stage, thumbnails: thumbnails, strip: strip
            )
            // 行の前の間（最初の行は空けない。同じアプリの前の行との間は、まとまりの枠の中で空ける）
            .padding(join.axis == .horizontal ? .leading : .top, index == 0 || isGrid || join.previous ? 0 : spacing)
            // 開いたウインドウは、その位置で広がって現れ、閉じたウインドウは縮んで消える（Chrome のタブと同じ）
            .transition(Self.rowTransition(horizontal: arrangement == .horizontal))
            // ドラッグで動いている行は、ほかの行より手前に描く（いちばん外側に付ける。内側に付けると効かない）
            .zIndex(reorder.isMoving(index) ? 1 : 0)
        }
    }
}

/// ウインドウ 1 つ分の行
///
/// - クリック: そのウインドウだけを出す
/// - ⌘＋クリック: 足す・外す
/// - ストリップの外（ステージ）へドラッグ: 足す
/// - 別のディスプレイのウインドウバーへドラッグ: そのディスプレイへ移して、それだけを出す
private struct WindowRow: View {
    let item: WindowItem
    let index: Int
    let count: Int
    /// 行のいちばん低い高さ（形式と大きさで決まる。0 なら中身の高さのまま）。横長の帯では、決まった高さ
    let rowHeight: CGFloat
    /// 横長の帯に並べるときの幅（縦に並べるときは nil で、幅いっぱい）
    var fixedWidth: CGFloat?
    /// となり合った同じアプリのウインドウとのつながり（つながる側の角を小さくする）
    var join = RowJoin()
    /// 並べ替えのときの並べ方（落とす位置の決め方と、線の向き）
    let reorderLayout: ReorderLayout
    let reorder: ReorderState
    let stage: StageController
    let thumbnails: ThumbnailStore
    let strip: StripController

    @State private var isHovering = false

    private var isOnStage: Bool { stage.stage(on: strip.screen).selection.contains(item.id) }
    /// 行の描き方（形式と大きさから決まる）
    private var kind: StripRowKind { strip.rowKind }
    private var showsThumbnail: Bool { kind.isThumbnail }
    /// アイコンだけを描くか（アイコンの並び（タイル）のとき）
    private var showsIconOnly: Bool { kind.showsIconOnly }

    /// サムネイルの下の、名前の文字
    private var thumbnailFont: Font {
        kind.size.thumbnailFontSize.map { .system(size: $0) } ?? .caption
    }

    var body: some View {
        content
            .padding(.horizontal, showsIconOnly ? 4 : 8)
            .padding(.vertical, kind.isList || showsIconOnly ? 4 : 6)
            // 横長の帯では、まとまりの枠の分だけ低くする（帯の高さに収める）
            .modifier(RowFrame(width: fixedWidth, height: join.isInCluster && join.axis == .horizontal ? rowHeight - ClusterTray.inset * 2 : rowHeight))
            .background(
                join.shape
                    .fill(isOnStage ? StripStyle.selectedFill : (isHovering ? StripStyle.rowHoverFill : StripStyle.rowFill))
            )
            .overlay(
                join.shape
                    .strokeBorder(isOnStage ? Color.accentColor.opacity(0.9) : .clear, lineWidth: 1.5)
            )
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovering)
            // 同じアプリのウインドウを、うすい枠（トレイ）で囲む
            .modifier(ClusterTray(join: join))
            .modifier(ReorderDrag(
                index: index,
                count: count,
                space: ReorderState.windowSpace,
                layout: reorderLayout,
                // 同じアプリをまとめているとき、ほかのアプリの間へドラッグしている間は、同じアプリの行も一緒に動かす
                cluster: stage.stripSettings.groupsSameApp ? join.cluster : nil,
                // 同じアプリをまとめているときは、ほかのアプリのまとまりの中には入れられない
                canDrop: dropRule,
                reorder: reorder,
                strip: strip,
                onTap: handleClick,
                onMove: { stage.moveWindow(from: index, dropIndex: $0, visible: strip.rows.map(\.id)) },
                // ウインドウバーの外（ステージ）で離したら、ステージに足す（まとめて動かしているときは、まとまりのウインドウをすべて）
                onDropOutside: { stage.add(draggedItems, on: StageController.screenUnderPointer ?? strip.screen) },
                // グループの行の上で離したら、そのグループに足す（同じく、まとまりのウインドウをすべて）
                onDropOnGroup: { group in draggedItems.forEach { stage.addWindow($0, toGroup: group) } },
                windowDrag: WindowDragInfo(
                    preview: { StripWindowDragPreview(title: item.displayTitle, icon: item.icon, count: draggedItems.count) },
                    canDropOnOtherStrip: otherStripDropRule,
                    // 別のディスプレイのウインドウバーで離したら、そのディスプレイへ移して、持ってきたウインドウだけを出す（足さない）
                    onDropOnOtherStrip: { target, dropIndex in
                        stage.move(draggedItems, to: target.screen, dropIndex: dropIndex, visible: target.rows.map(\.id))
                    }
                )
            ))
            // スクロールして見えているかを覚える（サムネイルは見えている行だけ撮る）。
            // 見えてきた行のサムネイルがまだなければ、すぐ撮る
            .onScrollVisibilityChange(threshold: 0.05) { visible in
                strip.setRowVisible(item.id, visible)
                if visible, showsThumbnail, thumbnails.images[item.id] == nil { thumbnails.captureNow() }
            }
            .contextMenu {
                if isOnStage {
                    Button("ステージから外す") { stage.remove(item, on: strip.screen) }
                    // 複数を ⌘＋クリックで選んだあと、そのまま右クリックで保存できるように
                    Button("ステージをグループとして保存") { stage.saveStageAsGroup(on: strip.screen) }
                    Divider()
                }
                Button("ウインドウを閉じる") { stage.close(item) }
                Button("「\(item.appName)」を終了") { stage.quitApp(of: item) }
            }
            .help(helpText)
    }

    /// ほかのデスクトップのウインドウなら、そのデスクトップの名前（しまってあるウインドウなど、いまのデスクトップ以外のものが並んだとき）
    private var desktopName: DesktopName? {
        stage.desktopName(of: item, except: strip.spaceID)
    }

    /// すべてのデスクトップに割り当てたウインドウか（どのデスクトップのウインドウバーにも並ぶ）
    private var isOnAllDesktops: Bool {
        stage.isOnAllDesktops(item)
    }

    /// アイコンだけで「すべて」と最小化が重なる場合は、矢印の代わりにアイコンを薄くする。
    private var dimsMinimizedIcon: Bool { showsIconOnly && isOnAllDesktops && item.isMinimized }

    /// ポインタを乗せたときの説明（名前は行に収まらないことがあるので、ここにすべて出す。アプリの名前も添える）
    private var helpText: String {
        var operations = "クリックで出す・ダブルクリックで画面いっぱいに広げる・⌘＋クリックで足す/外す・ステージへドラッグで足す・別のディスプレイのウインドウバーへドラッグで移す・グループの上へドラッグでグループに入れる"
        if let desktopName { operations = "\(desktopName.title)のウインドウです（クリックで、そのデスクトップへ移って出す）\n" + operations }
        if isOnAllDesktops { operations = "すべてのデスクトップに割り当てたウインドウです（どのデスクトップのウインドウバーにも並びます）\n" + operations }
        if item.isMinimized { operations = "しまってあるウインドウです\n" + operations }
        let name = item.title.isEmpty ? item.appName : "\(item.title)（\(item.appName)）"
        return ([name] + stage.badges(for: item).map(\.description) + [operations]).joined(separator: "\n")
    }

    @ViewBuilder
    private var content: some View {
        if showsIconOnly {
            appIcon(size: kind.iconSize, showsAllDesktops: isOnAllDesktops)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .bottomTrailing) {
                    if !dimsMinimizedIcon { minimizedMark }
                }
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
            .frame(maxWidth: .infinity)
            .frame(height: kind.size.thumbnailHeight)
            // サムネイルを撮れたときだけ、左下にアプリのアイコンを添える（撮れていないときは、真ん中のアイコンだけ）
            if thumbnails.images[item.id] != nil {
                appIcon(size: kind.size.thumbnailBadgeSize)
                    .offset(x: -2, y: 2)
            }
        }
    }

    /// アプリのアイコン（公開されたバッジ、または右上に標準の Dock バッジを添える）
    private func appIcon(size: CGFloat, showsAllDesktops: Bool = false) -> some View {
        WindowAppIcon(image: item.icon, size: size, badges: stage.badges(for: item),
                      isDimmed: dimsMinimizedIcon, showsAllDesktops: showsAllDesktops)
    }

    /// デスクトップの印（ほかのデスクトップのウインドウなら、その番号。すべてのデスクトップに割り当てたウインドウなら「すべて」）
    @ViewBuilder
    private var desktopMark: some View {
        if isOnAllDesktops {
            // 横長の帯は行の幅が決まっていて、名前を押しのけてしまうので、絵だけにする（説明はポインタを乗せると出る）
            DesktopBadge.allDesktops(fixedWidth == nil ? "すべて" : nil)
        } else if let desktopName {
            DesktopBadge.otherDesktop(desktopName.shortLabel)
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

    /// ドラッグで一緒に動かすウインドウ（同じアプリをまとめているときは、まとまりのウインドウすべて。ほかは、この行だけ）
    private var draggedItems: [WindowItem] {
        guard stage.stripSettings.groupsSameApp, let cluster = join.cluster else { return [item] }
        let rows = strip.rows
        return cluster.compactMap { rows.indices.contains($0) ? rows[$0] : nil }
    }

    /// 落とせる位置の決まり（同じアプリをまとめているときだけ。ほかはどこでも落とせる）。
    /// まとまりはまとめて動かすので、自分のまとまりの中・すぐ前後と、ほかのアプリのまとまりの中には落とせない（決まりは PinstageCore の ListReorder.canDrop）
    private var dropRule: ((Int) -> Bool)? {
        guard stage.stripSettings.groupsSameApp else { return nil }
        let cluster = join.cluster
        return { [reorder] drop in ListReorder.canDrop(at: drop, keys: reorder.keys, cluster: cluster) }
    }

    /// 別のディスプレイのウインドウバーに落とせる位置の決まり（同じアプリをまとめているときだけ。ほかはどこでも落とせる）。
    /// 行き先に同じアプリがあれば、そのまとまりの中か、すぐ前後だけ。なければ、ほかのアプリのまとまりの中には落とせない（決まりは PinstageCore の ListReorder.canInsert）
    private var otherStripDropRule: (([String], Int) -> Bool)? {
        guard stage.stripSettings.groupsSameApp else { return nil }
        let key = item.appKey
        return { keys, drop in ListReorder.canInsert(at: drop, keys: keys, key: key) }
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
