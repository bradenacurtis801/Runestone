@testable import Runestone
import XCTest

final class LineDecorationTests: XCTestCase {
    private func document(_ lines: [String], kinds: [Int]) -> (StringView, LineManager) {
        let string = NSMutableString(string: lines.joined(separator: "\n"))
        let stringView = StringView(string: string)
        let lineManager = LineManager(stringView: stringView)
        lineManager.rebuild()
        lineManager.setDecorations(kinds.enumerated().map { LineDecorationRun(firstRow: $0.offset, count: 1, kind: $0.element) })
        lineManager.setGutterLabels(lines.indices.map { "L\($0)" }, startingAt: 0)
        return (stringView, lineManager)
    }

    private func decorations(_ lineManager: LineManager) -> [Int] {
        (0 ..< lineManager.lineCount).map { lineManager.decoration(atRow: $0) }
    }

    private func labels(_ lineManager: LineManager) -> [String] {
        (0 ..< lineManager.lineCount).map { lineManager.line(atRow: $0).data.gutterLabel }
    }

    /// Replaces `count` rows from `start` the way the editor's `replaceLines` does: from the start of the first row to the end of the last
    /// row's text, never past its line break.
    private func replace(_ stringView: StringView, _ lineManager: LineManager, start: Int, count: Int, with newLines: [String]) {
        let first = lineManager.line(atRow: start)
        let last = lineManager.line(atRow: start + count - 1)
        let from = first.location
        let to = last.location + last.data.length
        let helper = TextEditHelper(stringView: stringView, lineManager: lineManager, lineEndings: .lf)
        _ = helper.replaceText(in: NSRange(location: from, length: to - from), with: newLines.joined(separator: "\n"))
    }

    func testLinesAfterAReplacedStretchKeepTheirKindAndLabel() {
        let (stringView, lineManager) = document(["bar0", "note0", "bar1", "note1", "bar2", "note2"], kinds: [3, 5, 3, 5, 3, 5])
        replace(stringView, lineManager, start: 0, count: 2, with: ["bar0", "a", "b", "c"])
        XCTAssertEqual(lineManager.lineCount, 8)
        XCTAssertEqual(Array(decorations(lineManager).suffix(4)), [3, 5, 3, 5])
        XCTAssertEqual(Array(labels(lineManager).suffix(4)), ["L2", "L3", "L4", "L5"])
    }

    func testLinesAfterAStretchInTheMiddleKeepTheirKindAndLabel() {
        let (stringView, lineManager) = document(["bar0", "note0", "bar1", "note1", "bar2", "note2"], kinds: [3, 5, 3, 5, 3, 5])
        replace(stringView, lineManager, start: 2, count: 2, with: ["bar1", "x"])
        XCTAssertEqual(lineManager.lineCount, 6 - 2 + 2)
        XCTAssertEqual(Array(decorations(lineManager).suffix(2)), [3, 5])
        XCTAssertEqual(Array(labels(lineManager).suffix(2)), ["L4", "L5"])
        XCTAssertEqual(Array(decorations(lineManager).prefix(2)), [3, 5])
    }

    func testReplacingTheLastLinesLeavesTheOnesBefore() {
        let (stringView, lineManager) = document(["bar0", "note0", "bar1", "note1"], kinds: [3, 5, 3, 5])
        replace(stringView, lineManager, start: 2, count: 2, with: ["bar1", "p", "q"])
        XCTAssertEqual(lineManager.lineCount, 5)
        XCTAssertEqual(Array(decorations(lineManager).prefix(2)), [3, 5])
        XCTAssertEqual(Array(labels(lineManager).prefix(2)), ["L0", "L1"])
    }

    func testSettingKindsForRowsLeavesTheOthersAlone() {
        let (_, lineManager) = document(["a", "b", "c", "d"], kinds: [1, 2, 3, 4])
        lineManager.setDecorations([LineDecorationRun(firstRow: 1, count: 2, kind: 9)], inRows: 1 ..< 3)
        XCTAssertEqual(decorations(lineManager), [1, 9, 9, 4])
    }

    /// Replaces random stretches of a document the way the diff view patches it, and checks every line's kind and label against a plain array.
    func testRandomReplacementsKeepEveryLineKindAndLabel() {
        var generator = SeededGenerator(seed: 7)
        var lines = (0 ..< 24).map { "bar\($0)" }
        var kinds = Array(repeating: 3, count: 24)
        var labels = (0 ..< 24).map { "L\($0)" }
        let (stringView, lineManager) = document(lines, kinds: kinds)
        for step in 0 ..< 400 {
            let count = Int.random(in: 1 ... min(4, lines.count), using: &generator)
            let start = Int.random(in: 0 ... lines.count - count, using: &generator)
            let newCount = Int.random(in: 1 ... 6, using: &generator)
            let newLines = (0 ..< newCount).map { Int.random(in: 0 ..< 4, using: &generator) == 0 ? "" : "n\(step)_\($0)" }
            let newKinds = (0 ..< newCount).map { _ in Int.random(in: 0 ... 5, using: &generator) }
            let newLabels = (0 ..< newCount).map { "s\(step)_\($0)" }
            replace(stringView, lineManager, start: start, count: count, with: newLines)
            lineManager.setDecorations(newKinds.enumerated().map { LineDecorationRun(firstRow: start + $0.offset, count: 1, kind: $0.element) }, inRows: start ..< start + newCount)
            lineManager.setGutterLabels(newLabels, startingAt: start)
            lines.replaceSubrange(start ..< start + count, with: newLines)
            kinds.replaceSubrange(start ..< start + count, with: newKinds)
            labels.replaceSubrange(start ..< start + count, with: newLabels)
            XCTAssertEqual(lineManager.lineCount, lines.count, "line count at step \(step)")
            XCTAssertEqual(decorations(lineManager), kinds, "kinds at step \(step) (replaced \(count) from \(start) with \(newCount))")
            XCTAssertEqual(self.labels(lineManager), labels, "labels at step \(step)")
            if lineManager.lineCount != lines.count || decorations(lineManager) != kinds { return }
        }
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
