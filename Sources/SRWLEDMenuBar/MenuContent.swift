import AppKit
import SwiftUI
import SRWLEDVisuals
import SRWLEDCore

struct MenuContent: View {
    @ObservedObject var model: AppModel
    @State private var showingSettings = false
    @State private var showingDiagnostics = false

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.isFirstRun {
                welcome
            }

            header

            SpectrumStrip(bands: model.bands)
                .frame(height: 46)
                .opacity(model.isRunning ? 1 : 0.25)

            if case .noSignal = model.state {
                permissionHint
            }
            if case .failed = model.state {
                failureHint
            }

            if let reason = model.lastRestartReason {
                Label(restartNote(reason), systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
            details
            Divider()
            controls
        }
        .padding(14)
        .frame(width: 300)
    }

    /// Содержимое в прокрутке: попап раньше был прибит к 420 точкам по высоте,
    /// а с раскрытыми настройками и диагностикой содержимое переваливает за 700 —
    /// нижняя часть, вместе с кнопкой «применить», просто срезалась. Прокрутка
    /// включается сама и только когда содержимое не поместилось.
    var body: some View {
        ScrollView(.vertical) {
            content
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: 300)
        .frame(maxHeight: 620)
        // Направление письма — снаружи прокрутки: иначе в арабском и урду
        // зеркалится содержимое, а полоса прокрутки остаётся справа.
        .environment(\.layoutDirection, model.language.isRightToLeft ? .rightToLeft : .leftToRight)
    }

    /// «Захват пересобран: сменилось устройство вывода: AirPods → Динамики».
    /// Подробность приходит из ядра и не переводится — это имена и числа.
    private func restartNote(_ reason: S) -> String {
        let head = "\(model.localized(.captureRestarted)): \(model.localized(reason))"
        return model.lastRestartDetail.isEmpty ? head : "\(head): \(model.lastRestartDetail)"
    }

    // MARK: Части

    /// Экран первого запуска: объясняем, что попросим и зачем, до системных диалогов.
    private var welcome: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(model.localized(.welcomeTitle))
                .font(.system(size: 13, weight: .semibold))
            Text(model.localized(.welcomeIntro))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(model.localized(.welcomeBody))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(model.localized(.welcomeAction))
                .font(.system(size: 11, weight: .medium))
        }
        .padding(10)
        .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: model.state.symbol)
                .foregroundStyle(statusColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.localized(model.stateKey))
                    .font(.system(size: 13, weight: .semibold))
                if model.isRunning {
                    Text("\(model.packetsPerSecond) \(model.localized(.packetsPerSecond))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Spacer()
        }
    }

    private var statusColor: Color {
        switch model.state {
        case .playing: return .green
        case .silent: return .secondary
        case .noSignal: return .orange
        case .failed: return .red
        case .stopped: return .secondary
        }
    }

    private var permissionHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.localized(.permissionTitle))
                .font(.system(size: 11, weight: .medium))
            Text(model.localized(.permissionBody))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Button(model.localized(.openPrivacy)) {
                let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")!
                NSWorkspace.shared.open(url)
            }
            .font(.system(size: 11))
        }
        .padding(9)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
    }

    /// Отказ: причина на языке интерфейса, под ней — текст системной ошибки как есть.
    private var failureHint: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(model.localized(model.stateKey))
                .font(.system(size: 11, weight: .medium))
            if !model.stateDetail.isEmpty {
                Text(model.stateDetail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 5) {
            if model.isRunning {
                detailRow(model.localized(.source), model.sourceDescription)
                detailRow(model.localized(.destination), model.destinationDescription)
                detailRow(model.localized(.totalPackets), "\(model.totalPackets)")
            } else {
                detailRow(model.localized(.destination), destinationPreview)
            }
            detailRow(model.localized(.processing),
                      model.localized(model.useOriginalBehaviour ? .processingOriginal : .processingFixed))
        }
    }

    private var destinationPreview: String {
        let endpoints = PacketSender.resolveEndpoints(settings: model.buildSettings())
        return endpoints.isEmpty
            ? model.localized(.notSet)
            : endpoints.map(\.description).joined(separator: ", ")
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
            Text(value)
                .font(.system(size: 11))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            // Пуск отдельной строкой во всю ширину, а не в ряд с остальными.
            // В ряду из трёх кнопок надписи не помещались: по замеру немецкий
            // ряд требовал 347 pt при 272 доступных, и так в восьми языках
            // из шестнадцати. Главное действие к тому же заслуживает своей строки.
            HStack(spacing: 8) {
                Button(model.localized(model.isRunning ? .stop : .start)) {
                    model.isRunning ? model.stop() : model.start()
                }
                // Cmd-Return, а не голый Return: рядом два текстовых поля,
                // а голый Return делает кнопку кнопкой по умолчанию — и запуск
                // случался бы при вводе адреса ленты.
                .keyboardShortcut(.return, modifiers: .command)
                .frame(maxWidth: .infinity)

                Button(model.localized(.quit)) {
                    model.stop()
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }

            // Раскрывашки называют раздел, а не действие: у кнопки со стрелкой
            // состояние несёт стрелка. Прежние «Скрыть настройки» и «Скрыть
            // диагностику» были ещё и самыми длинными строками во всей таблице.
            HStack(spacing: 8) {
                disclosure(.settings, open: showingSettings) {
                    withAnimation(.easeInOut(duration: 0.15)) { showingSettings.toggle() }
                }
                disclosure(.diagnostics, open: showingDiagnostics) {
                    withAnimation(.easeInOut(duration: 0.15)) { showingDiagnostics.toggle() }
                }
                Spacer(minLength: 0)
            }

            if showingDiagnostics {
                DiagnosticsPane(model: model)
            }

            if showingSettings {
                SettingsPane(model: model)
            }
        }
    }

    /// Кнопка-раскрывашка: стрелка показывает состояние, подпись называет раздел.
    private func disclosure(_ key: S, open: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .rotationEffect(.degrees(open ? 90 : 0))
                Text(model.localized(key))
            }
            .font(.system(size: 11))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverFill(cornerRadius: 6)
        .animation(.easeOut(duration: 0.15), value: open)
    }
}

// MARK: - Диагностика

struct DiagnosticsPane: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(model.diagnostics.lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .top, spacing: 7) {
                    Circle()
                        .fill(color(for: line.verdict))
                        .frame(width: 7, height: 7)
                        .padding(.top, 4)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(line.title)
                            .font(.system(size: 11, weight: .medium))
                        Text(line.detail)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if !line.advice.isEmpty {
                            Text(line.advice)
                                .font(.system(size: 10))
                                .foregroundStyle(color(for: line.verdict))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }

            Button(model.localized(.copyDiagnostics)) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(model.diagnostics.asText(language: model.language), forType: .string)
            }
            .font(.system(size: 11))
        }
        .padding(9)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
    }

    private func color(for verdict: Diagnostics.Verdict) -> Color {
        switch verdict {
        case .ok: return .green
        case .warning: return .orange
        case .failure: return .red
        case .unknown: return .secondary
        }
    }
}

// MARK: - Настройки

struct SettingsPane: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Picker(model.localized(.sendMode), selection: $model.sendMode) {
                Text(model.localized(.modeTargetList)).tag(Settings.SendMode.targetIPList)
                Text(model.localized(.modeBroadcastLAN)).tag(Settings.SendMode.broadcastLAN)
                Text(model.localized(.modeBroadcastSubnet)).tag(Settings.SendMode.broadcastSubnet)
                Text(model.localized(.modeMulticast)).tag(Settings.SendMode.multicast)
            }
            .pickerStyle(.menu)

            if model.sendMode == .targetIPList || model.sendMode == .broadcastSubnet {
                VStack(alignment: .leading, spacing: 3) {
                    TextField(model.localized(.targetsPlaceholder), text: $model.targets)
                        .textFieldStyle(.roundedBorder)
                    Text(model.localized(.targetsNote))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Text(model.localized(.port)).font(.system(size: 11))
                TextField("11988", value: $model.port, format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                    .monospacedDigit()
            }

            Toggle(model.localized(.spectrumInMenuBar), isOn: $model.showSpectrumInMenuBar)
                .font(.system(size: 11))

            Toggle(model.localized(.launchAtLogin), isOn: $model.launchAtLogin)
                .font(.system(size: 11))
            if let problem = model.loginItemProblem {
                Text(problem)
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Toggle(model.localized(.originalBehaviour), isOn: $model.useOriginalBehaviour)
                .font(.system(size: 11))
            Text(model.localized(.originalBehaviourNote))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            Button(model.localized(.applyRestart)) {
                model.restart()
            }
            .disabled(!model.isRunning)
            .font(.system(size: 11))
        }
        .padding(.top, 2)
    }
}
