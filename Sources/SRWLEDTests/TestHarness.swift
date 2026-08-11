import Foundation

/// Минимальный прогонщик тестов.
///
/// Своя реализация вместо swift-testing или XCTest сознательно: оба поставляются только
/// вместе с Xcode, а проект должен собираться и проверяться на голых Command Line Tools.
/// Если Xcode когда-нибудь появится, тесты переносятся на swift-testing почти механически.
final class TestRunner {
    private var currentSuite = ""
    private var passed = 0
    private var failed = 0
    private var failures: [String] = []
    private var currentTest = ""
    private var currentTestFailed = false

    func suite(_ name: String, _ body: (TestRunner) -> Void) {
        currentSuite = name
        print("\n\u{1B}[1m\(name)\u{1B}[0m")
        body(self)
    }

    func test(_ name: String, _ body: (TestRunner) throws -> Void) {
        currentTest = name
        currentTestFailed = false
        do {
            try body(self)
        } catch {
            currentTestFailed = true
            failures.append("\(currentSuite) → \(name): выброшено исключение \(error)")
        }
        if currentTestFailed {
            failed += 1
            print("  \u{1B}[31m✗\u{1B}[0m \(name)")
        } else {
            passed += 1
            print("  \u{1B}[32m✓\u{1B}[0m \(name)")
        }
    }

    /// Проверка. При провале тест помечается упавшим, но прогон продолжается —
    /// так за один запуск видно все проблемы сразу.
    func expect(_ condition: Bool, _ message: @autoclosure () -> String,
                file: StaticString = #file, line: UInt = #line) {
        guard !condition else { return }
        currentTestFailed = true
        let location = "\(URL(fileURLWithPath: "\(file)").lastPathComponent):\(line)"
        let text = "\(currentSuite) → \(currentTest): \(message()) [\(location)]"
        failures.append(text)
        print("    \u{1B}[31m↳ \(message())\u{1B}[0m  (\(location))")
    }

    func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ label: String = "",
                                   file: StaticString = #file, line: UInt = #line) {
        expect(actual == expected,
               "\(label.isEmpty ? "" : label + ": ")получено \(actual), ожидалось \(expected)",
               file: file, line: line)
    }

    /// Возвращает код выхода процесса.
    func summarize() -> Int32 {
        let total = passed + failed
        print("\n" + String(repeating: "─", count: 56))
        print("Test run with \(total) tests: \(passed) passed, \(failed) failed")
        if !failures.isEmpty {
            print("\nПодробности:")
            for failure in failures { print("  · \(failure)") }
        }
        print(String(repeating: "─", count: 56))
        return failed == 0 ? 0 : 1
    }
}
