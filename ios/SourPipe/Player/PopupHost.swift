import AVKit
import SwiftUI
import UIKit

/// NewPipe's popup player, done with Picture in Picture. iOS only starts it from a player layer
/// that is in the window, so a tiny one sits behind the app. It holds the player only while the
/// popup is wanted: an attached layer would make iOS pause playback in the background.
struct PopupHost: UIViewRepresentable {
    @ObservedObject var player: PlayerController
    /// Called when the user taps the popup's button to return to the app.
    var onRestore: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        context.coordinator.setUp(view)
        return view
    }

    func updateUIView(_ view: PlayerLayerView, context: Context) {
        context.coordinator.controller = player
        context.coordinator.onRestore = onRestore
        if player.popupRequested {
            // Not during the view update: starting changes published state.
            DispatchQueue.main.async { context.coordinator.start() }
        }
    }

    final class PlayerLayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    @MainActor
    final class Coordinator: NSObject, AVPictureInPictureControllerDelegate {
        weak var controller: PlayerController?
        var onRestore: () -> Void = {}
        private var view: PlayerLayerView?
        private var pip: AVPictureInPictureController?
        private var possible: NSKeyValueObservation?
        private var timeout: Task<Void, Never>?
        private var active = false

        func setUp(_ view: PlayerLayerView) {
            self.view = view
            guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
            pip = AVPictureInPictureController(playerLayer: view.playerLayer)
            pip?.delegate = self
        }

        func start() {
            guard let controller, let pip, let view else {
                controller?.popupRequested = false
                return
            }
            controller.popupRequested = false
            if active { return }
            view.playerLayer.player = controller.player
            possible?.invalidate()
            // Possible once the item is ready and the layer has drawn a frame.
            possible = pip.observe(\.isPictureInPicturePossible, options: [.initial, .new]) {
                [weak self] pip, _ in
                guard pip.isPictureInPicturePossible else { return }
                Task { @MainActor in self?.begin() }
            }
            timeout?.cancel()
            timeout = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                guard let self, !Task.isCancelled, !self.active else { return }
                NSLog("[player] popup did not start; showing the player instead")
                self.release()
                self.onRestore()
            }
        }

        private func begin() {
            guard let pip, !active, !pip.isPictureInPictureActive else { return }
            possible?.invalidate()
            possible = nil
            timeout?.cancel()
            pip.startPictureInPicture()
        }

        private func release() {
            possible?.invalidate()
            possible = nil
            timeout?.cancel()
            view?.playerLayer.player = nil
        }

        nonisolated func pictureInPictureControllerDidStartPictureInPicture(
            _ pip: AVPictureInPictureController
        ) {
            Task { @MainActor in
                self.active = true
                self.controller?.isInPictureInPicture = true
            }
        }

        nonisolated func pictureInPictureController(
            _ pip: AVPictureInPictureController,
            failedToStartPictureInPictureWithError error: Error
        ) {
            NSLog("[player] popup failed: %@", error.localizedDescription)
            Task { @MainActor in
                self.release()
                self.onRestore()
            }
        }

        nonisolated func pictureInPictureControllerDidStopPictureInPicture(
            _ pip: AVPictureInPictureController
        ) {
            Task { @MainActor in
                self.active = false
                self.controller?.isInPictureInPicture = false
                self.release()
            }
        }

        nonisolated func pictureInPictureController(
            _ pip: AVPictureInPictureController,
            restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completion:
                @escaping (Bool) -> Void
        ) {
            Task { @MainActor in
                self.onRestore()
                completion(true)
            }
        }
    }
}
