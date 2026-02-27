import Foundation
import UIKit
import AVFoundation
import Vision

public class VisionViewController: MRZViewController {
    var request: VNRecognizeTextRequest!
    let mrzTracker = StringTracker()

    var completionHandler: ((String) -> Void)?
    var onCancel: (() -> Void)?

    private let closeButton = UIButton(type: .system)

    public override func viewDidLoad() {
        request = VNRecognizeTextRequest(completionHandler: recognizeTextHandler)
        request.recognitionLanguages = ["en-US"]
        request.customWords = ["<", "<<", "<<<"]
        request.usesLanguageCorrection = false
        request.recognitionLevel = .accurate

        super.viewDidLoad()

        setupCloseButton()
    }

    private func setupCloseButton() {
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setTitle("Kapat", for: .normal)
        closeButton.tintColor = .white
        closeButton.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        closeButton.layer.cornerRadius = 8
        closeButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        view.addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            closeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16)
        ])
    }

    @objc private func closeTapped() {
        dismiss(animated: true) {
            self.onCancel?()
        }
    }

    func recognizeTextHandler(request: VNRequest, error: Error?) {
        var codes = [String]()

        guard let results = request.results as? [VNRecognizedTextObservation] else {
            return
        }

        let maximumCandidates = 1
        for visionResult in results {
            guard let candidate = visionResult.topCandidates(maximumCandidates).first else { continue }

            let rawText = candidate.string.replacingOccurrences(of: " ", with: "")
            let mrz = rawText.uppercased().filter {
                "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789<".contains($0)
            }

            if let result = mrz.checkMrz(), result != "nil" {
                codes.append(result)
            }
        }

        mrzTracker.logFrame(strings: codes)

        if let sureNumber = mrzTracker.getStableString() {
            showString(string: sureNumber)
            mrzTracker.reset(string: sureNumber)

            DispatchQueue.main.async {
                self.completionHandler?(sureNumber)
            }
        }
    }

    public override func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        request.regionOfInterest = regionOfInterest
        let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: textOrientation, options: [:])

        do {
            try requestHandler.perform([request])
        } catch {
            print(error)
        }
    }
}
