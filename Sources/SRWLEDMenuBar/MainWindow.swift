import AppKit
import SwiftUI
import SRWLEDVisuals
import SRWLEDCore

/// Главное окно: объёмная визуализация во всю площадь и панель управления справа.
struct MainWindow: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HSplitView {
            stage
                .frame(minWidth: 460)
            sidebar
                .frame(minWidth: 300, idealWidth: 320, maxWidth: 380)
        }
        .frame(minWidth: 820, minHeight: 540)
        .environment(\.layoutDirection, model.language.isRightToLeft ? .rightToLeft : .leftToRight)
    }

    // MARK: Сцена

    private var stage: some View {
        ZStack {
            Group {
                switch model.sceneStyle {
                case .crown:
                    CrownScene(sampler: { model.sampleBands() },
                               isRunning: model.isRunning,
                               palette: model.palette)
                case .neon:
                    NeonScene(sampler: { model.sampleBands() },
                              isRunning: model.isRunning,
                              palette: model.palette,
                              showsWordmark: false)
                case .ring:
                    RingScene(sampler: { model.sampleBands() },
                              isRunning: model.isRunning,
                              palette: model.palette)
                case .sphere:
                    WireScene(sampler: { model.sampleBands() },
                              isRunning: model.isRunning,
                              palette: model.palette)
                }
            }
                .ignoresSafeArea()

            VStack {
                stageHeader
                Spacer()
                if !model.isRunning { stagePrompt }
            }
            .padding(22)
        }
    }

    /// Состояние поверх свечения — крупно и без рамок, чтобы не спорить с картинкой.
    private var stageHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.localized(model.stateKey))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.55), radius: 12, y: 2)

                Text(model.isRunning ? model.sourceDescription : model.localized(.captureStopped))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.7))
                    .shadow(color: .black.opacity(0.6), radius: 8)
            }

            Spacer()

            if model.isRunning {
                HStack(spacing: 18) {
                    stageCounter("\(model.packetsPerSecond)", model.localized(.packetsPerSecond))
                    stageCounter("\(model.totalPackets)", model.localized(.totalPackets))
                }
            }
        }
    }

    private func stageCounter(_ value: String, _ label: String) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(value)
                .font(.system(size: 19, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.6))
        }
        .shadow(color: .black.opacity(0.55), radius: 10)
    }

    private var stagePrompt: some View {
        Button {
            model.start()
        } label: {
            Label(model.localized(.start), systemImage: "play.fill")
                .font(.system(size: 14, weight: .medium))
                .padding(.horizontal, 22)
                .padding(.vertical, 11)
                .background(.white.opacity(0.16), in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.28), lineWidth: 1))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.4), radius: 14, y: 4)
    }

    // MARK: Панель

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                controls

                if model.isFirstRun { welcomeBlock }
                if case .noSignal = model.state { permissionBlock }

                devicesSection
                destinationSection
                diagnosticsSection
                behaviourSection

                if let reason = model.lastRestartReason {
                    Label("\(model.localized(.captureRestarted)): \(reason)",
                          systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(18)
        }
    }

    private var controls: some View {
        HStack {
            Button(model.localized(model.isRunning ? .stop : .start)) {
                model.isRunning ? model.stop() : model.start()
            }
            .controlSize(.large)
            .keyboardShortcut(.return)

            Spacer()

            Picker("", selection: $model.language) {
                ForEach(Language.allCases) { language in
                    Text(language.nativeName).tag(language)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 128)
        }
    }

    private var devicesSection: some View {
        section(model.localized(.devices)) {
            if model.discoveredDevices.isEmpty {
                Text(model.localized(model.isSearching ? .searchingDevices : .noDevicesFound))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.discoveredDevices) { device in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(deviceColour(device))
                            .frame(width: 7, height: 7)
                            .padding(.top, 4)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(device.name).font(.system(size: 11, weight: .medium))
                            Text("\(device.host) · \(deviceStatusText(device))")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
                Button(model.localized(.useFound)) { model.useDiscoveredDevices() }
                    .font(.system(size: 11))
            }

            HStack {
                Button(model.localized(model.isSearching ? .refresh : .searchDevices)) {
                    model.isSearching ? model.refreshDeviceStatuses() : model.startDiscovery()
                }
                .font(.system(size: 11))
            }
        }
    }

    private func deviceColour(_ device: DiscoveredDevice) -> Color {
        guard let status = device.status else { return .secondary }
        if status.isReceivingFromUs { return .green }
        switch status.syncState {
        case .idle: return .orange
        case .disabled, .noUsermod, .sending: return .red
        default: return .secondary
        }
    }

    private func deviceStatusText(_ device: DiscoveredDevice) -> String {
        guard let status = device.status else { return model.localized(.deviceUnknown) }
        if status.isReceivingFromUs { return model.localized(.deviceReceiving) }
        if status.syncState == .idle { return model.localized(.deviceIdle) }
        return status.syncState.rawValue
    }

    private var destinationSection: some View {
        section(model.localized(.whereToSend)) {
            Picker("", selection: $model.sendMode) {
                Text(model.localized(.modeTargetList)).tag(Settings.SendMode.targetIPList)
                Text(model.localized(.modeBroadcastLAN)).tag(Settings.SendMode.broadcastLAN)
                Text(model.localized(.modeBroadcastSubnet)).tag(Settings.SendMode.broadcastSubnet)
                Text(model.localized(.modeMulticast)).tag(Settings.SendMode.multicast)
            }
            .labelsHidden()
            .pickerStyle(.menu)

            if model.sendMode == .targetIPList || model.sendMode == .broadcastSubnet {
                TextField(model.localized(.targetsPlaceholder), text: $model.targets)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Text(model.localized(.port))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                TextField("11988", value: $model.port, format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .monospacedDigit()
            }

            if model.isRunning {
                Text(model.destinationDescription)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private var diagnosticsSection: some View {
        section(model.localized(.diagnostics)) {
            if model.diagnostics.lines.isEmpty {
                Text(model.localized(.diagAppearsAfterStart))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(model.diagnostics.lines.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(colour(for: line.verdict))
                            .frame(width: 7, height: 7)
                            .padding(.top, 4)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(line.title).font(.system(size: 11, weight: .medium))
                            Text(line.detail)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if !line.advice.isEmpty {
                                Text(line.advice)
                                    .font(.system(size: 10))
                                    .foregroundStyle(colour(for: line.verdict))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
                Button(model.localized(.copy)) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.diagnostics.asText(), forType: .string)
                }
                .font(.system(size: 11))
            }
        }
    }

    private var behaviourSection: some View {
        section(model.localized(.behaviour)) {
            Toggle(model.localized(.launchAtLogin), isOn: $model.launchAtLogin)
                .font(.system(size: 11))
            if let problem = model.loginItemProblem {
                Text(problem)
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Picker("", selection: $model.sceneStyle) {
                ForEach(SceneStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            Picker("", selection: $model.palette) {
                ForEach(Palette.allCases) { palette in
                    Text(palette.title).tag(palette)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            Toggle(model.localized(.spectrumInMenuBar), isOn: $model.showSpectrumInMenuBar)
                .font(.system(size: 11))
            Toggle(model.localized(.originalBehaviour), isOn: $model.useOriginalBehaviour)
                .font(.system(size: 11))
            Text(model.localized(.originalBehaviourNote))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(model.localized(.applyRestart)) { model.restart() }
                .disabled(!model.isRunning)
                .font(.system(size: 11))
        }
    }

    // MARK: Блоки-подсказки

    private var welcomeBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.localized(.welcomeTitle))
                .font(.system(size: 13, weight: .semibold))
            Text(model.localized(.welcomeBody))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(11)
        .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    private var permissionBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.localized(.permissionTitle))
                .font(.system(size: 12, weight: .medium))
            Text(model.localized(.permissionBody))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(model.localized(.openPrivacy)) {
                let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")!
                NSWorkspace.shared.open(url)
            }
            .font(.system(size: 11))
        }
        .padding(11)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Мелочи

    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .kerning(0.6)
            content()
        }
    }

    private func colour(for verdict: Diagnostics.Verdict) -> Color {
        switch verdict {
        case .ok: return .green
        case .warning: return .orange
        case .failure: return .red
        case .unknown: return .secondary
        }
    }
}
