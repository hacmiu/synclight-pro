import SwiftUI

/// Cyberpunk visual theme: near-black base, neon accents, glow, mono type.
enum Cyber {
    // Core palette
    static let bg        = Color(red: 0.04, green: 0.03, blue: 0.09)   // near-black indigo
    static let bgDeep    = Color(red: 0.02, green: 0.01, blue: 0.05)
    static let panel     = Color(red: 0.08, green: 0.07, blue: 0.16)
    static let panelEdge = Color(red: 0.20, green: 0.85, blue: 1.00)   // cyan edge

    static let cyan      = Color(red: 0.00, green: 0.95, blue: 1.00)
    static let magenta   = Color(red: 1.00, green: 0.10, blue: 0.75)
    static let purple    = Color(red: 0.62, green: 0.20, blue: 1.00)
    static let yellow    = Color(red: 1.00, green: 0.92, blue: 0.20)
    static let green     = Color(red: 0.20, green: 1.00, blue: 0.55)
    static let red       = Color(red: 1.00, green: 0.20, blue: 0.35)

    static let text      = Color(red: 0.85, green: 0.90, blue: 1.00)
    static let textDim   = Color(red: 0.50, green: 0.55, blue: 0.70)

    // Neon gradient used for accents / selected states
    static var neonGradient: LinearGradient {
        LinearGradient(colors: [cyan, purple, magenta],
                       startPoint: .leading, endPoint: .trailing)
    }

    // Subtle background grid gradient
    static var bgGradient: LinearGradient {
        LinearGradient(colors: [bgDeep, bg, panel.opacity(0.6)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Neon text helper

extension View {
    /// Glowing neon text (colored shadow bloom).
    func neonText(_ color: Color, radius: CGFloat = 8) -> some View {
        self.foregroundStyle(color)
            .shadow(color: color.opacity(0.9), radius: radius)
            .shadow(color: color.opacity(0.5), radius: radius * 2)
    }

    /// Cyberpunk panel: dark fill, neon border + outer glow, clipped corners feel.
    func cyberPanel(corner: CGFloat = 12,
                    border: Color = Cyber.cyan,
                    glow: CGFloat = 12) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: corner)
                    .fill(Cyber.panel.opacity(0.85))
            )
            .overlay(
                RoundedRectangle(cornerRadius: corner)
                    .strokeBorder(border.opacity(0.8), lineWidth: 1.2)
            )
            .shadow(color: border.opacity(0.45), radius: glow)
    }
}

// MARK: - Cyber button style

struct CyberButtonStyle: ButtonStyle {
    var color: Color = Cyber.cyan
    var prominent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.callout, design: .monospaced).weight(.bold))
            .textCase(.uppercase)
            .foregroundStyle(prominent ? Cyber.bgDeep : color)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(prominent ? color : color.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(color.opacity(0.9), lineWidth: 1.2)
            )
            .shadow(color: color.opacity(configuration.isPressed ? 0.8 : 0.5),
                    radius: configuration.isPressed ? 3 : 10)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Cyber segmented control

/// Neon segmented control replacing the native `.segmented` Picker.
struct CyberSegmented<T: Hashable>: View {
    let options: [T]
    let title: (T) -> String
    @Binding var selection: T
    var accent: Color = Cyber.cyan
    var width: CGFloat? = nil

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(options.enumerated()), id: \.element) { _, opt in
                let selected = (opt == selection)
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { selection = opt }
                } label: {
                    Text(title(opt).uppercased())
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                        .tracking(1)
                        .foregroundStyle(selected ? Cyber.bgDeep : Cyber.textDim)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(selected ? accent : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .strokeBorder(accent.opacity(selected ? 1 : 0.35), lineWidth: 1)
                        )
                        .shadow(color: selected ? accent.opacity(0.7) : .clear, radius: 8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Cyber.panel.opacity(0.8))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(accent.opacity(0.4), lineWidth: 1)
        )
        .frame(width: width)
    }
}

// MARK: - Cyber dropdown (menu selector)

/// Neon dropdown replacing a native menu Picker. Shows the current label and
/// opens a menu of options.
struct CyberDropdown<T: Hashable>: View {
    let options: [T]
    let title: (T) -> String
    @Binding var selection: T
    var accent: Color = Cyber.cyan
    var width: CGFloat = 170

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { opt in
                Button {
                    selection = opt
                } label: {
                    if opt == selection {
                        Label(title(opt), systemImage: "checkmark")
                    } else {
                        Text(title(opt))
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(title(selection).uppercased())
                    .font(.system(.callout, design: .monospaced).weight(.bold))
                    .tracking(1)
                    .foregroundStyle(Cyber.text)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(accent)
                    .shadow(color: accent, radius: 4)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(width: width)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Cyber.panel.opacity(0.85))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(accent.opacity(0.8), lineWidth: 1.2)
            )
            .shadow(color: accent.opacity(0.4), radius: 8)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

// MARK: - Section label

struct CyberSectionTitle: View {
    let text: String
    var color: Color = Cyber.cyan
    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(color).frame(width: 4, height: 16)
                .shadow(color: color, radius: 6)
            Text(text.uppercased())
                .font(.system(.headline, design: .monospaced).weight(.heavy))
                .tracking(2)
                .neonText(color, radius: 6)
            Rectangle().fill(color.opacity(0.4)).frame(height: 1)
        }
    }
}
