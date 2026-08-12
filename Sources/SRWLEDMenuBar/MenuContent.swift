import AppKit
import SwiftUI
import SRWLEDVisuals
import SRWLEDCore

struct MenuContent: View {
    @ObservedObject var model: AppModel
    @State private var showingSettings = false
    @State private var showingDiagnostics = false

    var body: some View {
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
            if case .failed(let message) = model.state {
                failureHint(message)
            }

            if let reason = model.lastRestartReason {
                Label("Захват пересобран: \(reason)", systemImage: "arrow.triangle.2.circlepath")
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

    // MARK: Части

    /// Экран первого запуска: объясняем, что попросим и зачем, до системных диалогов.
    private var welcome: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Спектр звука — на ленты")
                .font(.system(size: 13, weight: .semibold))
            Text("Программа слушает то, что играет на компьютере, разбирает на 16 полос "
                 + "и шлёт их по сети на ленты с WLED.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("При первом запуске система спросит два разрешения: на запись системного "
                 + "звука и на доступ в локальную сеть. Сам звук никуда не передаётся и "
                 + "не сохраняется — в сеть уходят только 44 байта спектра на кадр.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Проверь адреса лент в настройках и нажми «Запустить».")
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
                Text(model.state.title)
                    .font(.system(size: 13, weight: .semibold))
                if model.isRunning {
                    Text("\(model.packetsPerSecond) пакетов/с")
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
            Text("Звук читается, но в нём одни нули.")
                .font(.system(size: 11, weight: .medium))
            Text("Обычно это значит, что не выдано разрешение на запись системного звука.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Button("Открыть настройки приватности") {
                let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")!
                NSWorkspace.shared.open(url)
            }
            .font(.system(size: 11))
        }
        .padding(9)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
    }

    private func failureHint(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(9)
            .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 5) {
            if model.isRunning {
                detailRow("Источник", model.sourceDescription)
                detailRow("Отправка", model.destinationDescription)
                detailRow("Всего пакетов", "\(model.totalPackets)")
            } else {
                detailRow("Отправка", destinationPreview)
            }
            detailRow("Обработка", model.useOriginalBehaviour ? "как в оригинале" : "исправленная")
        }
    }

    private var destinationPreview: String {
        let endpoints = PacketSender.resolveEndpoints(settings: model.buildSettings())
        return endpoints.isEmpty ? "не задана" : endpoints.map(\.description).joined(separator: ", ")
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
            HStack {
                Button(model.isRunning ? "Остановить" : "Запустить") {
                    model.isRunning ? model.stop() : model.start()
                }
                .keyboardShortcut(.return)

                Button(showingSettings ? "Скрыть настройки" : "Настройки") {
                    withAnimation(.easeInOut(duration: 0.15)) { showingSettings.toggle() }
                }
                Spacer()
                Button("Выход") {
                    model.stop()
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }

            HStack {
                Button(showingDiagnostics ? "Скрыть диагностику" : "Диагностика") {
                    withAnimation(.easeInOut(duration: 0.15)) { showingDiagnostics.toggle() }
                }
                .font(.system(size: 11))
                Spacer()
            }

            if showingDiagnostics {
                DiagnosticsPane(model: model)
            }

            if showingSettings {
                SettingsPane(model: model)
            }
        }
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

            Button("Скопировать диагностику") {
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
            Picker("Режим", selection: $model.sendMode) {
                Text("Списком адресов").tag(Settings.SendMode.targetIPList)
                Text("Broadcast по сети").tag(Settings.SendMode.broadcastLAN)
                Text("Broadcast подсети").tag(Settings.SendMode.broadcastSubnet)
                Text("Multicast").tag(Settings.SendMode.multicast)
            }
            .pickerStyle(.menu)

            if model.sendMode == .targetIPList || model.sendMode == .broadcastSubnet {
                VStack(alignment: .leading, spacing: 3) {
                    TextField("192.168.1.50, 192.168.1.51", text: $model.targets)
                        .textFieldStyle(.roundedBorder)
                    Text("Адреса лент через запятую")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Text("Порт").font(.system(size: 11))
                TextField("11988", value: $model.port, format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                    .monospacedDigit()
            }

            Toggle("Спектр в строке меню", isOn: $model.showSpectrumInMenuBar)
                .font(.system(size: 11))

            Toggle("Запускать при входе в систему", isOn: $model.launchAtLogin)
                .font(.system(size: 11))
            if let problem = model.loginItemProblem {
                Text(problem)
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Toggle("Обработка как в оригинале", isOn: $model.useOriginalBehaviour)
                .font(.system(size: 11))
            Text("Для сравнения: возвращает поведение Windows-версии целиком.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            Button("Применить и перезапустить") {
                model.restart()
            }
            .disabled(!model.isRunning)
            .font(.system(size: 11))
        }
        .padding(.top, 2)
    }
}
