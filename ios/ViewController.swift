import UIKit
import AVFoundation
import Vision

public class MRZViewController: UIViewController {

    // MARK: – Camera preview
    var previewView: PreviewView!

    // MARK: – Overlay layers & views
    private var overlayView: UIView!
    private var maskLayer = CAShapeLayer()
    private var cardBorderLayer = CAShapeLayer()
    private var cornerLayers: [CAShapeLayer] = []
    private var chipView: UIView!
    private var mrzLinesContainer: UIView!
    private var scanLineView: UIView!
    var hintLabel: UILabel!

    // MARK: – Public configuration
    var instructionText: String = "Kimliğinizin arka yüzünü çerçeveye yerleştirin" {
        didSet { hintLabel?.text = instructionText }
    }

    // MARK: – Camera & capture
    var currentOrientation = UIDeviceOrientation.portrait
    private let captureSession = AVCaptureSession()
    let captureSessionQueue = DispatchQueue(label: "com.documentaccept.mrz.capture")
    var captureDevice: AVCaptureDevice?
    var videoDataOutput = AVCaptureVideoDataOutput()
    let videoDataOutputQueue = DispatchQueue(label: "com.documentaccept.mrz.video")

    // MARK: – Region of interest & transforms
    var regionOfInterest = CGRect(x: 0, y: 0, width: 1, height: 1)
    var textOrientation = CGImagePropertyOrientation.up
    var bufferAspectRatio: Double = 16.0 / 9.0
    var uiRotationTransform = CGAffineTransform.identity
    var bottomToTopTransform = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -1)
    var roiToGlobalTransform = CGAffineTransform.identity
    var visionToAVFTransform = CGAffineTransform.identity

    // MARK: – Card frame constants
    private let cardAspectRatio: CGFloat = 85.6 / 54.0   // ID-1 standard
    private let cardWidthRatio: CGFloat = 0.88
    private(set) var cardRect: CGRect = .zero

    // ─────────────────────────────────────────────
    // MARK: – Lifecycle
    // ─────────────────────────────────────────────

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        NotificationCenter.default.addObserver(self, selector: #selector(appWillEnterForeground),
                                               name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidEnterBackground),
                                               name: UIApplication.didEnterBackgroundNotification, object: nil)

        setupPreviewView()
        setupOverlay()
        setupCardOverlayElements()

        previewView.session = captureSession

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
            if !self.captureSession.isRunning { self.captureSession.startRunning() }
        }
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        captureSessionQueue.async {
            if self.captureSession.isRunning { self.captureSession.stopRunning() }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        if captureSession.isRunning { captureSession.stopRunning() }
    }

    @objc private func appWillEnterForeground() {
        captureSessionQueue.async {
            if !self.captureSession.isRunning { self.captureSession.startRunning() }
        }
    }

    @objc private func appDidEnterBackground() {
        captureSessionQueue.async {
            if self.captureSession.isRunning { self.captureSession.stopRunning() }
        }
    }

    public override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        let deviceOrientation = UIDevice.current.orientation
        if deviceOrientation.isPortrait || deviceOrientation.isLandscape {
            currentOrientation = deviceOrientation
        }
        if let connection = previewView.videoPreviewLayer.connection,
           let newOrientation = AVCaptureVideoOrientation(deviceOrientation: deviceOrientation) {
            connection.videoOrientation = newOrientation
        }
        calculateRegionOfInterest()
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateCutout()
    }

    // ─────────────────────────────────────────────
    // MARK: – UI Setup
    // ─────────────────────────────────────────────

    private func setupPreviewView() {
        previewView = PreviewView()
        previewView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(previewView)
        NSLayoutConstraint.activate([
            previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            previewView.topAnchor.constraint(equalTo: view.topAnchor),
            previewView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupOverlay() {
        overlayView = UIView()
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.isUserInteractionEnabled = false
        view.addSubview(overlayView)
        NSLayoutConstraint.activate([
            overlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlayView.topAnchor.constraint(equalTo: view.topAnchor),
            overlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        overlayView.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        maskLayer.backgroundColor = UIColor.clear.cgColor
        maskLayer.fillRule = .evenOdd
        overlayView.layer.mask = maskLayer
    }

    private func setupCardOverlayElements() {
        // Thin card border
        cardBorderLayer.fillColor = UIColor.clear.cgColor
        cardBorderLayer.strokeColor = UIColor.white.withAlphaComponent(0.35).cgColor
        cardBorderLayer.lineWidth = 1.5
        view.layer.addSublayer(cardBorderLayer)

        // Four corner brackets
        for _ in 0..<4 {
            let corner = CAShapeLayer()
            corner.fillColor = UIColor.clear.cgColor
            corner.strokeColor = UIColor.white.cgColor
            corner.lineWidth = 3.0
            corner.lineCap = .round
            cornerLayers.append(corner)
            view.layer.addSublayer(corner)
        }

        // Chip icon (golden IC chip)
        chipView = buildChipView()
        view.addSubview(chipView)

        // MRZ line indicators
        mrzLinesContainer = UIView()
        mrzLinesContainer.isUserInteractionEnabled = false
        view.addSubview(mrzLinesContainer)

        // Animated scan line
        scanLineView = UIView()
        scanLineView.backgroundColor = UIColor(red: 0.3, green: 0.75, blue: 1.0, alpha: 0.5)
        scanLineView.layer.cornerRadius = 1
        view.addSubview(scanLineView)

        // Hint label
        hintLabel = UILabel()
        hintLabel.text = instructionText
        hintLabel.textColor = .white
        hintLabel.font = .systemFont(ofSize: 15, weight: .medium)
        hintLabel.textAlignment = .center
        hintLabel.numberOfLines = 0
        hintLabel.layer.shadowColor = UIColor.black.cgColor
        hintLabel.layer.shadowOffset = CGSize(width: 0, height: 1)
        hintLabel.layer.shadowOpacity = 0.7
        hintLabel.layer.shadowRadius = 3
        view.addSubview(hintLabel)
    }

    // ─────────────────────────────────────────────
    // MARK: – Chip View Builder
    // ─────────────────────────────────────────────

    private func buildChipView() -> UIView {
        let chip = UIView()
        chip.backgroundColor = UIColor(red: 0.82, green: 0.71, blue: 0.40, alpha: 0.92)
        chip.layer.cornerRadius = 5
        chip.layer.borderWidth = 0.8
        chip.layer.borderColor = UIColor(red: 0.68, green: 0.58, blue: 0.28, alpha: 1.0).cgColor

        // Horizontal contact lines
        for i in 0..<4 {
            let line = UIView()
            line.backgroundColor = UIColor(red: 0.68, green: 0.58, blue: 0.28, alpha: 0.55)
            line.tag = 100 + i
            chip.addSubview(line)
        }
        // Vertical center line
        let vLine = UIView()
        vLine.backgroundColor = UIColor(red: 0.68, green: 0.58, blue: 0.28, alpha: 0.55)
        vLine.tag = 200
        chip.addSubview(vLine)

        return chip
    }

    // ─────────────────────────────────────────────
    // MARK: – Region of Interest (text recognition)
    // ─────────────────────────────────────────────

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

    // ─────────────────────────────────────────────
    // MARK: – Cutout & Overlay Layout
    // ─────────────────────────────────────────────

    func updateCutout() {
        let vw = view.bounds.width
        let vh = view.bounds.height
        guard vw > 0, vh > 0 else { return }

        // Card rectangle — centred, shifted slightly up so MRZ area sits at the centre
        let cardW = vw * cardWidthRatio
        let cardH = cardW / cardAspectRatio
        let cardX = (vw - cardW) / 2
        let cardY = (vh - cardH) / 2 - cardH * 0.08
        cardRect = CGRect(x: cardX, y: cardY, width: cardW, height: cardH)

        let cr: CGFloat = 12 // corner radius

        // 1) Dark overlay with transparent card-shaped hole
        let full = UIBezierPath(rect: overlayView.bounds)
        full.append(UIBezierPath(roundedRect: cardRect, cornerRadius: cr))
        maskLayer.path = full.cgPath

        // 2) Thin card border
        cardBorderLayer.path = UIBezierPath(roundedRect: cardRect, cornerRadius: cr).cgPath

        // 3) Corner brackets
        layoutCornerBrackets(cornerRadius: cr)

        // 4) Chip icon (upper-left inside card)
        let chipW: CGFloat = 44
        let chipH: CGFloat = 34
        chipView.frame = CGRect(
            x: cardRect.minX + cardW * 0.07,
            y: cardRect.minY + cardH * 0.22,
            width: chipW,
            height: chipH
        )
        layoutChipInternals()

        // 5) MRZ line indicators (bottom of card)
        let mrzInset: CGFloat = 16
        let mrzH = cardH * 0.28
        mrzLinesContainer.frame = CGRect(
            x: cardRect.minX + mrzInset,
            y: cardRect.maxY - mrzH - mrzInset * 0.7,
            width: cardW - 2 * mrzInset,
            height: mrzH
        )
        layoutMRZLines()

        // 6) Scan line
        scanLineView.frame = CGRect(
            x: cardRect.minX + 8,
            y: mrzLinesContainer.frame.minY,
            width: cardW - 16,
            height: 2
        )
        startScanLineAnimation()

        // 7) Hint label below card
        hintLabel.frame = CGRect(
            x: cardRect.minX - 10,
            y: cardRect.maxY + 24,
            width: cardW + 20,
            height: 50
        )
    }

    // MARK: Corner brackets

    private func layoutCornerBrackets(cornerRadius cr: CGFloat) {
        let len: CGFloat = 28
        let r = cardRect

        // Top-left
        let tl = UIBezierPath()
        tl.move(to: CGPoint(x: r.minX, y: r.minY + cr + len))
        tl.addLine(to: CGPoint(x: r.minX, y: r.minY + cr))
        tl.addArc(withCenter: CGPoint(x: r.minX + cr, y: r.minY + cr),
                   radius: cr, startAngle: .pi, endAngle: -.pi / 2, clockwise: true)
        tl.addLine(to: CGPoint(x: r.minX + cr + len, y: r.minY))
        cornerLayers[0].path = tl.cgPath

        // Top-right
        let tr = UIBezierPath()
        tr.move(to: CGPoint(x: r.maxX - cr - len, y: r.minY))
        tr.addLine(to: CGPoint(x: r.maxX - cr, y: r.minY))
        tr.addArc(withCenter: CGPoint(x: r.maxX - cr, y: r.minY + cr),
                   radius: cr, startAngle: -.pi / 2, endAngle: 0, clockwise: true)
        tr.addLine(to: CGPoint(x: r.maxX, y: r.minY + cr + len))
        cornerLayers[1].path = tr.cgPath

        // Bottom-left
        let bl = UIBezierPath()
        bl.move(to: CGPoint(x: r.minX, y: r.maxY - cr - len))
        bl.addLine(to: CGPoint(x: r.minX, y: r.maxY - cr))
        bl.addArc(withCenter: CGPoint(x: r.minX + cr, y: r.maxY - cr),
                   radius: cr, startAngle: .pi, endAngle: .pi / 2, clockwise: false)
        bl.addLine(to: CGPoint(x: r.minX + cr + len, y: r.maxY))
        cornerLayers[2].path = bl.cgPath

        // Bottom-right
        let br = UIBezierPath()
        br.move(to: CGPoint(x: r.maxX - cr - len, y: r.maxY))
        br.addLine(to: CGPoint(x: r.maxX - cr, y: r.maxY))
        br.addArc(withCenter: CGPoint(x: r.maxX - cr, y: r.maxY - cr),
                   radius: cr, startAngle: .pi / 2, endAngle: 0, clockwise: false)
        br.addLine(to: CGPoint(x: r.maxX, y: r.maxY - cr - len))
        cornerLayers[3].path = br.cgPath
    }

    // MARK: Chip internals

    private func layoutChipInternals() {
        let b = chipView.bounds
        guard b.width > 0 else { return }

        let lw: CGFloat = 0.8
        let pad: CGFloat = 5
        let count = 4
        let spacing = (b.height - 2 * pad) / CGFloat(count)

        for i in 0..<count {
            if let line = chipView.viewWithTag(100 + i) {
                let y = pad + CGFloat(i) * spacing + spacing / 2 - lw / 2
                line.frame = CGRect(x: pad, y: y, width: b.width - 2 * pad, height: lw)
            }
        }
        if let vLine = chipView.viewWithTag(200) {
            vLine.frame = CGRect(x: b.width / 2 - lw / 2, y: pad, width: lw, height: b.height - 2 * pad)
        }
    }

    // MARK: MRZ line indicators

    private func layoutMRZLines() {
        mrzLinesContainer.subviews.forEach { $0.removeFromSuperview() }
        let b = mrzLinesContainer.bounds
        guard b.width > 0 else { return }

        let lineCount = 3
        let lineH: CGFloat = 2.0
        let gap = (b.height - CGFloat(lineCount) * lineH) / CGFloat(lineCount + 1)

        for i in 0..<lineCount {
            let line = UIView()
            line.backgroundColor = UIColor.white.withAlphaComponent(0.18)
            line.layer.cornerRadius = 1
            let y = gap + CGFloat(i) * (lineH + gap)
            line.frame = CGRect(x: 0, y: y, width: b.width, height: lineH)
            mrzLinesContainer.addSubview(line)
        }
    }

    // MARK: Scan line animation

    private func startScanLineAnimation() {
        scanLineView.layer.removeAllAnimations()
        let mrzFrame = mrzLinesContainer.frame
        guard mrzFrame.height > 0 else { return }

        scanLineView.frame.origin.y = mrzFrame.minY
        scanLineView.alpha = 0.7

        UIView.animate(withDuration: 2.0, delay: 0,
                       options: [.repeat, .autoreverse, .curveEaseInOut],
                       animations: {
            self.scanLineView.frame.origin.y = mrzFrame.maxY - 2
        })
    }

    // ─────────────────────────────────────────────
    // MARK: – Orientation
    // ─────────────────────────────────────────────

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

    // ─────────────────────────────────────────────
    // MARK: – Camera
    // ─────────────────────────────────────────────

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
        } catch {}

        captureSession.startRunning()
    }

    func showString(string: String) {
        captureSessionQueue.sync {
            self.captureSession.stopRunning()
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

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
