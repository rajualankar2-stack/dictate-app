import AppKit
import SwiftUI

/// Shared look for Settings and the welcome tour: a quiet sidebar, one raised panel, white cards with
/// hairline rows, one dark action per screen. Modelled on the Hex app's window.
enum DS {
    static let sidebarBG = Color(nsColor: .windowBackgroundColor)
    static let panelBG = Color(nsColor: .controlBackgroundColor)
    static let cardBG = Color(nsColor: .textBackgroundColor)
    static let hairline = Color.primary.opacity(0.10)
    static let muted = Color.secondary
    static let faint = Color.primary.opacity(0.45)
    static let cardRadius: CGFloat = 12
}

/// A titled group of rows in a bordered card.
struct Card<Content: View>: View {
    var title: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title { Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(DS.muted).padding(.leading, 4) }
            VStack(spacing: 0) { content }
                .background(DS.cardBG, in: RoundedRectangle(cornerRadius: DS.cardRadius))
                .overlay(RoundedRectangle(cornerRadius: DS.cardRadius).stroke(DS.hairline, lineWidth: 1))
        }
    }
}

/// One setting: icon, title, one-line description, control on the right.
struct SettingRow<Control: View>: View {
    var icon: String? = nil
    var title: String
    var detail: String? = nil
    var divider = true
    @ViewBuilder var control: Control
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 14)).foregroundStyle(DS.faint).frame(width: 22)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13))
                    if let detail { Text(detail).font(.system(size: 11)).foregroundStyle(DS.muted).fixedSize(horizontal: false, vertical: true) }
                }
                Spacer(minLength: 12)
                control
            }
            .padding(.horizontal, 16).padding(.vertical, 11)
            if divider { Rectangle().fill(DS.hairline).frame(height: 1).padding(.leading, 16) }
        }
    }
}

/// A key shown as a small keycap.
struct Keycap: View {
    var label: String
    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(DS.hairline, lineWidth: 1))
            .shadow(color: .black.opacity(0.10), radius: 0, x: 0, y: 1.5)
    }
}

struct PageTitle: View {
    var text: String
    var body: some View { Text(text).font(.system(size: 22, weight: .semibold)).padding(.bottom, 4) }
}

/// The one dark action. Secondary is outlined.
struct ActionButton: View {
    var title: String
    var primary = false
    var disabled = false
    var trailingArrow = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 13, weight: .semibold))
                if trailingArrow { Image(systemName: "arrow.right").font(.system(size: 11, weight: .semibold)) }
            }
            .padding(.horizontal, 16).padding(.vertical, 7)
            .foregroundStyle(primary ? Color(nsColor: .textBackgroundColor) : Color.primary)
            .background(RoundedRectangle(cornerRadius: 8).fill(primary ? Color.primary.opacity(0.88) : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(primary ? Color.clear : DS.hairline, lineWidth: 1))
            .opacity(disabled ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

struct SmallButton: View {
    var title: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 11).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(DS.hairline, lineWidth: 1))
        }.buttonStyle(.plain)
    }
}

/// Step dots: the current step is a pill.
struct StepDots: View {
    var count: Int
    var current: Int
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule().fill(i == current ? Color.primary.opacity(0.85) : Color.primary.opacity(0.18))
                    .frame(width: i == current ? 20 : 6, height: 6)
            }
        }
        .animation(.easeOut(duration: 0.15), value: current)
    }
}
