import SwiftUI

// MARK: - Color page
struct ColorPage: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let l = model.l10n
        VStack(alignment: .leading, spacing: 20) {
            CyberSectionTitle(text: l.tabColor, color: Cyber.magenta)

            // Current color swatch — clicking it opens the system color palette.
            HStack(spacing: 16) {
                ColorSwatchButton(
                    color: NSColor(model.color).usingColorSpace(.deviceRGB) ?? .blue,
                    onChange: { ns in
                        model.setColor(Color(nsColor: ns))
                    }
                ) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(model.color)
                        .frame(width: 80, height: 80)
                        .shadow(radius: 4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(.white.opacity(0.3), lineWidth: 1)
                        )
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "eyedropper")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(6)
                                .background(Circle().fill(.black.opacity(0.45)))
                                .padding(6)
                        }
                }
                .frame(width: 80, height: 80)
                .help(l.pickColor)

                VStack(alignment: .leading, spacing: 6) {
                    Text(l.pickColor)
                        .font(.system(.headline, design: .monospaced).weight(.bold))
                        .foregroundStyle(Cyber.text)
                    Text(model.color.hexString)
                        .font(.system(.title3, design: .monospaced).weight(.bold))
                        .neonText(Cyber.magenta, radius: 6)
                    Text("\(l.brightness): \(Int(model.brightness))%")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Cyber.textDim)
                }
                Spacer()
            }

            Divider().overlay(Cyber.magenta.opacity(0.3))

            // Hue slider (rainbow bar) — mirrors the original app's AlphaPicker
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "paintpalette").foregroundStyle(Cyber.magenta)
                    Text(l.hue).font(.system(.callout, design: .monospaced).weight(.semibold)).foregroundStyle(Cyber.text)
                    Spacer()
                    Text("\(Int(model.hue * 360))°").font(.system(.callout, design: .monospaced)).foregroundStyle(Cyber.cyan)
                }
                HueSlider(hue: Binding(
                    get: { model.hue },
                    set: { model.hue = $0 }
                ), onChange: { model.applyColor() })
            }

            // Saturation slider — gradient from white (0) to full colour (1) at
            // the current hue, so pastel / desaturated colours can be picked.
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "circle.lefthalf.filled").foregroundStyle(Cyber.purple)
                    Text(l.saturation).font(.system(.callout, design: .monospaced).weight(.semibold)).foregroundStyle(Cyber.text)
                    Spacer()
                    Text("\(Int(model.saturation * 100))%").font(.system(.callout, design: .monospaced)).foregroundStyle(Cyber.cyan)
                }
                GradientSlider(
                    value: Binding(
                        get: { model.saturation },
                        set: { model.saturation = $0 }
                    ),
                    colors: [
                        Color(hue: model.hue, saturation: 0, brightness: 1),
                        Color(hue: model.hue, saturation: 1, brightness: 1)
                    ],
                    thumbColor: Color(hue: model.hue, saturation: model.saturation, brightness: 1),
                    onChange: { model.applyColor() }
                )
            }

            Divider().overlay(Cyber.magenta.opacity(0.3))

            // Brightness
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "sun.max").foregroundStyle(Cyber.yellow)
                    Text(l.brightness).font(.system(.callout, design: .monospaced).weight(.semibold)).foregroundStyle(Cyber.text)
                    Spacer()
                    Text("\(Int(model.brightness))%").font(.system(.callout, design: .monospaced)).foregroundStyle(Cyber.cyan)
                }
                Slider(value: Binding(
                    get: { model.brightness },
                    set: { model.brightness = $0; model.applyBrightness() }
                ), in: 0...100).tint(Cyber.yellow)
            }
        }
    }
}

// MARK: - Effects page
struct EffectsPage: View {
    @EnvironmentObject var model: AppModel

    enum Group: String, CaseIterable, Identifiable {
        case dynamic   // type 2 — "幻彩"/fantasy effects (run on-device)
        case pickup    // type 3 — "拾音"/sound-pickup effects (need audio)
        var id: String { rawValue }
        func title(_ l: L10n) -> String {
            switch self {
            case .dynamic: return l.effectDynamic
            case .pickup: return l.effectPickup
            }
        }
        func subtitle(_ l: L10n) -> String {
            switch self {
            case .dynamic: return l.effectDynamicDesc
            case .pickup: return l.effectPickupDesc
            }
        }
        /// Protocol effect type (matches the original app's LedEffect IPC arg).
        var type: UInt8 { self == .dynamic ? 2 : 3 }
    }

    @State private var group: Group = .dynamic

    var body: some View {
        let l = model.l10n
        VStack(alignment: .leading, spacing: 20) {
            CyberSectionTitle(text: l.tabEffects, color: Cyber.purple)

            // Mode switch: dynamic (type 2) vs sound-pickup (type 3), matching
            // the original app's 幻彩/拾音 effect groups.
            CyberSegmented(options: Group.allCases,
                           title: { $0.title(l) },
                           selection: $group,
                           accent: Cyber.purple)

            Text(group.subtitle(l))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Cyber.textDim)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                ForEach(0..<7, id: \.self) { idx in
                    Button {
                        model.applyEffect(type: group.type, index: UInt8(idx))
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: icon(group, idx))
                                .font(.system(size: 26))
                                .foregroundStyle(Cyber.purple)
                                .shadow(color: Cyber.purple.opacity(0.8), radius: 8)
                            Text("\(group.title(l)) \(idx + 1)".uppercased())
                                .font(.system(.caption, design: .monospaced).weight(.bold))
                                .tracking(1)
                                .foregroundStyle(Cyber.text)
                        }
                        .frame(maxWidth: .infinity, minHeight: 84)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Cyber.panel.opacity(0.8))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(Cyber.purple.opacity(0.6), lineWidth: 1.2)
                        )
                        .shadow(color: Cyber.purple.opacity(0.35), radius: 10)
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider().overlay(Cyber.purple.opacity(0.3))

            // Speed only affects colour effects; sound-pickup follows the audio.
            if group == .dynamic {
                sliderRow(icon: "speedometer", title: l.dynamicSpeed, value: Binding(
                    get: { model.dynamicSpeed },
                    set: { model.dynamicSpeed = $0; model.applySpeed() }
                ), range: 5...100)
            }

            // Sound sensitivity only matters for the sound-pickup group.
            if group == .pickup {
                sliderRow(icon: "ear", title: l.soundSensitivity, value: Binding(
                    get: { model.soundSensitivity },
                    set: { model.soundSensitivity = $0; model.applySoundSensitivity() }
                ), range: 5...100)
            }
        }
    }

    private func icon(_ g: Group, _ idx: Int) -> String {
        if g == .pickup {
            return ["waveform", "music.note", "waveform.path", "speaker.wave.2",
                    "metronome", "dot.radiowaves.left.and.right", "bolt"][idx]
        }
        return ["rainbow", "wind", "waveform.path.ecg", "sparkles",
                "circle.hexagongrid", "bolt.fill", "star.fill"][idx]
    }

    private func sliderRow(icon: String, title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon).foregroundStyle(Cyber.cyan)
                Text(title).font(.system(.callout, design: .monospaced).weight(.semibold)).foregroundStyle(Cyber.text)
                Spacer()
                Text("\(Int(value.wrappedValue))").font(.system(.callout, design: .monospaced)).foregroundStyle(Cyber.cyan)
            }
            Slider(value: value, in: range)
                .tint(Cyber.cyan)
        }
    }
}

// MARK: - Sync page
struct SyncPage: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let l = model.l10n
        VStack(alignment: .leading, spacing: 20) {
            CyberSectionTitle(text: l.tabSync, color: Cyber.cyan)
            Text(l.syncDesc)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(Cyber.textDim)

            Toggle(isOn: Binding(
                get: { model.syncEnabled },
                set: { on in on ? model.startSync() : model.stopSync() }
            )) {
                Text(l.syncOn)
                    .font(.system(.callout, design: .monospaced).weight(.bold))
                    .foregroundStyle(Cyber.text)
            }
            .toggleStyle(.switch)
            .tint(Cyber.cyan)
            .disabled(!model.isConnected)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "gauge").foregroundStyle(Cyber.cyan)
                    Text(l.samplingFPS).font(.system(.callout, design: .monospaced).weight(.semibold)).foregroundStyle(Cyber.text)
                    Spacer()
                    Text("\(Int(model.syncFPS)) fps").font(.system(.callout, design: .monospaced)).foregroundStyle(Cyber.cyan)
                }
                Slider(value: $model.syncFPS, in: 5...60, step: 1).tint(Cyber.cyan)
            }

            // Target display: which monitor this strip should mirror. Lets
            // several lights each follow their own screen.
            let displays = AppModel.availableDisplays()
            if displays.count > 1 {
                HStack {
                    Image(systemName: "display").foregroundStyle(Cyber.cyan)
                    Text(l.display).font(.system(.callout, design: .monospaced).weight(.semibold)).foregroundStyle(Cyber.text)
                    Spacer()
                    CyberDropdown(
                        options: displays.map { $0.id },
                        title: { id in
                            displays.first(where: { $0.id == id })?.name ?? l.mainDisplay
                        },
                        selection: Binding(
                            get: { model.selectedDisplayID ?? CGMainDisplayID() },
                            set: { model.selectedDisplayID = ($0 == CGMainDisplayID()) ? nil : $0 }
                        ),
                        accent: Cyber.cyan,
                        width: 240
                    )
                }
            }

            // Strip direction (mirrors the original app's installation method).
            HStack {
                Image(systemName: "arrow.left.arrow.right").foregroundStyle(Cyber.magenta)
                Text(l.direction).font(.system(.callout, design: .monospaced).weight(.semibold)).foregroundStyle(Cyber.text)
                Spacer()
                CyberSegmented(options: [0, 1],
                               title: { $0 == 0 ? l.leftToRight : l.rightToLeft },
                               selection: $model.installationMethod,
                               accent: Cyber.magenta,
                               width: 260)
            }

            Text(l.screenPermission)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Cyber.yellow)

            Button(l.permissionBtn) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(CyberButtonStyle(color: Cyber.yellow))
        }
    }
}

// MARK: - Settings page
struct SettingsPage: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let l = model.l10n
        VStack(alignment: .leading, spacing: 20) {
            CyberSectionTitle(text: l.tabSettings, color: Cyber.yellow)

            // Language
            HStack {
                Image(systemName: "globe").foregroundStyle(Cyber.yellow)
                Text(l.language).font(.system(.callout, design: .monospaced).weight(.semibold)).foregroundStyle(Cyber.text)
                Spacer()
                CyberDropdown(options: AppLanguage.allCases,
                              title: { $0.label },
                              selection: $model.language,
                              accent: Cyber.yellow,
                              width: 160)
            }

            Divider().overlay(Cyber.yellow.opacity(0.25))

            // Auto off
            HStack {
                Image(systemName: "clock").foregroundStyle(Cyber.yellow)
                Text(l.autoOff).font(.system(.callout, design: .monospaced).weight(.semibold)).foregroundStyle(Cyber.text)
                Spacer()
                Toggle("", isOn: $model.autoOffEnabled).labelsHidden().tint(Cyber.yellow)
            }
            HStack {
                Text("\(Int(model.autoOffMinutes)) \(l.minutes)").font(.system(.callout, design: .monospaced)).foregroundStyle(Cyber.cyan)
                Slider(value: $model.autoOffMinutes, in: 5...120, step: 5).tint(Cyber.yellow)
                Button(l.apply) { model.applyAutoOff() }
                    .buttonStyle(CyberButtonStyle(color: Cyber.yellow))
            }

            Divider().overlay(Cyber.yellow.opacity(0.25))

            // USB Power Optimization (mirrors the original isLightCompression).
            HStack {
                Image(systemName: "bolt.batteryblock").foregroundStyle(Cyber.cyan)
                VStack(alignment: .leading, spacing: 2) {
                    Text(l.usbPowerOpt).font(.system(.callout, design: .monospaced).weight(.semibold)).foregroundStyle(Cyber.text)
                    Text(l.usbPowerOptDesc).font(.system(.caption, design: .monospaced)).foregroundStyle(Cyber.textDim)
                }
                Spacer()
                Toggle("", isOn: $model.usbPowerOptimization).labelsHidden().tint(Cyber.cyan)
            }

            Divider().overlay(Cyber.yellow.opacity(0.25))

            // Start on boot (login item), menu-bar only.
            HStack {
                Image(systemName: "power").foregroundStyle(Cyber.magenta)
                VStack(alignment: .leading, spacing: 2) {
                    Text(l.startOnBoot).font(.system(.callout, design: .monospaced).weight(.semibold)).foregroundStyle(Cyber.text)
                    Text(l.startOnBootDesc).font(.system(.caption, design: .monospaced)).foregroundStyle(Cyber.textDim)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { model.startOnBoot },
                    set: { model.setStartOnBoot($0) }
                )).labelsHidden().tint(Cyber.magenta)
            }

            Divider().overlay(Cyber.yellow.opacity(0.25))

            // About
            HStack {
                Image(systemName: "info.circle").foregroundStyle(Cyber.textDim)
                Text(l.about).font(.system(.callout, design: .monospaced)).foregroundStyle(Cyber.text)
                Spacer()
                Text("\(l.version) 1.0.0").font(.system(.caption, design: .monospaced)).foregroundStyle(Cyber.textDim)
            }
        }
    }
}
