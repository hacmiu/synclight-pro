import SwiftUI

// MARK: - Active-light context label (per-light pages)

/// Small "editing: <light>" caption shown at the top of the Color / Effects /
/// Settings pages when more than one light is connected. The actual light
/// SELECTION lives in the window header dropdown (see ContentView); this is just
/// an in-page reminder of which light the controls below apply to.
struct LightPicker: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let l = model.l10n
        let connected = model.devices.filter { $0.isConnected }
        if connected.count > 1, let device = model.selectedDevice {
            HStack(spacing: 8) {
                Image(systemName: "lightbulb.2").foregroundStyle(Cyber.cyan)
                Text(l.activeLight)
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(Cyber.textDim)
                HStack(spacing: 6) {
                    Circle().fill(Cyber.green).frame(width: 7, height: 7)
                    Text(device.displayName)
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                        .foregroundStyle(Cyber.cyan)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(Cyber.cyan.opacity(0.12)))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Cyber.cyan.opacity(0.6), lineWidth: 1))
                Spacer()
            }
        }
    }
}

// MARK: - Color page
struct ColorPage: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let l = model.l10n
        let device = model.selectedDevice
        VStack(alignment: .leading, spacing: 20) {
            CyberSectionTitle(text: l.tabColor, color: Cyber.magenta)
            LightPicker()

            if let device = device {
                // Current color swatch — clicking it opens the system color palette.
                HStack(spacing: 16) {
                    ColorSwatchButton(
                        color: NSColor(device.color).usingColorSpace(.deviceRGB) ?? .blue,
                        onChange: { ns in
                            model.setColor(Color(nsColor: ns))
                        }
                    ) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(device.color)
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
                        Text(device.color.hexString)
                            .font(.system(.title3, design: .monospaced).weight(.bold))
                            .neonText(Cyber.magenta, radius: 6)
                        Text("\(l.brightness): \(Int(device.brightness))%")
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
                        Text("\(Int(device.hue * 360))°").font(.system(.callout, design: .monospaced)).foregroundStyle(Cyber.cyan)
                    }
                    HueSlider(hue: Binding(
                        get: { device.hue },
                        set: { model.setHue($0) }
                    ))
                }

                // Saturation slider — gradient from white (0) to full colour (1).
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "circle.lefthalf.filled").foregroundStyle(Cyber.purple)
                        Text(l.saturation).font(.system(.callout, design: .monospaced).weight(.semibold)).foregroundStyle(Cyber.text)
                        Spacer()
                        Text("\(Int(device.saturation * 100))%").font(.system(.callout, design: .monospaced)).foregroundStyle(Cyber.cyan)
                    }
                    GradientSlider(
                        value: Binding(
                            get: { device.saturation },
                            set: { model.setSaturation($0) }
                        ),
                        colors: [
                            Color(hue: device.hue, saturation: 0, brightness: 1),
                            Color(hue: device.hue, saturation: 1, brightness: 1)
                        ],
                        thumbColor: Color(hue: device.hue, saturation: device.saturation, brightness: 1)
                    )
                }

                Divider().overlay(Cyber.magenta.opacity(0.3))

                // Brightness
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "sun.max").foregroundStyle(Cyber.yellow)
                        Text(l.brightness).font(.system(.callout, design: .monospaced).weight(.semibold)).foregroundStyle(Cyber.text)
                        Spacer()
                        Text("\(Int(device.brightness))%").font(.system(.callout, design: .monospaced)).foregroundStyle(Cyber.cyan)
                    }
                    Slider(value: Binding(
                        get: { device.brightness },
                        set: { model.setBrightness($0) }
                    ), in: 0...100).tint(Cyber.yellow)
                }
            } else {
                Text(l.noLights).font(.system(.callout, design: .monospaced)).foregroundStyle(Cyber.textDim)
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
        let device = model.selectedDevice
        VStack(alignment: .leading, spacing: 20) {
            CyberSectionTitle(text: l.tabEffects, color: Cyber.purple)
            LightPicker()

            // Mode switch: dynamic (type 2) vs sound-pickup (type 3).
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
                    .disabled(device == nil)
                }
            }

            Divider().overlay(Cyber.purple.opacity(0.3))

            if let device = device {
                // Speed only affects colour effects; sound-pickup follows the audio.
                if group == .dynamic {
                    sliderRow(icon: "speedometer", title: l.dynamicSpeed, value: Binding(
                        get: { device.dynamicSpeed },
                        set: { model.setDynamicSpeed($0) }
                    ), range: 5...100)
                }

                // Sound sensitivity only matters for the sound-pickup group.
                if group == .pickup {
                    sliderRow(icon: "ear", title: l.soundSensitivity, value: Binding(
                        get: { device.soundSensitivity },
                        set: { model.setSoundSensitivity($0) }
                    ), range: 5...100)
                }

                // Brightness works while an effect runs (the driver re-issues the
                // effect frame so the device commits the new level).
                sliderRow(icon: "sun.max", title: l.brightness, value: Binding(
                    get: { device.brightness },
                    set: { model.setBrightness($0) }
                ), range: 0...100, unit: "%", tint: Cyber.yellow)
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

    private func sliderRow(icon: String, title: String, value: Binding<Double>, range: ClosedRange<Double>,
                           unit: String = "", tint: Color = Cyber.cyan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon).foregroundStyle(tint)
                Text(title).font(.system(.callout, design: .monospaced).weight(.semibold)).foregroundStyle(Cyber.text)
                Spacer()
                Text("\(Int(value.wrappedValue))\(unit)").font(.system(.callout, design: .monospaced)).foregroundStyle(tint)
            }
            Slider(value: value, in: range)
                .tint(tint)
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

            // Screen-sync toggle for the SELECTED light. Each light mirrors its
            // own display independently; other lights keep their own state.
            let selected = model.selectedDevice
            Toggle(isOn: Binding(
                get: { selected?.syncEnabled ?? false },
                set: { on in model.setSync(on) }
            )) {
                HStack(spacing: 8) {
                    Text(l.syncOn)
                        .font(.system(.callout, design: .monospaced).weight(.bold))
                        .foregroundStyle(Cyber.text)
                    if let d = selected, model.devices.filter({ $0.isConnected }).count > 1 {
                        Text("· \(d.displayName)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(Cyber.cyan)
                    }
                }
            }
            .toggleStyle(.switch)
            .tint(Cyber.cyan)
            .disabled(selected == nil)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "gauge").foregroundStyle(Cyber.cyan)
                    Text(l.samplingFPS).font(.system(.callout, design: .monospaced).weight(.semibold)).foregroundStyle(Cyber.text)
                    Spacer()
                    Text("\(Int(model.syncFPS)) fps").font(.system(.callout, design: .monospaced)).foregroundStyle(Cyber.cyan)
                }
                Slider(value: $model.syncFPS, in: 5...60, step: 1).tint(Cyber.cyan)
            }

            Divider().overlay(Cyber.cyan.opacity(0.3))

            // Per-light cards: bind each light to a monitor + strip direction.
            let connected = model.devices.filter { $0.isConnected }
            if connected.isEmpty {
                Text(l.noLights).font(.system(.callout, design: .monospaced)).foregroundStyle(Cyber.textDim)
            } else {
                Text(l.displayOfAll)
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(Cyber.textDim)
                ForEach(connected) { device in
                    LightCard(device: device)
                }
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

/// One card per connected light in the Sync page: display binding + strip
/// direction + connect/disconnect. Takes the `LightDevice` directly so its
/// controls survive the per-frame `objectWillChange` republishes.
struct LightCard: View {
    @EnvironmentObject var model: AppModel
    let device: LightDevice

    var body: some View {
        let l = model.l10n
        let displays = AppModel.availableDisplays()
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Circle().fill(Cyber.green).frame(width: 9, height: 9)
                    .shadow(color: Cyber.green.opacity(0.8), radius: 5)
                Text(device.displayName)
                    .font(.system(.callout, design: .monospaced).weight(.bold))
                    .foregroundStyle(Cyber.text)
                Text("\(l.leds): \(device.ledCount)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Cyber.textDim)
                Spacer()
                // Per-light screen-sync switch.
                Toggle("", isOn: Binding(
                    get: { device.syncEnabled },
                    set: { on in model.setSync(on, for: device) }
                )).labelsHidden().tint(Cyber.cyan)
                Button(l.disconnect) { model.disconnect(device) }
                    .buttonStyle(CyberButtonStyle(color: Cyber.magenta))
            }

            HStack {
                Image(systemName: "display").foregroundStyle(Cyber.cyan)
                Text(l.display).font(.system(.caption, design: .monospaced).weight(.semibold)).foregroundStyle(Cyber.text)
                Spacer()
                if displays.count > 1 {
                    CyberDropdown(
                        options: displays.map { $0.id },
                        title: { id in displays.first(where: { $0.id == id })?.name ?? l.mainDisplay },
                        selection: Binding(
                            get: { device.displayID ?? CGMainDisplayID() },
                            set: { model.setDisplay($0 == CGMainDisplayID() ? nil : $0, for: device) }
                        ),
                        accent: Cyber.cyan,
                        width: 220
                    )
                } else {
                    Text(l.mainDisplay).font(.system(.caption, design: .monospaced)).foregroundStyle(Cyber.cyan)
                }
            }

            HStack {
                Image(systemName: "arrow.left.arrow.right").foregroundStyle(Cyber.magenta)
                Text(l.direction).font(.system(.caption, design: .monospaced).weight(.semibold)).foregroundStyle(Cyber.text)
                Spacer()
                CyberSegmented(options: [0, 1],
                               title: { $0 == 0 ? l.leftToRight : l.rightToLeft },
                               selection: Binding(
                                   get: { device.installationMethod },
                                   set: { device.installationMethod = $0; device.mirrorBox.value = ($0 == 1); model.persist(device) }
                               ),
                               accent: Cyber.magenta,
                               width: 240)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Cyber.panel.opacity(0.8)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Cyber.cyan.opacity(0.4), lineWidth: 1))
    }
}

// MARK: - Settings page
struct SettingsPage: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let l = model.l10n
        let device = model.selectedDevice
        VStack(alignment: .leading, spacing: 20) {
            CyberSectionTitle(text: l.tabSettings, color: Cyber.yellow)
            LightPicker()

            // Language (global)
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

            // Auto off — per selected light
            HStack {
                Image(systemName: "clock").foregroundStyle(Cyber.yellow)
                Text(l.autoOff).font(.system(.callout, design: .monospaced).weight(.semibold)).foregroundStyle(Cyber.text)
                Spacer()
                if let device = device {
                    Toggle("", isOn: Binding(
                        get: { device.autoOffEnabled },
                        set: { device.autoOffEnabled = $0; model.applyAutoOff() }
                    )).labelsHidden().tint(Cyber.yellow)
                }
            }
            if let device = device {
                HStack {
                    Text("\(Int(device.autoOffMinutes)) \(l.minutes)").font(.system(.callout, design: .monospaced)).foregroundStyle(Cyber.cyan)
                    Slider(value: Binding(
                        get: { device.autoOffMinutes },
                        set: { device.autoOffMinutes = $0 }
                    ), in: 5...120, step: 5).tint(Cyber.yellow)
                    Button(l.apply) { model.applyAutoOff() }
                        .buttonStyle(CyberButtonStyle(color: Cyber.yellow))
                }
            }

            Divider().overlay(Cyber.yellow.opacity(0.25))

            // USB Power Optimization (global)
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
                Text("\(l.version) 1.1").font(.system(.caption, design: .monospaced)).foregroundStyle(Cyber.textDim)
            }
        }
    }
}
