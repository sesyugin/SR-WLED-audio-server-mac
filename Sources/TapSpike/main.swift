// Спайк: захват системного звука на macOS через CoreAudio process tap.
// Аналог WasapiLoopbackCaptureEx.cs из Windows-версии.
//
// Схема: глобальный tap на весь системный выход -> приватное aggregate-устройство,
// в TapList которого этот tap -> IOProc, читающий входные буферы.
// Драйверы (BlackHole и т.п.) не нужны, macOS 14.2+.

import Foundation
import CoreAudio

// MARK: - Обёртки над CoreAudio

struct CAError: Error, CustomStringConvertible {
    let op: String
    let status: OSStatus

    var description: String {
        // OSStatus часто является four-char code ('!obj', 'nope' и т.п.)
        var be = status.bigEndian
        let chars = withUnsafeBytes(of: &be) { raw in
            raw.map { byte -> Character in
                let scalar = UnicodeScalar(byte)
                return (32...126).contains(byte) ? Character(scalar) : "?"
            }
        }
        return "\(op) -> OSStatus \(status) '\(String(chars))'"
    }
}

func check(_ op: String, _ status: OSStatus) throws {
    guard status == noErr else { throw CAError(op: op, status: status) }
}

func address(_ selector: AudioObjectPropertySelector,
             scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
             element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain)
    -> AudioObjectPropertyAddress
{
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
}

func readProperty<T>(_ objectID: AudioObjectID,
                     _ addr: AudioObjectPropertyAddress,
                     into value: inout T,
                     _ opName: String) throws
{
    var addr = addr
    var size = UInt32(MemoryLayout<T>.size)
    try check(opName, AudioObjectGetPropertyData(objectID, &addr, 0, nil, &size, &value))
}

func readStringProperty(_ objectID: AudioObjectID,
                        _ addr: AudioObjectPropertyAddress,
                        _ opName: String) throws -> String
{
    var addr = addr
    var size = UInt32(MemoryLayout<CFString?>.size)
    var value: CFString? = nil
    try check(opName, withUnsafeMutablePointer(to: &value) { ptr in
        AudioObjectGetPropertyData(objectID, &addr, 0, nil, &size, ptr)
    })
    guard let value else { throw CAError(op: opName, status: -1) }
    return value as String
}

// MARK: - Шаг 1: устройство вывода по умолчанию (нужно как источник тактирования)

var outputDeviceID = AudioObjectID(kAudioObjectUnknown)
try readProperty(AudioObjectID(kAudioObjectSystemObject),
                 address(kAudioHardwarePropertyDefaultOutputDevice),
                 into: &outputDeviceID,
                 "получение устройства вывода по умолчанию")

let outputUID = try readStringProperty(outputDeviceID,
                                       address(kAudioDevicePropertyDeviceUID),
                                       "чтение UID устройства вывода")
let outputName = try readStringProperty(outputDeviceID,
                                        address(kAudioObjectPropertyName),
                                        "чтение имени устройства вывода")

print("Вывод по умолчанию: \(outputName)")
print("  UID: \(outputUID)")

// MARK: - Шаг 2: создание глобального tap

let tapDescription = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
tapDescription.name = "SR-WLED audio tap"
tapDescription.isPrivate = true          // не показывать tap другим приложениям
tapDescription.muteBehavior = .unmuted   // звук продолжает идти в колонки

var tapID = AudioObjectID(kAudioObjectUnknown)
try check("AudioHardwareCreateProcessTap",
          AudioHardwareCreateProcessTap(tapDescription, &tapID))
print("Tap создан, AudioObjectID = \(tapID)")

let tapUID = try readStringProperty(tapID,
                                    address(kAudioTapPropertyUID),
                                    "чтение UID тапа")

// MARK: - Шаг 3: приватное aggregate-устройство, читающее этот tap

let aggregateUID = UUID().uuidString
let aggregateDescription: [String: Any] = [
    kAudioAggregateDeviceNameKey: "SR-WLED Capture",
    kAudioAggregateDeviceUIDKey: aggregateUID,
    kAudioAggregateDeviceMainSubDeviceKey: outputUID,
    kAudioAggregateDeviceClockDeviceKey: outputUID,
    kAudioAggregateDeviceIsPrivateKey: true,   // не засорять список устройств в системе
    kAudioAggregateDeviceIsStackedKey: false,
    kAudioAggregateDeviceTapAutoStartKey: true,
    kAudioAggregateDeviceSubDeviceListKey: [],
    kAudioAggregateDeviceTapListKey: [
        [
            kAudioSubTapUIDKey: tapUID,
            kAudioSubTapDriftCompensationKey: true,
        ]
    ],
]

var aggregateID = AudioObjectID(kAudioObjectUnknown)
try check("AudioHardwareCreateAggregateDevice",
          AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregateID))
print("Aggregate-устройство создано, AudioObjectID = \(aggregateID)")

// Уборка обязательна: незакрытые tap/aggregate остаются висеть в coreaudiod.
@MainActor func teardown() {
    AudioHardwareDestroyAggregateDevice(aggregateID)
    AudioHardwareDestroyProcessTap(tapID)
}

// MARK: - Шаг 4: формат входного потока

var format = AudioStreamBasicDescription()
do {
    try readProperty(aggregateID,
                     address(kAudioDevicePropertyStreamFormat, scope: kAudioObjectPropertyScopeInput),
                     into: &format,
                     "чтение формата входного потока")
} catch {
    teardown()
    throw error
}

print("Формат захвата: \(format.mSampleRate.formatted()) Гц, "
      + "\(format.mChannelsPerFrame) кан., \(format.mBitsPerChannel) бит, "
      + "флаги 0x\(String(format.mFormatFlags, radix: 16))")

// MARK: - Шаг 5: IOProc — сюда приходит звук

final class LevelMeter: @unchecked Sendable {
    private let lock = NSLock()
    private var peak: Float = 0
    private var sumOfSquares: Double = 0
    private var sampleCount: Int = 0
    private(set) var callbackCount = 0
    private(set) var totalFrames = 0

    func accumulate(_ samples: UnsafeBufferPointer<Float>, frames: Int) {
        lock.lock()
        defer { lock.unlock() }
        for sample in samples {
            let magnitude = abs(sample)
            if magnitude > peak { peak = magnitude }
            sumOfSquares += Double(sample) * Double(sample)
        }
        sampleCount += samples.count
        callbackCount += 1
        totalFrames += frames
    }

    /// Возвращает (peak, rms) и сбрасывает накопленное.
    func drain() -> (peak: Float, rms: Float) {
        lock.lock()
        defer { lock.unlock() }
        let rms = sampleCount > 0 ? Float((sumOfSquares / Double(sampleCount)).squareRoot()) : 0
        let result = (peak, rms)
        peak = 0
        sumOfSquares = 0
        sampleCount = 0
        return result
    }
}

let meter = LevelMeter()
let ioQueue = DispatchQueue(label: "srwled.capture")

var procID: AudioDeviceIOProcID?
do {
    try check("AudioDeviceCreateIOProcIDWithBlock",
              // @Sendable обязателен: top-level код неявно @MainActor, а CoreAudio
              // вызывает блок со своего IO-потока. Без этого — trap в swift_task_checkIsolated.
              AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, ioQueue) {
                  @Sendable _, inInputData, _, _, _ in
                  let bufferList = UnsafeMutableAudioBufferListPointer(
                      UnsafeMutablePointer(mutating: inInputData))
                  for buffer in bufferList {
                      guard let data = buffer.mData, buffer.mDataByteSize > 0 else { continue }
                      let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                      let samples = UnsafeBufferPointer(
                          start: data.assumingMemoryBound(to: Float.self), count: count)
                      let channels = max(Int(buffer.mNumberChannels), 1)
                      meter.accumulate(samples, frames: count / channels)
                  }
              })

    try check("AudioDeviceStart", AudioDeviceStart(aggregateID, procID))
} catch {
    teardown()
    throw error
}

// MARK: - Шаг 6: 15 секунд измерений

print("")
print("Захват запущен. Включи музыку — ниже должен появиться уровень.")
print("(15 секунд, затем автоматическая остановка)")
print("")

let deadline = Date().addingTimeInterval(15)
while Date() < deadline {
    Thread.sleep(forTimeInterval: 0.25)
    let (peak, rms) = meter.drain()
    let barLength = Int((min(peak, 1.0) * 40).rounded())
    let bar = String(repeating: "█", count: barLength).padding(toLength: 40, withPad: " ", startingAt: 0)
    print(String(format: "\r[%@] peak %.4f  rms %.4f", bar, peak, rms), terminator: "")
    fflush(stdout)
}

print("")
print("")
print("Итого: \(meter.callbackCount) вызовов IOProc, \(meter.totalFrames) сэмплов "
      + "(~\(Int(Double(meter.totalFrames) / format.mSampleRate)) с звука)")

// MARK: - Уборка

AudioDeviceStop(aggregateID, procID)
if let procID {
    AudioDeviceDestroyIOProcID(aggregateID, procID)
}
teardown()
print("Tap и aggregate-устройство удалены.")
