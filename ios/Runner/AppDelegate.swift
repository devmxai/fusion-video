import UIKit
import Flutter

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let registrar = self.registrar(forPlugin: "FusionPreviewSurface") {
      registrar.register(FusionPreviewViewFactory(), withId: "fusion_video/preview_surface")
      let channel = FlutterMethodChannel(
        name: "fusion_video/preview_session",
        binaryMessenger: registrar.messenger()
      )
      channel.setMethodCallHandler { call, result in
        guard call.method == "updatePreview" else {
          result(FlutterMethodNotImplemented)
          return
        }

        guard
          let args = call.arguments as? [String: Any],
          let projectId = args["projectId"] as? Int64,
          let positionSeconds = args["positionSeconds"] as? Double,
          let isPlaying = args["isPlaying"] as? Bool
        else {
          result(
            FlutterError(
              code: "invalid_args",
              message: "Missing preview session arguments",
              details: nil
            )
          )
          return
        }

        FusionPreviewRegistry.shared.update(
          projectId: projectId,
          positionSeconds: positionSeconds,
          isPlaying: isPlaying
        )
        result(nil)
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

private final class FusionPreviewRegistry {
  static let shared = FusionPreviewRegistry()

  private var views: [Int64: NSHashTable<FusionPreviewNativeView>] = [:]

  private init() {}

  func attach(view: FusionPreviewNativeView, projectId: Int64) {
    let bucket = views[projectId] ?? NSHashTable<FusionPreviewNativeView>.weakObjects()
    bucket.add(view)
    views[projectId] = bucket
  }

  func detach(view: FusionPreviewNativeView, projectId: Int64) {
    views[projectId]?.remove(view)
  }

  func update(projectId: Int64, positionSeconds: Double, isPlaying: Bool) {
    views[projectId]?.allObjects.forEach {
      $0.update(positionSeconds: positionSeconds, isPlaying: isPlaying)
    }
  }
}

private final class FusionPreviewViewFactory: NSObject, FlutterPlatformViewFactory {
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    let projectId = (args as? [String: Any]).flatMap { $0["projectId"] as? Int64 } ?? viewId
    return FusionPreviewPlatformView(frame: frame, projectId: projectId)
  }
}

private final class FusionPreviewPlatformView: NSObject, FlutterPlatformView {
  private let previewView: FusionPreviewNativeView

  init(frame: CGRect, projectId: Int64) {
    self.previewView = FusionPreviewNativeView(frame: frame, projectId: projectId)
    super.init()
  }

  func view() -> UIView {
    previewView
  }
}

private final class FusionPreviewNativeView: UIView {
  private let projectId: Int64
  private let highlightLayer = CAGradientLayer()
  private let titleLabel = UILabel()
  private let statusLabel = UILabel()
  private let progressTrack = UIView()
  private let progressFill = UIView()

  init(frame: CGRect, projectId: Int64) {
    self.projectId = projectId
    super.init(frame: frame)
    setupUI()
    FusionPreviewRegistry.shared.attach(view: self, projectId: projectId)
    update(positionSeconds: 0, isPlaying: false)
  }

  required init?(coder: NSCoder) {
    return nil
  }

  deinit {
    FusionPreviewRegistry.shared.detach(view: self, projectId: projectId)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    highlightLayer.frame = bounds
    let inset: CGFloat = 18
    titleLabel.frame = CGRect(x: inset, y: 18, width: bounds.width - inset * 2, height: 22)
    statusLabel.frame = CGRect(x: inset, y: titleLabel.frame.maxY + 8, width: bounds.width - inset * 2, height: 18)
    progressTrack.frame = CGRect(x: inset, y: bounds.height - 34, width: bounds.width - inset * 2, height: 6)
    updateProgressWidth()
  }

  func update(positionSeconds: Double, isPlaying: Bool) {
    currentPosition = positionSeconds
    isCurrentlyPlaying = isPlaying
    statusLabel.text = String(format: "%@  %.2fs", isPlaying ? "Playing" : "Paused", positionSeconds)
    updateProgressWidth()
  }

  private var currentPosition: Double = 0
  private var isCurrentlyPlaying = false

  private func setupUI() {
    backgroundColor = UIColor(red: 0.06, green: 0.06, blue: 0.07, alpha: 1)
    layer.cornerRadius = 8
    clipsToBounds = true

    highlightLayer.colors = [
      UIColor(white: 1, alpha: 0.04).cgColor,
      UIColor.clear.cgColor,
      UIColor(white: 0, alpha: 0.2).cgColor
    ]
    highlightLayer.startPoint = CGPoint(x: 0, y: 0)
    highlightLayer.endPoint = CGPoint(x: 1, y: 1)
    highlightLayer.frame = bounds
    layer.addSublayer(highlightLayer)

    titleLabel.text = "Fusion Native Preview"
    titleLabel.textColor = UIColor(white: 1, alpha: 0.92)
    titleLabel.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
    addSubview(titleLabel)

    statusLabel.textColor = UIColor(white: 1, alpha: 0.58)
    statusLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
    addSubview(statusLabel)

    progressTrack.backgroundColor = UIColor(white: 1, alpha: 0.08)
    progressTrack.layer.cornerRadius = 3
    addSubview(progressTrack)

    progressFill.backgroundColor = UIColor(red: 0.36, green: 0.87, blue: 0.35, alpha: 1)
    progressFill.layer.cornerRadius = 3
    progressTrack.addSubview(progressFill)
  }

  private func updateProgressWidth() {
    guard progressTrack.bounds.width > 0 else { return }
    let progress = min(max(currentPosition / 5.0, 0), 1)
    progressFill.frame = CGRect(
      x: 0,
      y: 0,
      width: progressTrack.bounds.width * progress,
      height: progressTrack.bounds.height
    )
  }
}
