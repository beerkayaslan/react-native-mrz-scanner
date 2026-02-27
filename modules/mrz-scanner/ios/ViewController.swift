import UIKit
import AVFoundation
import Vision

public class MRZViewController: UIViewController {
    var previewView: PreviewView!
    var cutoutView: UIView!

    var maskLayer = CAShapeLayer()
    var currentOrientation = UIDeviceOrientation.portrait

    private let captureSession = AVCaptureSession()
    let captureSessionQueue = DispatchQueue(label: "com.documentaccept.mrz.capture")

    var captureDevice: AVCaptureDevice?

    var videoDataOutput = AVCaptureVideoDataOutput()
    let videoDataOutputQueue = DispatchQueue(label: "com.documentaccept.mrz.video")

    var regionOfInterest = CGRect(x: 0, y: 0, width: 1, height: 1)
    var textOrientation = CGImagePropertyOrientation.up

    var bufferAspectRatio: Double = 16.0 / 9.0
    var uiRotationTransform = CGAffineTransform.identity
    var bottomToTopTransform = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -1)
    var roiToGlobalTransform = CGAffineTransform.identity
    var visionToAVFTransform = CGAffineTransform.identity

    public override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black

        NotificationCenter.default.addObserver(self, selector: #selector(appWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)

        previewView = PreviewView()
        cutoutView = UIView()

        previewView.translatesAutoresizingMaskIntoConstraints = false
        cutoutView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(previewView)
        view.addSubview(cutoutView)

        NSLayoutConstraint.activate([
            previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            previewView.topAnchor.constraint(equalTo: view.topAnchor),
            previewView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            cutoutView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            cutoutView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            cutoutView.topAnchor.constraint(equalTo: view.topAnchor),
            cutoutView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        previewView.session = captureSession

        cutoutView.backgroundColor = UIColor.gray.withAlphaComponent(0.45)
        maskLayer.backgroundColor = UIColor.clear.cgColor
        maskLayer.fillRule = .evenOdd
        cutoutView.layer.mask = maskLayer

        captureSessionQueue.async {
            self.setupCamera()
            DispatchQueue.main.async {
                self.calculateRegionOfInterest()
            }
        }
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        captureSessionQueue.async {
            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
            }
        }
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        captureSessionQueue.async {
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
    }

    @objc private func appWillEnterForeground() {
        captureSessionQueue.async {
            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
            }
        }
    }

    @objc private func appDidEnterBackground() {
        captureSessionQueue.async {
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }
        }
    }

    public override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        let deviceOrientation = UIDevice.current.orientation
        if deviceOrientation.isPortrait || deviceOrientation.isLandscape {
            currentOrientation = deviceOrientation
        }

        if let videoPreviewLayerConnection = previewView.videoPreviewLayer.connection,
           let newVideoOrientation = AVCaptureVideoOrientation(deviceOrientation: deviceOrientation) {
            videoPreviewLayerConnection.videoOrientation = newVideoOrientation
        }

        calculateRegionOfInterest()
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateCutout()
    }

    func calculateRegionOfInterest() {
        let desiredHeightRatio = 0.25
        let desiredWidthRatio = 0.8
        let maxPortraitWidth = 0.9

        let size: CGSize
        if currentOrientation.isPortrait || currentOrientation == .unknown {
            size = CGSize(
                width: min(desiredWidthRatio * bufferAspectRatio, maxPortraitWidth),
                height: desiredHeightRatio / bufferAspectRatio
            )
        } else {
            size = CGSize(width: desiredWidthRatio, height: desiredHeightRatio)
        }

        regionOfInterest.origin = CGPoint(x: (1 - size.width) / 2, y: (1 - size.height) / 2)
        regionOfInterest.size = size

        setupOrientationAndTransform()
        DispatchQueue.main.async { self.updateCutout() }
    }

    func updateCutout() {
        let roiRectTransform = bottomToTopTransform.concatenating(uiRotationTransform)
        let cutout = previewView.videoPreviewLayer.layerRectConverted(fromMetadataOutputRect: regionOfInterest.applying(roiRectTransform))

        let path = UIBezierPath(rect: cutoutView.frame)
        path.append(UIBezierPath(roundedRect: cutout, cornerRadius: 8))
        maskLayer.path = path.cgPath
    }

    func setupOrientationAndTransform() {
        let roi = regionOfInterest
        roiToGlobalTransform = CGAffineTransform(translationX: roi.origin.x, y: roi.origin.y)
            .scaledBy(x: roi.width, y: roi.height)

        switch currentOrientation {
        case .landscapeLeft:
            textOrientation = .up
            uiRotationTransform = .identity
        case .landscapeRight:
            textOrientation = .down
            uiRotationTransform = CGAffineTransform(translationX: 1, y: 1).rotated(by: CGFloat.pi)
        case .portraitUpsideDown:
            textOrientation = .left
            uiRotationTransform = CGAffineTransform(translationX: 1, y: 0).rotated(by: CGFloat.pi / 2)
        default:
            textOrientation = .right
            uiRotationTransform = CGAffineTransform(translationX: 0, y: 1).rotated(by: -CGFloat.pi / 2)
        }

        visionToAVFTransform = roiToGlobalTransform
            .concatenating(bottomToTopTransform)
            .concatenating(uiRotationTransform)
    }

    func setupCamera() {
        guard let captureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            return
        }
        self.captureDevice = captureDevice

        if captureDevice.supportsSessionPreset(.hd4K3840x2160) {
            captureSession.sessionPreset = .hd4K3840x2160
            bufferAspectRatio = 3840.0 / 2160.0
        } else {
            captureSession.sessionPreset = .hd1920x1080
            bufferAspectRatio = 1920.0 / 1080.0
        }

        guard let deviceInput = try? AVCaptureDeviceInput(device: captureDevice) else { return }
        if captureSession.canAddInput(deviceInput) {
            captureSession.addInput(deviceInput)
        }

        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        videoDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
        videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]

        if captureSession.canAddOutput(videoDataOutput) {
            captureSession.addOutput(videoDataOutput)
            videoDataOutput.connection(with: .video)?.preferredVideoStabilizationMode = .off
        }

        do {
            try captureDevice.lockForConfiguration()
            captureDevice.videoZoomFactor = 1.5
            captureDevice.autoFocusRangeRestriction = .near
            captureDevice.unlockForConfiguration()
        } catch {
        }

        captureSession.startRunning()
    }

    func showString(string: String) {
        captureSessionQueue.sync {
            self.captureSession.stopRunning()
        }
    }
}

extension MRZViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    }
}

extension AVCaptureVideoOrientation {
    init?(deviceOrientation: UIDeviceOrientation) {
        switch deviceOrientation {
        case .portrait: self = .portrait
        case .portraitUpsideDown: self = .portraitUpsideDown
        case .landscapeLeft: self = .landscapeRight
        case .landscapeRight: self = .landscapeLeft
        default: return nil
        }
    }
}
