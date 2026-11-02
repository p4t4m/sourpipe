import AVKit
import SwiftUI
import UIKit

/// The system player UI: controls, AirPlay, speed menu and Picture in Picture.
struct VideoPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer
    var onPictureInPicture: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(onPictureInPicture: onPictureInPicture) }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.updatesNowPlayingInfoCenter = false
        controller.delegate = context.coordinator
        context.coordinator.attach(controller, player: player)
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if context.coordinator.detached == false, controller.player !== player {
            controller.player = player
        }
    }

    /// iOS pauses a player whose video is on screen when the app leaves the foreground. Detaching
    /// it keeps the audio going; during Picture in Picture it must stay attached.
    final class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        private weak var controller: AVPlayerViewController?
        private var player: AVPlayer?
        private var observers: [NSObjectProtocol] = []
        private var inPictureInPicture = false
        var detached = false
        private let onPictureInPicture: (Bool) -> Void

        init(onPictureInPicture: @escaping (Bool) -> Void) {
            self.onPictureInPicture = onPictureInPicture
        }

        func attach(_ controller: AVPlayerViewController, player: AVPlayer) {
            self.controller = controller
            self.player = player
            let center = NotificationCenter.default
            observers.append(center.addObserver(
                forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
            ) { [weak self] _ in
                guard let self, !self.inPictureInPicture else { return }
                self.detached = true
                self.controller?.player = nil
            })
            observers.append(center.addObserver(
                forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                self.detached = false
                self.controller?.player = self.player
            })
        }

        deinit {
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
        }

        func playerViewControllerWillStartPictureInPicture(_ c: AVPlayerViewController) {
            inPictureInPicture = true
            onPictureInPicture(true)
        }

        func playerViewControllerDidStopPictureInPicture(_ c: AVPlayerViewController) {
            inPictureInPicture = false
            onPictureInPicture(false)
        }
    }
}
