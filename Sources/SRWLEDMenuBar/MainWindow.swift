import AppKit
import SwiftUI
import SRWLEDVisuals
import SRWLEDCore

/// Главное окно: объёмная визуализация во всю площадь и панель управления справа.
///
/// Панель разложена по вкладкам, а не сплошным списком. Причина не в красоте:
/// у настроек четыре разных повода открыться — «куда слать», «как выглядит»,
/// «почему не работает» и «как ведёт себя приложение», — и приходят к ним
/// в разное время. Сплошной список заставлял прокручивать мимо трёх чужих
/// разделов к своему, а самый нужный из них, диагностика, лежал в самом низу.
struct MainWindow: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Вкладки панели. Порядок — по тому, когда к ним приходят: адреса задают
    /// один раз при настройке, вид крутят постоянно, диагностику открывают
    /// в беде, поведение приложения — почти никогда.
    private enum Tab: String, CaseIterable, Identifiable {
        case send, look, health, app
        var id: String { rawValue }

        var key: S {
            switch self {
            case .send: return .whereToSend
            case .look: return .tabLook
            case .health: return .diagnostics
            case .app: return .settings
            }
        }

        var symbol: String {
            switch self {
            case .send: return "antenna.radiowaves.left.and.right"
            case .look: return "paintbrush"
            case .health: return "stethoscope"
            case .app: return "gearshape"
            }
        }
    }

    @State private var tab: Tab = .send

    /// Показана ли обвязка поверх сцены в режиме просмотра.
    ///
    /// Панель убрали — значит смотрят. Тогда через несколько секунд покоя
    /// уходят и состояние, и полоса под сценой: на экране остаётся то, ради
    /// чего окно и открыли. Любое движение указателя возвращает их обратно.
    @State private var chromeVisible = true
    @State private var chromeTask: Task<Void, Never>?

    var body: some View {
        Group {
            if model.showsPanel {
                HSplitView {
                    stage
                        .frame(minWidth: 460)
                    sidebar
                        .frame(minWidth: 300, idealWidth: 330, maxWidth: 400)
                }
            } else {
                stage
            }
        }
        // Без панели окно можно сузить до самой сцены: в режиме просмотра
        // ширина под настройки больше не нужна.
        .frame(minWidth: model.showsPanel ? 860 : 480, minHeight: 460)
        .environment(\.layoutDirection, model.language.isRightToLeft ? .rightToLeft : .leftToRight)
    }

    // MARK: Сцена

    private var stage: some View {
        ZStack {
            if model.animationEnabled {
                scene.ignoresSafeArea()
            } else {
                stageOff
            }

            VStack {
                stageHeader
                Spacer()
                if !model.isRunning { stagePrompt }
                stageBar
            }
            .padding(22)
            // Обвязка уходит только в режиме просмотра и только на ходу:
            // на остановленном сервере прятать нечего, а кнопку пуска
            // прятать и вовсе нельзя.
            .opacity(chromeShown ? 1 : 0)
            .animation(reduceMotion ? nil : Motion.envelope(rising: chromeShown),
                       value: chromeShown)
        }
        // Движение указателя над сценой возвращает обвязку и заново заводит
        // отсчёт покоя.
        .onContinuousHover { phase in
            if case .active = phase { wakeChrome() }
        }
        .onChange(of: model.showsPanel) { _, _ in wakeChrome() }
        .onDisappear { chromeTask?.cancel() }
    }

    /// Видна ли обвязка прямо сейчас.
    private var chromeShown: Bool {
        model.showsPanel || !model.isRunning || chromeVisible
    }

    /// Возвращает обвязку и снова заводит отсчёт покоя.
    private func wakeChrome() {
        chromeTask?.cancel()
        if !chromeVisible { chromeVisible = true }
        guard !model.showsPanel, model.isRunning else { return }
        chromeTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            chromeVisible = false
        }
    }

    @ViewBuilder
    private var scene: some View {
        switch model.sceneStyle {
        case .crown:
            CrownScene(sampler: { model.sampleBands() },
                       isRunning: model.isRunning,
                       paused: !model.windowVisible,
                       palette: model.palette,
                       tint: model.columnTint,
                       light: model.lightQuality)
        case .neon:
            NeonScene(sampler: { model.sampleBands() },
                      isRunning: model.isRunning,
                      paused: !model.windowVisible,
                      palette: model.palette,
                      tint: model.columnTint,
                      showsWordmark: false)
        case .ring:
            RingScene(sampler: { model.sampleBands() },
                      isRunning: model.isRunning,
                      paused: !model.windowVisible,
                      palette: model.palette,
                      tint: model.columnTint)
        case .sphere:
            WireScene(sampler: { model.sampleBands() },
                      isRunning: model.isRunning,
                      paused: !model.windowVisible,
                      palette: model.palette,
                      tint: model.columnTint)
        }
    }

    /// Что видно, когда анимация выключена. Не чёрный прямоугольник: человек
    /// выключил картинку, а не звук, и ему всё ещё нужно видеть, что сигнал
    /// идёт. Полоска спектра стоит шестнадцати заливок на кадр против трёх
    /// сотен тел у сцены — в этом и вся разница в цене.
    private var stageOff: some View {
        ZStack {
            Color(red: 0.035, green: 0.030, blue: 0.028).ignoresSafeArea()
            VStack(spacing: 14) {
                SpectrumStrip(bands: model.bands, ignition: model.isRunning ? 1 : 0)
                    .frame(height: 54)
                    .foregroundStyle(Color(hue: model.columnTint ?? model.palette.hues.hot,
                                           saturation: 0.7, brightness: 1).opacity(0.75))
                    .animation(reduceMotion ? nil : Motion.light(rising: model.isRunning),
                               value: model.isRunning)
                Text(model.localized(.animationOffNote))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 420)
            .padding(.horizontal, 40)
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

    /// Полоса под сценой: выключатель картинки, и только он.
    ///
    /// Ползунок цвета отсюда убран и живёт в настройках, во вкладке «Вид».
    /// Причина простая: цвет выбирают один раз и надолго, а место под сценой
    /// стоит дорого — там уместно то, к чему тянутся часто. Выключатель как
    /// раз такой: анимацию гасят, когда машина занята другим, и делают это
    /// глядя на неё.
    private var stageBar: some View {
        HStack(spacing: 14) {
            Button {
                model.animationEnabled.toggle()
            } label: {
                Image(systemName: model.animationEnabled ? "waveform" : "waveform.slash")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 30, height: 26)
                    .background(.white.opacity(model.animationEnabled ? 0.14 : 0.26),
                                in: RoundedRectangle(cornerRadius: 7))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .hoverFillOnDark(cornerRadius: 7)
            .help(model.localized(model.animationEnabled ? .animationOff : .animationOn))

            Text(model.localized(model.animationEnabled ? .animationOn : .animationOff))
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.8))

            Spacer(minLength: 0)

            // Убрать панель — здесь же, под сценой: тянутся к этому глядя
            // на картинку, а не разыскивая пункт в меню.
            Button {
                withAnimation(reduceMotion ? nil : Motion.disclosure) {
                    model.showsPanel.toggle()
                }
            } label: {
                Image(systemName: model.showsPanel
                      ? "rectangle.righthalf.inset.filled"
                      : "rectangle.righthalf.inset.filled.arrow.right")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 30, height: 26)
                    .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 7))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .hoverFillOnDark(cornerRadius: 7)
            .help(model.localized(model.showsPanel ? .hidePanel : .showPanel))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.black.opacity(0.34), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.10), lineWidth: 0.5))
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
        .hoverFillOnDark(cornerRadius: 22, opacity: 0.10)
        .shadow(color: .black.opacity(0.4), radius: 14, y: 4)
        .padding(.bottom, 10)
    }

    // MARK: Панель

    private var sidebar: some View {
        VStack(spacing: 0) {
            header
            Divider()
            tabs
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if model.isFirstRun { welcomeBlock }

                    switch tab {
                    case .send:
                        destinationSection
                        devicesSection
                    case .look:
                        appearanceSection
                    case .health:
                        if case .noSignal = model.state { permissionBlock }
                        if case .failed = model.state { failureBlock }
                        diagnosticsSection
                        if let reason = model.lastRestartReason {
                            Label(restartNote(reason),
                                  systemImage: "arrow.triangle.2.circlepath")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    case .app:
                        behaviourSection
                        processingSection
                    }
                }
                .padding(18)
            }
        }
    }

    /// Шапка панели: пуск и общий вердикт. Стоит выше вкладок и не уезжает
    /// с прокруткой — на эту кнопку жмут из любого раздела.
    ///
    /// Точка вердикта здесь же не для красоты: она видна со всех вкладок и
    /// краснеет раньше, чем человек догадается открыть диагностику.
    private var header: some View {
        HStack(spacing: 10) {
            Button {
                model.isRunning ? model.stop() : model.start()
            } label: {
                Label(model.localized(model.isRunning ? .stop : .start),
                      systemImage: model.isRunning ? "stop.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            // Cmd-Return, а не голый Return: во вкладке «куда слать» два
            // текстовых поля, а голый Return делает эту кнопку кнопкой
            // по умолчанию — и отправка начиналась бы прямо при вводе адреса.
            .keyboardShortcut(.return, modifiers: .command)

            Button {
                tab = .health
            } label: {
                Circle()
                    .fill(overallColour)
                    .frame(width: 9, height: 9)
                    // Вердикт перетекает, а не подменяется: смена цвета так
                    // читается как «вот сейчас изменилось», а мгновенная —
                    // как будто так и было всегда.
                    .animation(reduceMotion ? nil : Motion.attack, value: overallColour)
                    .padding(5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverFill(cornerRadius: 6)
            .help(model.localized(.diagnostics))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var overallColour: Color {
        colour(for: model.diagnostics.overall)
    }

    private var tabs: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { item in
                Button {
                    tab = item
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.symbol).font(.system(size: 13))
                        Text(model.localized(item.key))
                            .font(.system(size: 9))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                    .background(tab == item ? Color.accentColor.opacity(0.16) : Color.clear)
                    .foregroundStyle(tab == item ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .hoverFill(cornerRadius: 0, opacity: 0.06)
            }
        }
    }

    // MARK: Разделы

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

            Button(model.localized(model.isSearching ? .refresh : .searchDevices)) {
                model.isSearching ? model.refreshDeviceStatuses() : model.startDiscovery()
            }
            .font(.system(size: 11))
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
        // Через ключ, а не через сырое значение перечисления: у SyncState они
        // написаны по-русски и годятся для отладки, но не для интерфейса.
        return model.localized(status.key)
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

    private var appearanceSection: some View {
        section(model.localized(.tabLook)) {
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

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(model.localized(.columnColour))
                        .font(.system(size: 11))
                    Spacer()
                    Text(model.columnTint == nil
                         ? model.localized(.fromPalette)
                         : "\(Int((model.columnTint ?? 0) * 360))°")
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                HueSlider(hue: Binding(get: { model.columnTint },
                                       set: { model.columnHue = $0 ?? -1 }),
                          fallback: model.palette.hues.hot)
            }

            Toggle(model.localized(.animationOn), isOn: $model.animationEnabled)
                .font(.system(size: 11))

            // Качество прячется, когда сцены нет: настройка того, чего сейчас
            // не рисуют, — это орган, у которого нельзя увидеть результат.
            if model.animationEnabled {
                Picker(model.localized(.quality), selection: $model.lightQuality) {
                    Text(model.localized(.qualityFull)).tag(false)
                    Text(model.localized(.qualityLight)).tag(true)
                }
                .pickerStyle(.segmented)
                .font(.system(size: 11))
            }

            Toggle(model.localized(.spectrumInMenuBar), isOn: $model.showSpectrumInMenuBar)
                .font(.system(size: 11))
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
                    NSPasteboard.general.setString(model.diagnostics.asText(language: model.language),
                                                   forType: .string)
                }
                .font(.system(size: 11))
            }
        }
    }

    private var behaviourSection: some View {
        section(model.localized(.behaviour)) {
            Toggle(model.localized(.launchAtLogin), isOn: $model.launchAtLogin)
                .font(.system(size: 11))
            Toggle(model.localized(.autoStart), isOn: $model.autoStart)
                .font(.system(size: 11))
            Text(model.localized(.autoStartNote))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let problem = model.loginItemProblem {
                Text(problem)
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Text(model.localized(.language))
                    .font(.system(size: 11))
                Spacer()
                Picker("", selection: $model.language) {
                    ForEach(Language.allCases) { language in
                        Text(language.nativeName).tag(language)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 150)
            }
        }
    }

    private var processingSection: some View {
        section(model.localized(.processing)) {
            Toggle(model.localized(.originalBehaviour), isOn: $model.useOriginalBehaviour)
                .font(.system(size: 11))
            Text(model.localized(.originalBehaviourNote))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Набор «как в оригинале» задаёт все параметры разом, и поштучные
            // переключатели поверх него не применяются. Показывать их при
            // включённом наборе — обманывать: крутится, а не действует.
            if !model.useOriginalBehaviour {
                Divider().padding(.vertical, 2)

                slider(model.localized(.sensitivity),
                       note: model.localized(.sensitivityNote),
                       value: $model.sensitivity,
                       range: 0...1,
                       auto: true,
                       format: { "\(Int($0 * 100))%" })

                slider(model.localized(.silenceThreshold),
                       note: model.localized(.silenceNote),
                       value: $model.silenceDB,
                       range: (-90)...(-30),
                       auto: false,
                       format: { "\(Int($0)) dBFS" })

                Toggle(model.localized(.smoothing), isOn: $model.smoothBands)
                    .font(.system(size: 11))

                choice(model.localized(.bandGrid), on: $model.wledBandGrid,
                       yes: "WLED", no: "40–10000 Hz", note: model.localized(.gridNote))
                choice(model.localized(.windowKind), on: $model.hannWindow,
                       yes: "Hann", no: "FlatTop")
                choice(model.localized(.aggregation), on: $model.energyAggregation,
                       yes: "RMS", no: "Max")
                choice(model.localized(.agc), on: $model.stableGain,
                       yes: "Stable", no: "Original")

                Button(model.localized(.resetDefaults)) { model.resetProcessing() }
                    .font(.system(size: 11))
            }

            Button(model.localized(.applyRestart)) { model.restart() }
                .disabled(!model.isRunning)
                .font(.system(size: 11))
        }
    }

    /// Ползунок с подписью, значением и — если параметр это допускает —
    /// состоянием «пусть решает само». Отрицательная величина и есть это
    /// состояние: отдельный переключатель рядом с каждым ползунком удвоил бы
    /// число органов в разделе, ничего не добавив.
    private func slider(_ title: String, note: String,
                        value: Binding<Double>,
                        range: ClosedRange<Double>,
                        auto: Bool,
                        format: @escaping (Double) -> String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.system(size: 11))
                Spacer()
                Text(auto && value.wrappedValue < 0
                     ? "auto"
                     : format(max(range.lowerBound, value.wrappedValue)))
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Slider(value: Binding(get: { max(range.lowerBound, value.wrappedValue) },
                                      set: { value.wrappedValue = $0 }),
                       in: range)
                if auto {
                    Button("auto") { value.wrappedValue = -1 }
                        .font(.system(size: 10))
                        .disabled(value.wrappedValue < 0)
                }
            }
            Text(note)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Выбор из двух вариантов. Названия вариантов намеренно не переводятся:
    /// Hann, FlatTop, RMS — имена собственные, и в любой стране их пишут так же.
    private func choice(_ title: String, on: Binding<Bool>,
                        yes: String, no: String, note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 11))
            Picker("", selection: on) {
                Text(yes).tag(true)
                Text(no).tag(false)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            if let note {
                Text(note)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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

    /// Отказ: причина на языке интерфейса, под ней — текст системной ошибки.
    ///
    /// Раньше отказ подменялся состоянием «нет сигнала», и человек видел совет
    /// про разрешение на звук, когда на деле не был задан ни один адрес.
    private var failureBlock: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(model.localized(model.stateKey))
                .font(.system(size: 12, weight: .medium))
            if !model.stateDetail.isEmpty {
                Text(model.stateDetail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    /// «Захват пересобран: сменилось устройство вывода: AirPods → Динамики».
    private func restartNote(_ reason: S) -> String {
        let head = "\(model.localized(.captureRestarted)): \(model.localized(reason))"
        return model.lastRestartDetail.isEmpty ? head : "\(head): \(model.lastRestartDetail)"
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
