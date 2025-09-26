import SwiftUI
import AVFoundation

#if canImport(UIKit)
import UIKit

struct QRScannerView: UIViewControllerRepresentable {
    static var isSupported: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return UIImagePickerController.isSourceTypeAvailable(.camera)
        #endif
    }

    var onDetect: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerVC {
        let vc = ScannerVC()
        vc.onDetect = onDetect
        return vc
    }

    func updateUIViewController(_ uiViewController: ScannerVC, context: Context) { }

    final class ScannerVC: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        var onDetect: ((String) -> Void)?

        private let session = AVCaptureSession()
        private let preview = AVCaptureVideoPreviewLayer()

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black

            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device) else { return }

            let output = AVCaptureMetadataOutput()
            guard session.canAddInput(input), session.canAddOutput(output) else { return }
            session.addInput(input)
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            output.metadataObjectTypes = [.qr]

            preview.session = session
            preview.videoGravity = .resizeAspectFill
            view.layer.addSublayer(preview)
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            preview.frame = view.bounds
            if !session.isRunning { session.startRunning() }
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            for obj in metadataObjects {
                guard let readable = obj as? AVMetadataMachineReadableCodeObject,
                      readable.type == .qr,
                      let str = readable.stringValue else { continue }
                session.stopRunning()
                onDetect?(str)
                dismiss(animated: true)
                break
            }
        }
    }
}

#else

// Fallback for platforms without UIKit (e.g., macOS AppKit build)
struct QRScannerView: View {
    static var isSupported: Bool { false }
    var onDetect: (String) -> Void

    init(onDetect: @escaping (String) -> Void) {
        self.onDetect = onDetect
    }

    var body: some View {
        // No camera scanning on this platform
        EmptyView()
    }
}

#endif
