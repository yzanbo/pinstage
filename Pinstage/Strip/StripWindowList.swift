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

    /// 「ほかのウインドウ」のボタンの高さ（おおよそ）
    private static let footerHeight: CGFloat = 24
    /// アイコンの並びの、1 つ分の幅のいちばん小さい値
    private static let tileSize: CGFloat = 50

    var body: some View {
        let limit = stage.stripSettings.visibleCount
        // このストリップが置かれたデスクトップの一覧で並べる（ほかのデスクトップに切り替えている間も、この一覧のまま）
        let rows = strip.rows
        // ほかのウインドウの数は、ストリップに並べる候補（このデスクトップのウインドウ）で数える
        let all = strip.candidates
        let isIconOnly = stage.stripSettings.itemSize.isIconOnly
        VStack(alignment: .leading, spacing: 6) {
            if !isIconOnly {
                SectionHeader(title: "ウインドウ", count: all.count)
            }
            // 一覧は決まった高さの行。ほかは、ウインドウが少ないとき、行を同じ高さで広げて縦いっぱいに並べる（多いときは中身の高さのままスクロール）
            let look = stage.stripSettings.itemSize
            let spacing = StripRowSizing.spacing(size: look)
            let rowHeight = StripRowSizing.rowHeight(
                size: look,
                available: listHeight,
                count: rows.count,
                footer: all.count > limit ? Self.footerHeight : 0
            )
            let tiles = look.showsTiles
            ScrollView {
                if tiles {
                    // アイコンだけを、ストリップの幅に合わせて何個か並べる
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.tileSize), spacing: spacing)], spacing: spacing) {
                        rowViews(rows, rowHeight: 0)
                    }
                    .coordinateSpace(.named(ReorderState.windowSpace))
                    .overlay(alignment: .topLeading) { DropLine(reorder: reorder, count: rows.count, isGrid: true) }
                }
                LazyVStack(spacing: spacing) {
                    if !tiles {
                        rowViews(rows, rowHeight: rowHeight)
                    }
                    if all.count > limit {
                        Button(isIconOnly
                            ? (stage.showsAllWindows ? "−" : "+\(all.count - limit)")
                            : (stage.showsAllWindows ? "たたむ" : "ほかのウインドウ（\(all.count - limit)）")) {
                            stage.showsAllWindows.toggle()
                            thumbnails.captureNow()
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                        .padding(.top, 2)
                    }
                    if all.isEmpty, stage.isTrusted, !isIconOnly {
                        Text("ウインドウがありません")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .coordinateSpace(.named(ReorderState.windowSpace))
                .overlay(alignment: .topLeading) {
                    if !tiles { DropLine(reorder: reorder, count: rows.count, isGrid: false) }
                }
            }
            .scrollIndicators(.never)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// ウインドウの行（アイコンの並びでも、一覧でも同じ行。rowHeight が 0 なら、中身の高さのまま）
    private func rowViews(_ rows: [WindowItem], rowHeight: CGFloat) -> some View {
        ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
            WindowRow(
                item: item, index: index, count: rows.count, rowHeight: rowHeight,
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
    /// 行のいちばん低い高さ（ウインドウが少ないときは大きくなる。0 なら中身の高さのまま）
    let rowHeight: CGFloat
    let reorder: ReorderState
    let stage: StageController
    let thumbnails: ThumbnailStore
    let strip: StripController

    @State private var isHovering = false

    private var isOnStage: Bool { stage.stage(on: strip.screen).selection.contains(item.id) }
    private var size: StripItemSize { stage.stripSettings.itemSize }
    /// アイコンの並び（タイル）の 1 つとして描くか
    private var isTile: Bool { size.showsTiles }
    private var showsThumbnail: Bool { size.showsThumbnails }
    /// アイコンだけを描くか（ストリップが細い帯のとき・アイコンの並びのとき）
    private var showsIconOnly: Bool { size.isIconOnly || isTile }

    /// 行が大きくなったときのアイコンの大きさ（元の大きさから、少しだけ大きくする）
    private var scaledIconSize: CGFloat {
        if isTile { return 36 }
        if size.isIconOnly {
            // 細い帯の幅に収まる大きさまで
            return min(44, max(size.iconSize, rowHeight - 12))
        }
        // 一覧は、行の高さを変えないので、アイコンも決まった大きさ
        if size == .list { return size.iconSize }
        return min(size.iconSize * 1.6, max(size.iconSize, (rowHeight - 12) * 0.55))
    }

    /// 行が大きくなったときのサムネイルの高さ（名前の行と余白の分を除いた高さまで広げる）
    private var scaledThumbnailHeight: CGFloat {
        max(size.thumbnailHeight, rowHeight - 34)
    }

    var body: some View {
        content
            .padding(.horizontal, showsIconOnly ? 4 : 8)
            .padding(.vertical, size == .list || showsIconOnly ? 4 : 6)
            .frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .leading)
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
                isGrid: isTile,
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
        var operations = "クリックで出す・ダブルクリックで画面いっぱいに広げる・⌘＋クリックで足す/外す・右へドラッグで足す・グループの上へドラッグでグループに入れる"
        if let desktopName { operations = "\(desktopName.title)のウインドウです（クリックで、そのデスクトップへ移って出す）\n" + operations }
        let name = item.title.isEmpty ? item.appName : "\(item.title)（\(item.appName)）"
        return name + "\n" + operations
    }

    @ViewBuilder
    private var content: some View {
        if showsIconOnly {
            appIcon(size: scaledIconSize)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .bottomTrailing) { minimizedMark }
        } else if showsThumbnail {
            VStack(alignment: .leading, spacing: 4) {
                thumbnail
                HStack(spacing: 4) {
                    Text(item.displayTitle)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                    desktopMark
                    minimizedMark
                }
            }
        } else {
            HStack(spacing: 8) {
                appIcon(size: scaledIconSize)
                // ブラウザの縦のタブと同じく、アイコンと名前を 1 行で（アプリの名前は、ポインタを乗せると出る）
                Text(item.displayTitle)
                    .font(.system(size: 13))
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
                    appIcon(size: size.iconSize * 1.4)
                }
            }
            .frame(maxWidth: .infinity, minHeight: scaledThumbnailHeight, maxHeight: scaledThumbnailHeight)
            // サムネイルを撮れたときだけ、左下にアプリのアイコンを添える（撮れていないときは、真ん中のアイコンだけ）
            if thumbnails.images[item.id] != nil {
                appIcon(size: 18)
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
