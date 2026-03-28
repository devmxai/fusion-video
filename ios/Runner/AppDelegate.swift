import UIKit
import Flutter
import AVFoundation

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
      let probeChannel = FlutterMethodChannel(
        name: "fusion_video/media_probe",
        binaryMessenger: registrar.messenger()
      )
      probeChannel.setMethodCallHandler { call, result in
        guard call.method == "probeMedia" else {
          result(FlutterMethodNotImplemented)
          return
        }
        guard
          let args = call.arguments as? [String: Any],
          let path = args["path"] as? String,
          let kind = args["kind"] as? String
        else {
          result(
            FlutterError(
              code: "invalid_args",
              message: "Missing probe arguments",
              details: nil
            )
          )
          return
        }
        result(FusionMediaProbe.probe(path: path, kind: kind))
      }
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
          sourcePath: args["sourcePath"] as? String,
          sourceKind: args["sourceKind"] as? String,
          sourceStartSeconds: args["sourceStartSeconds"] as? Double,
          sourceEndSeconds: args["sourceEndSeconds"] as? Double,
          positionSeconds: positionSeconds,
          isPlaying: isPlaying
        )
        result(nil)
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

private enum FusionMediaProbe {
  static func probe(path: String, kind: String) -> [String: Any]? {
    switch kind {
    case "video":
      let url = URL(fileURLWithPath: path)
      let asset = AVURLAsset(url: url)
      let duration = asset.duration.seconds
      guard let track = asset.tracks(withMediaType: .video).first else {
        return [
          "durationSeconds": duration.isFinite ? duration : 0
        ]
      }
      let transformed = track.naturalSize.applying(track.preferredTransform)
      return [
        "durationSeconds": duration.isFinite ? duration : 0,
        "width": Int(abs(transformed.width)),
        "height": Int(abs(transformed.height))
      ]
    case "image":
      guard let image = UIImage(contentsOfFile: path) else {
        return nil
      }
      return [
        "width": Int(image.size.width * image.scale),
        "height": Int(image.size.height * image.scale)
      ]
    default:
      return nil
    }
  }
}

private final class FusionPreviewRegistry {
  static let shared = FusionPreviewRegistry()

  private var views: [Int64: NSHashTable<FusionPreviewNativeView>] = [:]
  private var payloads: [Int64: FusionPreviewPayload] = [:]

  private init() {}

  func attach(view: FusionPreviewNativeView, projectId: Int64) {
    let bucket = views[projectId] ?? NSHashTable<FusionPreviewNativeView>.weakObjects()
    bucket.add(view)
    views[projectId] = bucket
    if let payload = payloads[projectId] {
      view.update(
        sourcePath: payload.sourcePath,
        sourceKind: payload.sourceKind,
        sourceStartSeconds: payload.sourceStartSeconds,
        sourceEndSeconds: payload.sourceEndSeconds,
        positionSeconds: payload.positionSeconds,
        isPlaying: payload.isPlaying
      )
    }
  }

  func detach(view: FusionPreviewNativeView, projectId: Int64) {
    views[projectId]?.remove(view)
  }

  func update(
    projectId: Int64,
    sourcePath: String?,
    sourceKind: String?,
    sourceStartSeconds: Double?,
    sourceEndSeconds: Double?,
    positionSeconds: Double,
    isPlaying: Bool
  ) {
    payloads[projectId] = FusionPreviewPayload(
      sourcePath: sourcePath,
      sourceKind: sourceKind,
      sourceStartSeconds: sourceStartSeconds,
      sourceEndSeconds: sourceEndSeconds,
      positionSeconds: positionSeconds,
      isPlaying: isPlaying
    )
    views[projectId]?.allObjects.forEach {
      $0.update(
        sourcePath: sourcePath,
        sourceKind: sourceKind,
        sourceStartSeconds: sourceStartSeconds,
        sourceEndSeconds: sourceEndSeconds,
        positionSeconds: positionSeconds,
        isPlaying: isPlaying
      )
    }
  }
}

private struct FusionPreviewPayload {
  let sourcePath: String?
  let sourceKind: String?
  let sourceStartSeconds: Double?
  let sourceEndSeconds: Double?
  let positionSeconds: Double
  let isPlaying: Bool
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
  private let imageView = UIImageView()
  private let playerLayer = AVPlayerLayer()
  private var player: AVPlayer?
  private var playbackObserverToken: Any?
  private var currentSourcePath: String?
  private var currentSourceKind: String?
  private var currentSourceStartSeconds: Double = 0
  private var currentSourceEndSeconds: Double?

  init(frame: CGRect, projectId: Int64) {
    self.projectId = projectId
    super.init(frame: frame)
    setupUI()
    FusionPreviewRegistry.shared.attach(view: self, projectId: projectId)
    update(
      sourcePath: nil,
      sourceKind: nil,
      sourceStartSeconds: nil,
      sourceEndSeconds: nil,
      positionSeconds: 0,
      isPlaying: false
    )
  }

  required init?(coder: NSCoder) {
    return nil
  }

  deinit {
    player?.pause()
    removePlaybackObserver()
    playerLayer.player = nil
    FusionPreviewRegistry.shared.detach(view: self, projectId: projectId)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    imageView.frame = bounds
    playerLayer.frame = bounds
  }

  func update(
    sourcePath: String?,
    sourceKind: String?,
    sourceStartSeconds: Double?,
    sourceEndSeconds: Double?,
    positionSeconds: Double,
    isPlaying: Bool
  ) {
    let sourceChanged = sourcePath != currentSourcePath || sourceKind != currentSourceKind
    currentSourcePath = sourcePath
    currentSourceKind = sourceKind
    currentSourceStartSeconds = max(0, sourceStartSeconds ?? 0)
    currentSourceEndSeconds = sourceEndSeconds
    currentPosition = positionSeconds
    isCurrentlyPlaying = isPlaying
    if sourceChanged {
      loadSource()
    }
    applyTransport()
  }

  private var currentPosition: Double = 0
  private var isCurrentlyPlaying = false

  private func setupUI() {
    backgroundColor = .black
    clipsToBounds = true

    imageView.frame = bounds
    imageView.contentMode = .scaleAspectFill
    imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    imageView.isHidden = true
    addSubview(imageView)

    playerLayer.videoGravity = .resizeAspectFill
    playerLayer.frame = bounds
    layer.addSublayer(playerLayer)
    playerLayer.isHidden = true
  }

  private func loadSource() {
    guard let sourceKind = currentSourceKind, let sourcePath = currentSourcePath else {
      player?.pause()
      removePlaybackObserver()
      player = nil
      playerLayer.player = nil
      playerLayer.isHidden = true
      imageView.image = nil
      imageView.isHidden = true
      return
    }

    switch sourceKind {
    case "video":
      imageView.image = nil
      imageView.isHidden = true
      let url = URL(fileURLWithPath: sourcePath)
      let newPlayer = AVPlayer(url: url)
      newPlayer.actionAtItemEnd = .pause
      removePlaybackObserver()
      player = newPlayer
      playerLayer.player = newPlayer
      playerLayer.isHidden = false
      addPlaybackObserver(to: newPlayer)
    case "image":
      player?.pause()
      removePlaybackObserver()
      player = nil
      playerLayer.player = nil
      playerLayer.isHidden = true
      imageView.image = UIImage(contentsOfFile: sourcePath)
      imageView.isHidden = false
    default:
      player?.pause()
      removePlaybackObserver()
      player = nil
      playerLayer.player = nil
      playerLayer.isHidden = true
      imageView.image = nil
      imageView.isHidden = true
    }
  }

  private func applyTransport() {
    guard currentSourceKind == "video", let player else { return }

    let targetSeconds = clampedPositionSeconds(currentPosition)
    let target = CMTime(seconds: targetSeconds, preferredTimescale: 600)
    let current = player.currentTime().seconds
    let shouldSeek = !current.isFinite || abs(current - targetSeconds) > 0.04

    let playOrPause = { [weak self] in
      guard let self else { return }
      let currentSeconds = player.currentTime().seconds
      if let endSeconds = self.currentSourceEndSeconds,
         currentSeconds.isFinite,
         currentSeconds >= endSeconds - 0.015
      {
        player.pause()
        return
      }
      if self.isCurrentlyPlaying {
        player.play()
      } else {
        player.pause()
      }
    }

    if shouldSeek {
      player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
        playOrPause()
      }
    } else {
      playOrPause()
    }
  }

  private func addPlaybackObserver(to player: AVPlayer) {
    playbackObserverToken = player.addPeriodicTimeObserver(
      forInterval: CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600),
      queue: .main
    ) { [weak self, weak player] _ in
      guard let self, let player else { return }
      guard let endSeconds = self.currentSourceEndSeconds else { return }
      let currentSeconds = player.currentTime().seconds
      if currentSeconds.isFinite && currentSeconds >= endSeconds - 0.015 {
        player.pause()
        player.seek(
          to: CMTime(seconds: endSeconds, preferredTimescale: 600),
          toleranceBefore: .zero,
          toleranceAfter: .zero
        )
      }
    }
  }

  private func removePlaybackObserver() {
    if let playbackObserverToken, let player {
      player.removeTimeObserver(playbackObserverToken)
    }
    playbackObserverToken = nil
  }

  private func clampedPositionSeconds(_ seconds: Double) -> Double {
    let lowerBound = currentSourceStartSeconds
    if let upperBound = currentSourceEndSeconds {
      return min(max(seconds, lowerBound), upperBound)
    }
    return max(seconds, lowerBound)
  }
}
