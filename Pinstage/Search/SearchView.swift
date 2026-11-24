import AppKit
import PinstageCore
import SwiftUI

/// 検索の欄（打つ欄と、絞り込んだ結果の一覧）
struct SearchView: View {
    let model: SearchModel
    @FocusState private var isFocused: Bool

    var body: some View {
        let results = model.results
        // 選んでいる行は、絞り込みをやり直して求めるので、行ごとには求めない
        let selected = model.selected
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                TextField("ウインドウ・グループを検索", text: Binding(get: { model.query }, set: { model.query = $0 }))
                    .textFieldStyle(.plain)
                    .font(.title2)
                    .focused($isFocused)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider()

            if results.isEmpty {
                Text("見つかりません")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(results.enumerated()), id: \.offset) { index, item in
                                SearchRow(item: item, model: model, isSelected: index == selected)
                                    .id(index)
                                    .onTapGesture { model.activate(at: index) }
                            }
                        }
                        .padding(6)
                    }
                    .scrollIndicators(.never)
                    // ↑↓ で選んだ行が見えるようにする
                    .onChange(of: selected) { _, selected in
                        proxy.scrollTo(selected)
                    }
                }
            }

            Divider()
            Text("↑↓ で選ぶ　↩ で出す　⌘↩ でステージに足す　esc で閉じる")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 6)
        }
        .frame(width: SearchController.size.width, height: SearchController.size.height)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.separator))
        .defaultFocus($isFocused, true)
        .onAppear {
            // パネルがキーウインドウになるのを待ってから、文字の欄にフォーカスを入れる
            DispatchQueue.main.async { isFocused = true }
        }
    }
}

/// 結果の 1 行（ウインドウはアプリのアイコン、グループは中身のアイコンを重ねて）
private struct SearchRow: View {
    let item: SearchItem<SearchTarget>
    let model: SearchModel
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            icon
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.25) : .clear)
        )
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var icon: some View {
        switch item.id {
        case .window(let id):
            if let icon = model.stage.item(for: id)?.icon {
                Image(nsImage: icon).resizable()
            }
        case .group(let id):
            let members = model.stage.library.group(id: id)?.members ?? []
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.accentColor.opacity(0.18))
                HStack(spacing: -8) {
                    ForEach(Array(members.prefix(3).enumerated()), id: \.offset) { _, member in
                        MemberIcon(bundleID: member.bundleID, size: 18)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.accentColor)
                    .offset(x: 2, y: 2)
            }
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch item.id {
        case .group:
            Text("グループ")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .window(let id):
            if model.stage.stage(on: model.screen).selection.contains(id) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
                    .help("ステージに出しています")
            }
        }
    }
}
