import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @State private var tab: Tab = .color

    enum Tab: String, CaseIterable, Identifiable {
        case color, effects, sync, settings
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .color: return "paintpalette.fill"
            case .effects: return "sparkles"
            case .sync: return "display"
            case .settings: return "gearshape.fill"
            }
        }
        /// Per-tab neon accent colour.
        var accent: Color {
            switch self {
            case .color: return Cyber.magenta
            case .effects: return Cyber.purple
            case .sync: return Cyber.cyan
            case .settings: return Cyber.yellow
            }
        }
        func title(_ l: L10n) -> String {
            switch self {
            case .color: return l.tabColor
            case .effects: return l.tabEffects
            case .sync: return l.tabSync
            case .settings: return l.tabSettings
            }
        }
    }

    var body: some View {
        let l = model.l10n
        VStack(spacing: 0) {
            header(l)
            Divider().overlay(Cyber.cyan.opacity(0.4))
            HStack(spacing: 0) {
                sidebar(l)
                Divider().overlay(Cyber.purple.opacity(0.4))
                detail(l)
            }
            Divider().overlay(Cyber.cyan.opacity(0.4))
            footer(l)
        }
        .background(Cyber.bgGradient.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
    }

    // MARK: Header
    private func header(_ l: L10n) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Cyber.cyan.opacity(0.15)).frame(width: 40, height: 40)
                Image(systemName: "bolt.fill")
                    .font(.system(size: 20, weight: .black))
                    .neonText(model.isConnected ? Cyber.cyan : Cyber.textDim, radius: 8)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(l.appTitle.uppercased())
                    .font(.system(.title2, design: .monospaced).weight(.black))
                    .tracking(3)
                    .neonText(Cyber.cyan, radius: 10)
                Text(l.armNotice)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Cyber.textDim)
            }
            Spacer()

            // Light selector — chooses which light all pages edit. Only shown
            // when 2+ lights are connected; single-light behaves as before.
            let connectedLights = model.devices.filter { $0.isConnected }
            if connectedLights.count > 1 {
                HStack(spacing: 6) {
                    Image(systemName: "lightbulb.2")
                        .foregroundStyle(Cyber.cyan)
                    CyberDropdown(
                        options: connectedLights.map { $0.id },
                        title: { id in
                            connectedLights.first(where: { $0.id == id })?.displayName ?? l.activeLight
                        },
                        selection: Binding(
                            get: { model.selectedDevice?.id ?? connectedLights[0].id },
                            set: { id in
                                if let d = model.devices.first(where: { $0.id == id }) { model.select(d) }
                            }
                        ),
                        accent: Cyber.cyan,
                        width: 150
                    )
                }
                .padding(.horizontal, 10).padding(.vertical, 4)
                .cyberPanel(corner: 8, border: Cyber.cyan, glow: 6)
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(model.isConnected ? Cyber.green : Cyber.red)
                    .frame(width: 9, height: 9)
                    .shadow(color: (model.isConnected ? Cyber.green : Cyber.red).opacity(0.9), radius: 6)
                Text(model.isConnected ? l.connected : l.notConnected)
                    .font(.system(.callout, design: .monospaced).weight(.semibold))
                    .foregroundStyle(Cyber.text)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .cyberPanel(corner: 8, border: model.isConnected ? Cyber.green : Cyber.red, glow: 6)

            Button(model.isConnected ? l.disconnectAll : l.connect) {
                if model.isConnected { model.disconnect() } else { model.connectAll() }
            }
            .buttonStyle(CyberButtonStyle(color: model.isConnected ? Cyber.magenta : Cyber.cyan, prominent: true))
        }
        .padding(16)
        .background(Cyber.bgDeep.opacity(0.6))
    }

    // MARK: Sidebar
    private func sidebar(_ l: L10n) -> some View {
        VStack(spacing: 8) {
            ForEach(Tab.allCases) { t in
                let selected = (tab == t)
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { tab = t }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: t.icon)
                            .frame(width: 22)
                            .foregroundStyle(selected ? t.accent : Cyber.textDim)
                            .shadow(color: selected ? t.accent : .clear, radius: 6)
                        Text(t.title(l).uppercased())
                            .font(.system(.callout, design: .monospaced).weight(.bold))
                            .tracking(1)
                            .foregroundStyle(selected ? Cyber.text : Cyber.textDim)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(selected ? t.accent.opacity(0.12) : Color.clear)
                    )
                    .overlay(alignment: .leading) {
                        if selected {
                            Rectangle()
                                .fill(t.accent)
                                .frame(width: 3)
                                .shadow(color: t.accent, radius: 6)
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(selected ? t.accent.opacity(0.7) : Color.clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(12)
        .frame(width: 210)
        .background(Cyber.bgDeep.opacity(0.5))
    }

    // MARK: Detail
    @ViewBuilder
    private func detail(_ l: L10n) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                switch tab {
                case .color: ColorPage()
                case .effects: EffectsPage()
                case .sync: SyncPage()
                case .settings: SettingsPage()
                }
            }
            .padding(26)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Footer
    private func footer(_ l: L10n) -> some View {
        HStack {
            if !model.statusText.isEmpty {
                Text(model.statusText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Cyber.cyan.opacity(0.8))
            }
            Spacer()
            let connectedCount = model.devices.filter { $0.isConnected }.count
            if connectedCount > 1 {
                Text("\(l.lights): \(connectedCount)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Cyber.textDim)
                Text("//").font(.system(.caption, design: .monospaced)).foregroundStyle(Cyber.textDim)
            }
            Text("\(l.firmware): \(model.firmware)  //  \(l.leds): \(model.ledCount)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Cyber.textDim)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Cyber.bgDeep.opacity(0.6))
    }
}
