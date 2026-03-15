import AVKit
import SwiftUI

struct ActionSessionPreviewView: View {
    let videoURL: URL

    @State private var player: AVPlayer

    init(videoURL: URL) {
        self.videoURL = videoURL
        _player = State(initialValue: AVPlayer(url: videoURL))
    }

    var body: some View {
        VideoPlayer(player: player)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .onChange(of: videoURL) { _, newValue in
                player.pause()
                player = AVPlayer(url: newValue)
            }
            .onDisappear {
                player.pause()
            }
    }
}
