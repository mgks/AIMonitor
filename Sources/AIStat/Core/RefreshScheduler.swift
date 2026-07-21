import Foundation

/// Drives the periodic refresh. Bound to the main run loop because the
/// resulting state updates flow into SwiftUI on the main actor.
@MainActor
public final class RefreshScheduler {
    private var timer: Timer?
    private var interval: TimeInterval
    private let action: () -> Void

    public init(interval: TimeInterval, action: @escaping () -> Void) {
        self.interval = max(10, interval)   // never hammer APIs below 10s
        self.action = action
    }

    public func start() {
        stop()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.action() }
        }
        // common mode so refresh still fires while a menu is open.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Change the interval and restart if currently running.
    public func setInterval(_ newInterval: TimeInterval) {
        interval = max(10, newInterval)
        if timer != nil { start() }
    }
}
