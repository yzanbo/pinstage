import AppKit
import PinstageCore
import SwiftUI

/// ウインドウバーとウィンドウスイッチャーで共通のアプリアイコン。
/// アイコンの薄さは画像だけに適用し、通知とデスクトップの印は読みやすく保つ。
struct WindowAppIcon: View {
    let image: NSImage?
    let size: CGFloat
    let badges: [AppIconBadge]
    var isDimmed = false
    var showsAllDesktops = false
    /// スイッチャーでは、アプリのアイコンが取れなくても代わりの絵を出して枠を保つ。
    var showsFallback = false

    var body: some View {
        icon
            .opacity(isDimmed ? 0.45 : 1)
            .overlay {
                ZStack {
                    ForEach(badges) { badge in
                        AppNotificationBadge(badge: badge, iconSize: size)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: badge.corner.alignment)
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if showsAllDesktops { DesktopBadge.allDesktopsIcon(iconSize: size) }
            }
    }

    @ViewBuilder private var icon: some View {
        if showsFallback {
            (image.map(Image.init(nsImage:)) ?? Image(systemName: "macwindow"))
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else if let image {
            Image(nsImage: image)
                .resizable()
                .frame(width: size, height: size)
        }
    }
}

private extension AppIconBadge.Corner {
    var alignment: Alignment {
        switch self {
        case .topLeft: .topLeading
        case .topRight: .topTrailing
        case .bottomLeft: .bottomLeading
        }
    }
}

private struct AppNotificationBadge: View {
    let badge: AppIconBadge
    let iconSize: CGFloat

    private var height: CGFloat {
        badge.isPublished ? max(8, (iconSize * 0.31).rounded()) : max(10, (iconSize * 0.4).rounded())
    }

    private var channels: (red: Double, green: Double, blue: Double)? {
        badge.rgb.map { (Double(($0 >> 16) & 255) / 255, Double(($0 >> 8) & 255) / 255, Double($0 & 255) / 255) }
    }

    private var background: Color {
        channels.map { Color(red: $0.red, green: $0.green, blue: $0.blue) } ?? .red
    }

    private var foreground: Color {
        guard let channels else { return .white }
        func linear(_ channel: Double) -> Double {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(channels.red) + 0.7152 * linear(channels.green) + 0.0722 * linear(channels.blue)
        return 1.05 / (luminance + 0.05) >= 4.5 ? .white : .black
    }

    var body: some View {
        Group {
            if badge.text == "•" {
                Circle()
                    .fill(background)
                    .frame(width: height * 0.75, height: height * 0.75)
            } else {
                Text(badge.text)
                    .font(.system(size: height * 0.62, weight: .semibold).monospacedDigit())
                    .foregroundStyle(foreground)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, height * (badge.isPublished ? 0.18 : 0.25))
                    .frame(minWidth: height, minHeight: height)
                    .background(Capsule().fill(background))
            }
        }
        .shadow(color: .black.opacity(0.25), radius: 0.5, y: 0.5)
        .offset(x: height * (badge.corner == .topRight ? (badge.isPublished ? 0.45 : 0.3) : -0.45),
                y: height * (badge.corner == .bottomLeft ? 0.15 : -0.3))
        .accessibilityLabel(badge.description)
        .help(badge.description)
    }
}
