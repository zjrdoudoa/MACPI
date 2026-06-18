import Foundation

final class AppTimerBox: @unchecked Sendable {
    private var timer: Timer?

    func replace(with newTimer: Timer) {
        timer?.invalidate()
        timer = newTimer
    }

    func invalidate() {
        timer?.invalidate()
        timer = nil
    }
}
