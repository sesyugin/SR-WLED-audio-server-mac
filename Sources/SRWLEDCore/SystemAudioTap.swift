import CoreAudio
import Foundation

/// Захват системного звука через CoreAudio process tap — замена WASAPI loopback.
///
/// Глобальный tap на весь вывод заворачивается в приватное aggregate-устройство,
/// с которого читает IOProc. Виртуальные драйверы вроде BlackHole не нужны.
/// Требуется macOS 14.2+.
public final class SystemAudioTap: @unchecked Sendable {
    public struct CaptureFormat: Sendable {
        public let sampleRate: Double
        public let channels: Int
    }

    public enum TapError: Error, CustomStringConvertible {
        case coreAudio(operation: String, status: OSStatus)
        case missingValue(String)

        public var description: String {
            switch self {
            case .coreAudio(let operation, let status):
                var bigEndian = status.bigEndian
                let code = withUnsafeBytes(of: &bigEndian) { raw in
                    String(raw.map { (32...126).contains($0) ? Character(UnicodeScalar($0)) : "?" })
                }
                return "\(operation): OSStatus \(status) ('\(code)')"
            case .missingValue(let what):
                return "не удалось получить \(what)"
            }
        }
    }

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var isRunning = false

    private let queue = DispatchQueue(label: "srwled.audio.capture")

    public private(set) var format: CaptureFormat?
    public private(set) var outputDeviceName = ""

    public init() {}

    deinit {
        try? stop()
    }

    /// Запускает захват. `handler` вызывается с аудиопотока CoreAudio —
    /// внутри нельзя блокироваться и аллоцировать.
    public func start(handler: @escaping @Sendable (UnsafeBufferPointer<Float>, Int) -> Void) throws {
        guard !isRunning else { return }

        // 1. Устройство вывода по умолчанию — источник тактирования для aggregate.
        var outputDeviceID = AudioObjectID(kAudioObjectUnknown)
        try readProperty(AudioObjectID(kAudioObjectSystemObject),
                         Self.address(kAudioHardwarePropertyDefaultOutputDevice),
                         into: &outputDeviceID,
                         "чтение устройства вывода по умолчанию")

        let outputUID = try readString(outputDeviceID,
                                       Self.address(kAudioDevicePropertyDeviceUID),
                                       "UID устройства вывода")
        outputDeviceName = (try? readString(outputDeviceID,
                                            Self.address(kAudioObjectPropertyName),
                                            "имя устройства вывода")) ?? outputUID

        // 2. Глобальный стерео-tap, не глушащий звук в колонках.
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.name = "SR-WLED audio tap"
        description.isPrivate = true
        description.muteBehavior = .unmuted

        try check("AudioHardwareCreateProcessTap",
                  AudioHardwareCreateProcessTap(description, &tapID))

        let tapUID = try readString(tapID, Self.address(kAudioTapPropertyUID), "UID тапа")

        // 3. Приватное aggregate-устройство, читающее этот tap.
        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "SR-WLED Capture",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceClockDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [],
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapUIDKey: tapUID, kAudioSubTapDriftCompensationKey: true]
            ],
        ]

        do {
            try check("AudioHardwareCreateAggregateDevice",
                      AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary,
                                                         &aggregateID))

            var asbd = AudioStreamBasicDescription()
            try readProperty(aggregateID,
                             Self.address(kAudioDevicePropertyStreamFormat,
                                          scope: kAudioObjectPropertyScopeInput),
                             into: &asbd,
                             "чтение формата входного потока")

            guard asbd.mSampleRate > 0, asbd.mChannelsPerFrame > 0 else {
                throw TapError.missingValue("корректный формат потока")
            }
            format = CaptureFormat(sampleRate: asbd.mSampleRate,
                                   channels: Int(asbd.mChannelsPerFrame))

            try check("AudioDeviceCreateIOProcIDWithBlock",
                      AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) {
                          @Sendable _, inInputData, _, _, _ in
                          let bufferList = UnsafeMutableAudioBufferListPointer(
                              UnsafeMutablePointer(mutating: inInputData))
                          for buffer in bufferList {
                              guard let data = buffer.mData, buffer.mDataByteSize > 0 else { continue }
                              let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                              let samples = UnsafeBufferPointer(
                                  start: data.assumingMemoryBound(to: Float.self), count: count)
                              handler(samples, max(Int(buffer.mNumberChannels), 1))
                          }
                      })

            try check("AudioDeviceStart", AudioDeviceStart(aggregateID, procID))
            isRunning = true
        } catch {
            try? stop()
            throw error
        }
    }

    public func stop() throws {
        if isRunning {
            AudioDeviceStop(aggregateID, procID)
            isRunning = false
        }
        if let procID {
            AudioDeviceDestroyIOProcID(aggregateID, procID)
            self.procID = nil
        }
        if aggregateID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    // MARK: - Обёртки над CoreAudio

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                                element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain)
        -> AudioObjectPropertyAddress
    {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    private func check(_ operation: String, _ status: OSStatus) throws {
        guard status == noErr else {
            throw TapError.coreAudio(operation: operation, status: status)
        }
    }

    private func readProperty<T>(_ objectID: AudioObjectID,
                                 _ propertyAddress: AudioObjectPropertyAddress,
                                 into value: inout T,
                                 _ operation: String) throws
    {
        var propertyAddress = propertyAddress
        var size = UInt32(MemoryLayout<T>.size)
        // Только для POD-типов (AudioObjectID, AudioStreamBasicDescription): пишем в сырые байты,
        // чтобы не превращать в raw-указатель значение, которое может содержать ссылку.
        try check(operation, withUnsafeMutableBytes(of: &value) { raw in
            AudioObjectGetPropertyData(objectID, &propertyAddress, 0, nil, &size, raw.baseAddress!)
        })
    }

    private func readString(_ objectID: AudioObjectID,
                            _ propertyAddress: AudioObjectPropertyAddress,
                            _ what: String) throws -> String
    {
        var propertyAddress = propertyAddress
        var size = UInt32(MemoryLayout<CFString?>.size)
        var value: CFString?
        try check("чтение: \(what)", withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(objectID, &propertyAddress, 0, nil, &size, pointer)
        })
        guard let value else { throw TapError.missingValue(what) }
        return value as String
    }
}
