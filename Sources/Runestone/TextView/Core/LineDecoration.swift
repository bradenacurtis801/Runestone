import UIKit

/// How the lines of one decoration kind are drawn: a color behind the whole row of text, and one behind the line's row in the gutter.
public struct LineDecorationStyle: Equatable {
    public var background: UIColor?
    public var gutterBackground: UIColor?

    public init(background: UIColor? = nil, gutterBackground: UIColor? = nil) {
        self.background = background
        self.gutterBackground = gutterBackground
    }
}

/// `count` lines from the 0-based row `firstRow` are of `kind` (0 means none).
public struct LineDecorationRun: Equatable {
    public var firstRow: Int
    public var count: Int
    public var kind: Int

    public init(firstRow: Int, count: Int, kind: Int) {
        self.firstRow = firstRow
        self.count = count
        self.kind = kind
    }
}
