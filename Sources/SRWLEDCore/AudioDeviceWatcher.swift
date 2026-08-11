import CoreAudio
import Foundation

/// Следит за изменениями звукового тракта и сообщает, что захват пора пересобрать.
///
/// Зачем: устройство вывода читается один раз при запуске, и его UID зашивается
/// в aggregate-устройство как источник тактирования. Переключился на AirPods —
/// старое aggregate указывает в никуда, и захват тихо умирает: ни ошибки, ни события,
/// просто перестают приходить кадры.
///
/// Отдельно важна частота дискретизации: у Bluetooth-гарнитуры с микрофоном она
/// падает до 16–24 кГц, и без пересборки верхние полосы застынут навсегда, потому что
/// сетка полос и разрешение БПФ считаются от частоты.
public final class AudioDeviceWatcher: @unchecked Sendable {

    public enum Change: String, Sendable {
        case defaultOutputDevice = "сменилось устройство вывода"
        case sampleRate = "сменилась частота дискретизации"
        case deviceList = "изменился список устройств"
    }

    private let queue = DispatchQueue(label: "srwled.device.watcher")
    private let onChange: @Sendable (Change) -> Void

    /// Изменения приходят пачками: система шлёт несколько уведомлений подряд.
    /// Без выдержки мы бы пересобирали захват по три раза на одно переключение.
    private let debounce: DispatchTimeInterval
    private var pendingWork: DispatchWorkItem?
    private let lock = NSLock()

    private var systemListeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var deviceListeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    public init(debounceMilliseconds: Int = 300,
                onChange: @escaping @Sendable (Change) -> Void)
    {
        self.debounce = .milliseconds(debounceMilliseconds)
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    /// - Parameter outputDeviceID: устройство, за частотой которого следим.
    ///   Передавай то же, что использует текущий захват.
    public func start(watching outputDeviceID: AudioObjectID) {
        stop()

        addSystemListener(kAudioHardwarePropertyDefaultOutputDevice, change: .defaultOutputDevice)
        addSystemListener(kAudioHardwarePropertyDevices, change: .deviceList)

        if outputDeviceID != AudioObjectID(kAudioObjectUnknown) {
            addDeviceListener(outputDeviceID,
                              kAudioDevicePropertyNominalSampleRate,
                              change: .sampleRate)
        }
    }

    public func stop() {
        lock.lock()
        let system = systemListeners
        let devices = deviceListeners
        systemListeners = []
        deviceListeners = []
        pendingWork?.cancel()
        pendingWork = nil
        lock.unlock()

        for (address, block) in system {
            var address = address
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, queue, block)
        }
        for (objectID, address, block) in devices {
            var address = address
            AudioObjectRemovePropertyListenerBlock(objectID, &address, queue, block)
        }
    }

    // MARK: - Внутреннее

    private func addSystemListener(_ selector: AudioObjectPropertySelector, change: Change) {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.schedule(change)
        }

        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, queue, block)

        if status == noErr {
            lock.lock()
            systemListeners.append((address, block))
            lock.unlock()
        }
    }

    private func addDeviceListener(_ objectID: AudioObjectID,
                                   _ selector: AudioObjectPropertySelector,
                                   change: Change)
    {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.schedule(change)
        }

        let status = AudioObjectAddPropertyListenerBlock(objectID, &address, queue, block)

        if status == noErr {
            lock.lock()
            deviceListeners.append((objectID, address, block))
            lock.unlock()
        }
    }

    private func schedule(_ change: Change) {
        lock.lock()
        pendingWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.onChange(change)
        }
        pendingWork = work
        lock.unlock()
        queue.asyncAfter(deadline: .now() + debounce, execute: work)
    }
}
