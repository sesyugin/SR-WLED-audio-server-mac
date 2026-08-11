import Foundation

// Прогон всех проверок ядра. Ни одна не обращается к аудиоустройствам
// и не отправляет пакеты в реальную сеть.

let runner = TestRunner()

runPacketTests(runner)
runPacketSenderTests(runner)
runPipelineTests(runner)
runCorrectnessTests(runner)

exit(runner.summarize())
