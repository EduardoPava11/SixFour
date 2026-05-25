import SwiftUI
import AVFoundation
import UIKit

/// Thin SwiftUI wrapper around AVCaptureVideoPreviewLayer.
///
/// Exposes a `onFocusTap` callback that fires with **two** coordinates per tap:
/// (a) `devicePoint` — normalized 0..1 in AVCaptureDevice space, suitable for
///     `focusPointOfInterest` / `exposurePointOfInterest`;
/// (b) `localPoint` — the tap location in the view's own coords, so callers can
///     position a reticle exactly where the user tapped.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    var onFocusTap: ((_ devicePoint: CGPoint, _ localPoint: CGPoint) -> Void)? = nil

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.previewLayer.session = session
        v.previewLayer.videoGravity = .resizeAspectFill
        v.onTap = onFocusTap
        let tap = UITapGestureRecognizer(
            target: v, action: #selector(PreviewView.handleTap(_:))
        )
        v.addGestureRecognizer(tap)
        v.isUserInteractionEnabled = true
        return v
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.onTap = onFocusTap
    }

    final class PreviewView: UIView {
        var onTap: ((CGPoint, CGPoint) -> Void)? = nil
        // UIKit requires `class var layerClass`; `static` does not satisfy the override.
        // swiftlint:disable:next static_over_final_class
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer {
            // Guaranteed by `layerClass` override above (documented UIView contract).
            // swiftlint:disable:next force_cast
            layer as! AVCaptureVideoPreviewLayer
        }
        @objc func handleTap(_ gr: UITapGestureRecognizer) {
            let local = gr.location(in: self)
            let device = previewLayer.captureDevicePointConverted(fromLayerPoint: local)
            onTap?(device, local)
        }
    }
}
