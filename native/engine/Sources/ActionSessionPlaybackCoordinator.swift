import AVFoundation
import Foundation

final class ActionSessionPlaybackCoordinator: ObservableObject, @unchecked Sendable {
    let player: AVPlayer

    @Published private(set) var currentTimeSeconds: Double = 0
    @Published private(set) var durationSeconds: Double = 0

    private var timeObserver: Any?

    init(url: URL) {
        self.player = AVPlayer(url: url)
        installTimeObserver()
        refreshDuration()
    }

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
    }

    func load(url: URL) {
        player.pause()
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        currentTimeSeconds = 0
        refreshDuration()
    }

    func pause() {
        player.pause()
    }

    func seek(to seconds: Double) {
        let target = max(0, min(seconds, durationSeconds > 0 ? durationSeconds : seconds))
        let time = CMTime(seconds: target, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTimeSeconds = target
    }

    private func installTimeObserver() {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] time in
            guard let self else {
                return
            }
            let seconds = time.seconds
            if seconds.isFinite {
                currentTimeSeconds = seconds
            }
            refreshDuration()
        }
    }

    private func refreshDuration() {
        guard let duration = player.currentItem?.duration.seconds, duration.isFinite else {
            return
        }
        durationSeconds = duration
    }
}
