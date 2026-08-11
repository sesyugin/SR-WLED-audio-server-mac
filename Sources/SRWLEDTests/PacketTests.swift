import Foundation
import SRWLEDCore

func runPacketTests(_ t: TestRunner) {
    t.suite("Пакет audiosync v2") { t in

        t.test("Ровно 44 байта — WLED отбрасывает любой другой размер молча") { t in
            t.expectEqual(AudioSyncPacket().encoded().count, 44, "размер пакета")
            t.expectEqual(AudioSyncPacket.byteCount, 44, "константа размера")
        }

        t.test("Заголовок 00002 с нулевым байтом-терминатором") { t in
            let bytes = AudioSyncPacket().encoded()
            t.expectEqual(Array(bytes[0..<6]), [0x30, 0x30, 0x30, 0x30, 0x32, 0x00], "заголовок")
        }

        t.test("Каждое поле лежит по своему смещению") { t in
            var packet = AudioSyncPacket()
            packet.sampleRaw = 1.0            // 0x3F800000
            packet.sampleSmth = 2.0           // 0x40000000
            packet.samplePeak = 0xAA
            packet.frameCounter = 0xBB
            packet.fftBins = (0..<16).map { UInt8($0 * 16) }
            packet.zeroCrossingCount = 0x1234
            packet.fftMagnitude = 4.0         // 0x40800000
            packet.fftMajorPeak = 8.0         // 0x41000000

            let bytes = packet.encoded()

            t.expectEqual(Array(bytes[8..<12]), [0x00, 0x00, 0x80, 0x3F], "sampleRaw @8")
            t.expectEqual(Array(bytes[12..<16]), [0x00, 0x00, 0x00, 0x40], "sampleSmth @12")
            t.expectEqual(bytes[16], 0xAA, "samplePeak @16")
            t.expectEqual(bytes[17], 0xBB, "frameCounter @17")
            t.expectEqual(Array(bytes[18..<34]), (0..<16).map { UInt8($0 * 16) }, "полосы @18")
            t.expectEqual(bytes[34], 0x34, "zeroCrossing младший @34")
            t.expectEqual(bytes[35], 0x12, "zeroCrossing старший @35")
            t.expectEqual(Array(bytes[36..<40]), [0x00, 0x00, 0x80, 0x40], "magnitude @36")
            t.expectEqual(Array(bytes[40..<44]), [0x00, 0x00, 0x00, 0x41], "majorPeak @40")
        }

        t.test("Давление кодируется фиксированной точкой 8.8") { t in
            var packet = AudioSyncPacket()

            packet.pressure = 0
            t.expectEqual(Array(packet.encoded()[6..<8]), [0, 0], "ноль")

            packet.pressure = 1.0
            t.expectEqual(Array(packet.encoded()[6..<8]), [1, 0], "единица")

            packet.pressure = 1.5
            t.expectEqual(Array(packet.encoded()[6..<8]), [1, 128], "полтора")

            packet.pressure = 300
            t.expectEqual(Array(packet.encoded()[6..<8]), [255, 0], "зажим сверху")

            packet.pressure = -5
            t.expectEqual(Array(packet.encoded()[6..<8]), [0, 0], "зажим снизу")
        }

        // Ловит реальный дефект: конверсия NaN в UInt8 роняет процесс по SIGTRAP.
        t.test("Мусор в полях не роняет процесс") { t in
            let garbage: [Float] = [.nan, .infinity, -.infinity, -1, 1e30, .signalingNaN]
            for value in garbage {
                var packet = AudioSyncPacket()
                packet.pressure = value
                packet.sampleRaw = value
                packet.sampleSmth = value
                packet.fftMagnitude = value
                packet.fftMajorPeak = value
                t.expectEqual(packet.encoded().count, 44, "пакет с \(value)")
            }
        }

        t.test("Затухание доводит все поля до нуля и не уходит в минус") { t in
            var packet = AudioSyncPacket()
            packet.sampleRaw = 200
            packet.sampleSmth = 200
            packet.fftMagnitude = 3000
            packet.pressure = 100
            packet.fftBins = [UInt8](repeating: 255, count: 16)

            // Видимая часть — полосы. Именно их гашение человек замечает глазом,
            // и оно должно укладываться примерно в секунду при 47 кадрах в секунду.
            var framesUntilDark = 0
            var frames = 0
            while frames < 200 {
                packet.decay(rate: 0.85)
                frames += 1
                if framesUntilDark == 0 && packet.fftBins.allSatisfy({ $0 == 0 }) {
                    framesUntilDark = frames
                }
                if framesUntilDark > 0 && packet.sampleRaw == 0 { break }
            }

            t.expect(framesUntilDark <= 40,
                     "полосы гасли \(framesUntilDark) кадров (~\(String(format: "%.1f", Double(framesUntilDark) / 47))" +
                     " с), ожидалось не больше 40")
            t.expect(frames <= 70, "полное затухание заняло \(frames) кадров, ожидалось не больше 70")
            t.expect(packet.fftBins.allSatisfy { $0 == 0 }, "полосы должны обнулиться")
            t.expectEqual(packet.sampleRaw, 0, "уровень")
            t.expect(packet.pressure >= 0, "давление не должно уходить в минус")
        }
    }
}
