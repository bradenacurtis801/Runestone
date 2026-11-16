import UIKit

/// Scrolls the text view while a selection is dragged to an edge: a handle, the loupe, or a word held and moved.
///
/// UIKit moves the text view only to show the end of the selection, never because the finger is near an edge, and it draws a handle's
/// movement itself, telling the text view where the selection ends only when the finger lifts. So this watches the finger on every window
/// of the scene (the handles may be drawn in a window of the system's own), scrolls while it is in an edge zone, and — for a handle —
/// moves the held end of the selection to the character under the finger, against an anchor kept from when the finger came down.
final class SelectionAutoscroller: NSObject, UIGestureRecognizerDelegate {
    var isEnabled = false {
        didSet {
            guard isEnabled != oldValue else { return }
            if isEnabled { watchWindows() } else { unwatchWindows() }
        }
    }
    /// What scrolls the text up and down — the text view itself unless it sits in a scroll view that does.
    var verticalScrollView: (() -> UIScrollView?)?
    /// Asked when a finger comes down: `true` leaves it alone (something else owns the touch).
    var isSuspended: (() -> Bool)?

    private unowned let textView: TextView
    private var watchers: [Watcher] = []
    private var windowObserver: NSObjectProtocol?
    private var offsetObserver: NSKeyValueObservation?
    private var link: CADisplayLink?

    /// Whether the finger came down on the text view (or by its handles, a little outside it).
    private var startedHere = false
    private var rangeAtTouch = NSRange(location: 0, length: 0)
    private var isDragging = false
    /// The end of the selection that is not held, and whether the held one is the start, while a finger is on a handle.
    private var anchor: Int?
    private var holdsStart = false
    /// Where the edge scroll last put the text, held against any other scrolling while a selection is dragged.
    private var heldOffset: CGPoint?
    private var isScrolling = false
    /// Set while this changes the selection itself, so that is not taken for the finger's.
    private var isMovingSelection = false

    /// How close to the top or bottom edge, in points, the finger starts to scroll; the sides' is `sideZone`.
    private let zone: CGFloat = 70
    private let sideZone: CGFloat = 50
    /// The most it scrolls in a frame.
    private let maxStep: CGFloat = 16

    private final class Watcher {
        weak var window: UIWindow?
        let gesture: UILongPressGestureRecognizer
        init(window: UIWindow, gesture: UILongPressGestureRecognizer) {
            self.window = window
            self.gesture = gesture
        }
    }

    init(textView: TextView) {
        self.textView = textView
        super.init()
        offsetObserver = textView.observe(\.contentOffset) { [weak self] view, _ in
            // While a selection is dragged, the finger's scroll is the only scroll: UIKit and the text view move the view to show the
            // end of the selection (far to the left, on a short line), and that is put back.
            guard let self, let held = self.heldOffset, !self.isScrolling, view.contentOffset != held else { return }
            view.contentOffset = held
        }
    }

    deinit {
        windowObserver.map(NotificationCenter.default.removeObserver)
        watchers.forEach { $0.gesture.view?.removeGestureRecognizer($0.gesture) }
        link?.invalidate()
    }

    // MARK: Watching the finger

    func windowChanged() {
        guard isEnabled else { return }
        if textView.window == nil { unwatchWindows() } else { watchWindows() }
    }

    func selectionChanged() {
        guard isEnabled else { return }
        // A window may have come up since (the system's, for the handles).
        watchWindows()
        if startedHere, touch != nil, !isMovingSelection { isDragging = true }
    }

    /// Every window of the scene gets a watcher — the app's and any the system adds.
    private func watchWindows() {
        guard let scene = textView.window?.windowScene else { return }
        watchers.removeAll { $0.window == nil || $0.gesture.view == nil }
        for window in scene.windows where !watchers.contains(where: { $0.window === window }) {
            let press = UILongPressGestureRecognizer(target: self, action: #selector(touched(_:)))
            press.minimumPressDuration = 0
            press.allowableMovement = .greatestFiniteMagnitude
            press.cancelsTouchesInView = false
            press.delegate = self
            window.addGestureRecognizer(press)
            watchers.append(Watcher(window: window, gesture: press))
        }
        windowObserver = windowObserver ?? NotificationCenter.default.addObserver(forName: UIWindow.didBecomeVisibleNotification, object: nil, queue: .main) { [weak self] _ in
            self?.watchWindows()
        }
    }

    private func unwatchWindows() {
        watchers.forEach { $0.gesture.view?.removeGestureRecognizer($0.gesture) }
        watchers = []
        windowObserver.map(NotificationCenter.default.removeObserver)
        windowObserver = nil
        stop()
    }

    /// The watcher a finger is down on.
    private var touch: UILongPressGestureRecognizer? {
        watchers.first { $0.gesture.state == .began || $0.gesture.state == .changed }?.gesture
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    @objc private func touched(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            let host = textView.superview ?? textView
            startedHere = textView.frame.insetBy(dx: -40, dy: -40).contains(gesture.location(in: host)) && !(isSuspended?() ?? false)
            guard startedHere else { return }
            rangeAtTouch = textView.selectedRange
            isDragging = false
            grabHandle(at: gesture.location(in: textView.superview ?? textView))
            start()
        case .changed:
            break
        default:
            guard touch == nil else { return }
            startedHere = false
            isDragging = false
            anchor = nil
            stop()
        }
    }

    /// A finger that came down on a selection's handle: the end that is not held is kept as the anchor, and the held one is found from
    /// the finger.
    private func grabHandle(at point: CGPoint) {
        anchor = nil
        let range = rangeAtTouch
        guard range.length > 0 else { return }
        let host = textView.superview ?? textView
        /// How far the finger is from a handle's knob: past the end of its line, the start's above it and the end's below.
        func distance(to offset: Int, below: Bool) -> CGFloat {
            guard let position = textView.position(from: textView.beginningOfDocument, offset: offset) else { return .infinity }
            let rect = textView.convert(textView.caretRect(for: position), to: host)
            return hypot(rect.midX - point.x, (below ? rect.maxY + 12 : rect.minY - 12) - point.y)
        }
        let start = distance(to: range.location, below: false)
        let end = distance(to: range.location + range.length, below: true)
        guard min(start, end) < 50 else { return }
        holdsStart = start < end
        anchor = holdsStart ? range.location + range.length : range.location
        isDragging = true
    }

    // MARK: Scrolling

    private func start() {
        guard link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    private func stop() {
        heldOffset = nil
        link?.invalidate()
        link = nil
    }

    /// How far into a zone the finger is, up to 1 (at 1.5 times the zone): negative toward the start, positive toward the end.
    private func pressure(_ position: CGFloat, start: CGFloat, end: CGFloat, zone: CGFloat) -> CGFloat {
        if position > end - zone { return min((position - (end - zone)) / zone, 1.5) / 1.5 }
        if position < start + zone { return -min((start + zone - position) / zone, 1.5) / 1.5 }
        return 0
    }

    @objc private func tick() {
        guard let touch else { return stop() }
        if !isDragging {
            let now = textView.selectedRange
            // A selection that grew or moved: not a caret put down by a tap (that lands as the finger lifts).
            guard now != rangeAtTouch, now.length > 0 || rangeAtTouch.length > 0 else { return }
            isDragging = true
        }
        if heldOffset == nil { heldOffset = textView.contentOffset }
        isScrolling = true
        var moved = false

        // Up and down: what scrolls the text.
        let scroll: UIScrollView? = verticalScrollView.map { $0() } ?? textView
        if let scroll, let host = scroll.superview {
            let inset = scroll.adjustedContentInset
            let y = touch.location(in: host).y
            let step = pressure(y, start: scroll.frame.minY + inset.top, end: scroll.frame.maxY - inset.bottom, zone: zone) * maxStep
            let lowest = -inset.top
            let highest = max(lowest, scroll.contentSize.height - scroll.bounds.height + inset.bottom)
            let next = min(max(scroll.contentOffset.y + step, lowest), highest)
            if step != 0, next != scroll.contentOffset.y {
                scroll.contentOffset.y = next
                moved = true
            }
        }

        // Sideways: the text view itself, for text that is not wrapped. The gutter's width is not text.
        let inset = textView.adjustedContentInset
        if textView.contentSize.width > textView.bounds.width - inset.left - inset.right, let host = textView.superview {
            let x = touch.location(in: host).x
            let step = pressure(x, start: textView.frame.minX + inset.left + textView.gutterWidth, end: textView.frame.maxX - inset.right, zone: sideZone) * maxStep
            let lowest = -inset.left
            let highest = max(lowest, textView.contentSize.width - textView.bounds.width + inset.right)
            let next = min(max(textView.contentOffset.x + step, lowest), highest)
            if step != 0, next != textView.contentOffset.x {
                textView.contentOffset.x = next
                moved = true
            }
        }

        // What the finger scrolled is held from here on, and the selection moving after it must not scroll the view.
        isScrolling = false
        heldOffset = textView.contentOffset
        guard moved else { return }
        followFinger(touch)
    }

    /// The text moved under a finger that has not: the end of the selection being dragged — the one nearer the finger — goes to the
    /// character now under it. A caret goes there whole.
    private func followFinger(_ touch: UILongPressGestureRecognizer) {
        // The text view's own coordinates are the content's: the input view inside it sits at its origin.
        var point = touch.location(in: textView)
        // The finger is on the handle's knob, a little past the line it moves.
        if anchor != nil { point.y += holdsStart ? 12 : -12 }
        guard let target = textView.closestPosition(to: point) else { return }
        let at = textView.offset(from: textView.beginningOfDocument, to: target)
        let current = textView.selectedRange
        var range = NSRange(location: at, length: 0)
        if let anchor {
            range = NSRange(location: min(anchor, at), length: abs(anchor - at))
        } else if current.length > 0 {
            func distance(_ offset: Int) -> CGFloat {
                guard let position = textView.position(from: textView.beginningOfDocument, offset: offset) else { return .greatestFiniteMagnitude }
                let rect = textView.caretRect(for: position)
                return hypot(rect.midX - point.x, rect.midY - point.y)
            }
            let low = current.location, high = current.location + current.length
            let other = distance(low) <= distance(high) ? high : low
            range = NSRange(location: min(other, at), length: abs(other - at))
        }
        guard range != current else { return }
        isMovingSelection = true
        textView.selectedRange = range
        isMovingSelection = false
    }
}
