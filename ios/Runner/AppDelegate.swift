import UIKit
import Flutter
import AVFoundation
import QuartzCore

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  private let previewEngineHost = FusionPreviewEngineHost()

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
      let previewEngineChannel = FlutterMethodChannel(
        name: "fusion_video/preview_engine",
        binaryMessenger: registrar.messenger()
      )
      let previewEventsChannel = FlutterEventChannel(
        name: "fusion_video/preview_events",
        binaryMessenger: registrar.messenger()
      )
      let probeChannel = FlutterMethodChannel(
        name: "fusion_video/media_probe",
        binaryMessenger: registrar.messenger()
      )
      let exportChannel = FlutterMethodChannel(
        name: "fusion_video/export_session",
        binaryMessenger: registrar.messenger()
      )
      probeChannel.setMethodCallHandler { call, result in
        if call.method == "probeMedia" {
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
          return
        }
        if call.method == "generateVideoThumbnails" {
          guard
            let args = call.arguments as? [String: Any],
            let path = args["path"] as? String,
            let timestampsSeconds = args["timestampsSeconds"] as? [Double]
          else {
            result(
              FlutterError(
                code: "invalid_args",
                message: "Missing thumbnail arguments",
                details: nil
              )
            )
            return
          }
          let targetWidth = (args["targetWidth"] as? NSNumber)?.intValue ?? 80
          let targetHeight = (args["targetHeight"] as? NSNumber)?.intValue ?? 48
          DispatchQueue.global(qos: .userInitiated).async {
            let thumbnails = FusionMediaThumbnailGenerator.generateVideoThumbnails(
              path: path,
              timestampsSeconds: timestampsSeconds,
              targetWidth: targetWidth,
              targetHeight: targetHeight
            )
            DispatchQueue.main.async {
              result(thumbnails)
            }
          }
          return
        }
        result(FlutterMethodNotImplemented)
      }
      exportChannel.setMethodCallHandler { call, result in
        switch call.method {
        case "startExport":
          guard let args = call.arguments as? [String: Any] else {
            result(
              FlutterError(
                code: "invalid_args",
                message: "Missing export arguments",
                details: nil
              )
            )
            return
          }
          do {
            result(try FusionExportRegistry.shared.startExport(arguments: args))
          } catch let error as FusionExportError {
            result(
              FlutterError(
                code: error.code,
                message: error.message,
                details: nil
              )
            )
          } catch {
            result(
              FlutterError(
                code: "export_failed",
                message: error.localizedDescription,
                details: nil
              )
            )
          }
        case "pollExport":
          guard
            let args = call.arguments as? [String: Any],
            let jobId = args["jobId"] as? String
          else {
            result(
              FlutterError(
                code: "invalid_args",
                message: "Missing export polling arguments",
                details: nil
              )
            )
            return
          }
          result(FusionExportRegistry.shared.pollStatus(jobId: jobId))
        case "cancelExport":
          guard
            let args = call.arguments as? [String: Any],
            let jobId = args["jobId"] as? String
          else {
            result(
              FlutterError(
                code: "invalid_args",
                message: "Missing export cancel arguments",
                details: nil
              )
            )
            return
          }
          FusionExportRegistry.shared.cancel(jobId: jobId)
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
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
          transportRevision: (args["transportRevision"] as? NSNumber)?.int64Value ?? 0,
          sourceId: args["sourceId"] as? String,
          sourcePath: args["sourcePath"] as? String,
          sourceKind: args["sourceKind"] as? String,
          upcomingSourceId: args["upcomingSourceId"] as? String,
          upcomingSourcePath: args["upcomingSourcePath"] as? String,
          upcomingSourceKind: args["upcomingSourceKind"] as? String,
          clipStartSeconds: args["clipStartSeconds"] as? Double,
          clipEndSeconds: args["clipEndSeconds"] as? Double,
          sourceStartSeconds: args["sourceStartSeconds"] as? Double,
          sourceEndSeconds: args["sourceEndSeconds"] as? Double,
          upcomingSourceStartSeconds: args["upcomingSourceStartSeconds"] as? Double,
          upcomingSourceEndSeconds: args["upcomingSourceEndSeconds"] as? Double,
          projectWidth: args["projectWidth"] as? Int,
          projectHeight: args["projectHeight"] as? Int,
          baseClipId: args["baseClipId"] as? String,
          baseClipIds: args["baseClipIds"] as? [String] ?? [],
          selectedClipId: args["selectedClipId"] as? String,
          baseAudioGain: args["baseAudioGain"] as? Double,
          baseAudioMuted: args["baseAudioMuted"] as? Bool,
          sceneNodes: args["sceneNodes"] as? [[String: Any]] ?? [],
          audioNodes: args["audioNodes"] as? [[String: Any]] ?? [],
          positionSeconds: positionSeconds,
          isPlaying: isPlaying
        )
        result(nil)
      }
      previewEngineChannel.setMethodCallHandler { call, result in
        switch call.method {
        case "isEnginePreviewAvailable":
          result(self.previewEngineHost.isScaffoldReady)
        case "configurePreviewEngine":
          guard
            let args = call.arguments as? [String: Any],
            let projectId = args["projectId"] as? Int64,
            let positionSeconds = args["positionSeconds"] as? Double,
            let isPlaying = args["isPlaying"] as? Bool
          else {
            result(
              FlutterError(
                code: "invalid_args",
                message: "Missing preview engine arguments",
                details: nil
              )
            )
            return
          }

          self.previewEngineHost.configurePreviewEngine(
            FusionPreviewResolvedConfiguration(
              projectId: projectId,
              positionSeconds: positionSeconds,
              isPlaying: isPlaying,
              transportRevision: (args["transportRevision"] as? NSNumber)?.int64Value ?? 0,
              sourceId: args["sourceId"] as? String,
              sourcePath: args["sourcePath"] as? String,
              sourceKind: args["sourceKind"] as? String,
              upcomingSourceId: args["upcomingSourceId"] as? String,
              upcomingSourcePath: args["upcomingSourcePath"] as? String,
              upcomingSourceKind: args["upcomingSourceKind"] as? String,
              clipStartSeconds: args["clipStartSeconds"] as? Double,
              clipEndSeconds: args["clipEndSeconds"] as? Double,
              sourceStartSeconds: args["sourceStartSeconds"] as? Double,
              sourceEndSeconds: args["sourceEndSeconds"] as? Double,
              upcomingSourceStartSeconds: args["upcomingSourceStartSeconds"] as? Double,
              upcomingSourceEndSeconds: args["upcomingSourceEndSeconds"] as? Double,
              projectWidth: args["projectWidth"] as? Int,
              projectHeight: args["projectHeight"] as? Int,
              baseClipId: args["baseClipId"] as? String,
              baseClipIds: args["baseClipIds"] as? [String] ?? [],
              selectedClipId: args["selectedClipId"] as? String,
              continuityKind: args["continuityKind"] as? String,
              sceneNodes: args["sceneNodes"] as? [[String: Any]] ?? [],
              audioNodes: args["audioNodes"] as? [[String: Any]] ?? []
            )
          )

          FusionPreviewRegistry.shared.update(
            projectId: projectId,
            transportRevision: (args["transportRevision"] as? NSNumber)?.int64Value ?? 0,
            sourceId: args["sourceId"] as? String,
            sourcePath: args["sourcePath"] as? String,
            sourceKind: args["sourceKind"] as? String,
            upcomingSourceId: args["upcomingSourceId"] as? String,
            upcomingSourcePath: args["upcomingSourcePath"] as? String,
            upcomingSourceKind: args["upcomingSourceKind"] as? String,
            clipStartSeconds: args["clipStartSeconds"] as? Double,
            clipEndSeconds: args["clipEndSeconds"] as? Double,
            sourceStartSeconds: args["sourceStartSeconds"] as? Double,
            sourceEndSeconds: args["sourceEndSeconds"] as? Double,
            upcomingSourceStartSeconds: args["upcomingSourceStartSeconds"] as? Double,
            upcomingSourceEndSeconds: args["upcomingSourceEndSeconds"] as? Double,
            projectWidth: args["projectWidth"] as? Int,
            projectHeight: args["projectHeight"] as? Int,
            baseClipId: args["baseClipId"] as? String,
            baseClipIds: args["baseClipIds"] as? [String] ?? [],
            selectedClipId: args["selectedClipId"] as? String,
            baseAudioGain: args["baseAudioGain"] as? Double,
            baseAudioMuted: args["baseAudioMuted"] as? Bool,
            sceneNodes: args["sceneNodes"] as? [[String: Any]] ?? [],
            audioNodes: args["audioNodes"] as? [[String: Any]] ?? [],
            positionSeconds: positionSeconds,
            isPlaying: isPlaying
          )
          result(nil)
        case "dispatchPreviewCommand":
          guard
            let args = call.arguments as? [String: Any],
            let projectId = args["projectId"] as? Int64,
            let transportRevision = (args["transportRevision"] as? NSNumber)?.int64Value,
            let commandKind = args["kind"] as? String
          else {
            result(
              FlutterError(
                code: "invalid_args",
                message: "Missing preview command arguments",
                details: nil
              )
            )
            return
          }
          self.previewEngineHost.dispatchPreviewCommand(
            FusionPreviewTransportCommandEnvelope(
              projectId: projectId,
              transportRevision: transportRevision,
              kind: commandKind,
              positionSeconds: args["positionSeconds"] as? Double,
              isPlaying: args["isPlaying"] as? Bool
            )
          )
          FusionPreviewRegistry.shared.dispatchCommand(
            projectId: projectId,
            transportRevision: transportRevision,
            commandKind: commandKind,
            positionSeconds: args["positionSeconds"] as? Double,
            isPlaying: args["isPlaying"] as? Bool
          )
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
      previewEventsChannel.setStreamHandler(FusionPreviewEventsStreamHandler.shared)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

private enum FusionMediaThumbnailGenerator {
  static func generateVideoThumbnails(
    path: String,
    timestampsSeconds: [Double],
    targetWidth: Int,
    targetHeight: Int
  ) -> [FlutterStandardTypedData] {
    guard !timestampsSeconds.isEmpty else {
      return []
    }

    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: max(targetWidth, 24), height: max(targetHeight, 24))

    var thumbnails: [FlutterStandardTypedData] = []
    for second in timestampsSeconds {
      let time = CMTime(seconds: max(second, 0), preferredTimescale: 600)
      guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else {
        continue
      }
      let image = UIImage(cgImage: cgImage)
      guard let data = image.pngData() else {
        continue
      }
      thumbnails.append(FlutterStandardTypedData(bytes: data))
    }
    return thumbnails
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
    case "audio":
      let url = URL(fileURLWithPath: path)
      let asset = AVURLAsset(url: url)
      let duration = asset.duration.seconds
      return [
        "durationSeconds": duration.isFinite ? duration : 0
      ]
    default:
      return nil
    }
  }
}

private struct FusionExportError: Error {
  let code: String
  let message: String
}

private struct FusionExportSceneNode {
  let clipId: String
  let assetId: String
  let kind: String
  let localPath: String
  let displayLabel: String?
  let clipStartSeconds: Double
  let clipEndSeconds: Double
  let sourceStartSeconds: Double
  let sourceEndSeconds: Double
  let x: Double
  let y: Double
  let width: Double
  let height: Double
  let opacity: Double
  let rotationDegrees: Double
  let zIndex: Int

  init?(map: [String: Any]) {
    guard
      let clipId = map["clipId"] as? String,
      let assetId = map["assetId"] as? String,
      let kind = map["kind"] as? String,
      let localPath = map["localPath"] as? String
    else {
      return nil
    }
    self.clipId = clipId
    self.assetId = assetId
    self.kind = kind
    self.localPath = localPath
    self.displayLabel = map["displayLabel"] as? String
    self.clipStartSeconds = (map["clipStartSeconds"] as? NSNumber)?.doubleValue ?? 0
    self.clipEndSeconds = (map["clipEndSeconds"] as? NSNumber)?.doubleValue ?? 0
    self.sourceStartSeconds = (map["sourceStartSeconds"] as? NSNumber)?.doubleValue ?? 0
    self.sourceEndSeconds = (map["sourceEndSeconds"] as? NSNumber)?.doubleValue ?? 0
    self.x = (map["x"] as? NSNumber)?.doubleValue ?? 0
    self.y = (map["y"] as? NSNumber)?.doubleValue ?? 0
    self.width = (map["width"] as? NSNumber)?.doubleValue ?? 0
    self.height = (map["height"] as? NSNumber)?.doubleValue ?? 0
    self.opacity = (map["opacity"] as? NSNumber)?.doubleValue ?? 1
    self.rotationDegrees = (map["rotationDegrees"] as? NSNumber)?.doubleValue ?? 0
    self.zIndex = (map["zIndex"] as? NSNumber)?.intValue ?? 0
  }
}

private struct FusionExportAudioNode {
  let clipId: String
  let assetId: String
  let kind: String
  let localPath: String
  let displayLabel: String?
  let clipStartSeconds: Double
  let clipEndSeconds: Double
  let sourceStartSeconds: Double
  let sourceEndSeconds: Double
  let gain: Float
  let isMuted: Bool

  init?(map: [String: Any]) {
    guard
      let clipId = map["clipId"] as? String,
      let assetId = map["assetId"] as? String,
      let kind = map["kind"] as? String,
      let localPath = map["localPath"] as? String
    else {
      return nil
    }
    self.clipId = clipId
    self.assetId = assetId
    self.kind = kind
    self.localPath = localPath
    self.displayLabel = map["displayLabel"] as? String
    self.clipStartSeconds = (map["clipStartSeconds"] as? NSNumber)?.doubleValue ?? 0
    self.clipEndSeconds = (map["clipEndSeconds"] as? NSNumber)?.doubleValue ?? 0
    self.sourceStartSeconds = (map["sourceStartSeconds"] as? NSNumber)?.doubleValue ?? 0
    self.sourceEndSeconds = (map["sourceEndSeconds"] as? NSNumber)?.doubleValue ?? 0
    self.gain = Float((map["gain"] as? NSNumber)?.doubleValue ?? 1)
    self.isMuted = (map["isMuted"] as? Bool) ?? false
  }
}

private final class FusionExportRegistry {
  static let shared = FusionExportRegistry()

  private var jobs: [String: FusionNativeExportJob] = [:]

  private init() {}

  func startExport(arguments: [String: Any]) throws -> [String: Any] {
    guard let sourcePath = arguments["sourcePath"] as? String else {
      throw FusionExportError(
        code: "invalid_args",
        message: "Missing export source path"
      )
    }
    guard let sourceKind = arguments["sourceKind"] as? String, sourceKind == "video" else {
      throw FusionExportError(
        code: "unsupported_source_kind",
        message: "Export foundation currently supports video clips only."
      )
    }

    let sourceStartSeconds = max(0, arguments["sourceStartSeconds"] as? Double ?? 0)
    let sourceEndSeconds = arguments["sourceEndSeconds"] as? Double
    let projectWidth = (arguments["projectWidth"] as? NSNumber)?.intValue
    let projectHeight = (arguments["projectHeight"] as? NSNumber)?.intValue
    let clipStartSeconds = max(0, arguments["clipStartSeconds"] as? Double ?? 0)
    let clipEndSeconds = arguments["clipEndSeconds"] as? Double
    let audioGain = Float((arguments["audioGain"] as? NSNumber)?.doubleValue ?? 1.0)
    let isMuted = (arguments["isMuted"] as? Bool) ?? false
    let sceneNodes =
      ((arguments["sceneNodes"] as? [[String: Any]]) ?? []).compactMap(FusionExportSceneNode.init)
    let audioNodes =
      ((arguments["audioNodes"] as? [[String: Any]]) ?? []).compactMap(FusionExportAudioNode.init)
    let outputFileName =
      (arguments["outputFileName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    let requestedName = (outputFileName?.isEmpty == false ? outputFileName : nil)
      ?? "fusion_export_\(Int(Date().timeIntervalSince1970)).mp4"
    let job = try FusionNativeExportJob(
      jobId: UUID().uuidString,
      sourcePath: sourcePath,
      sourceStartSeconds: sourceStartSeconds,
      sourceEndSeconds: sourceEndSeconds,
      projectWidth: projectWidth,
      projectHeight: projectHeight,
      clipStartSeconds: clipStartSeconds,
      clipEndSeconds: clipEndSeconds,
      audioGain: audioGain,
      isMuted: isMuted,
      sceneNodes: sceneNodes,
      audioNodes: audioNodes,
      outputFileName: requestedName
    )
    jobs[job.jobId] = job
    job.start { [weak self] in
      if job.isTerminal {
        self?.jobs[job.jobId] = job
      }
    }
    return job.statusMap
  }

  func pollStatus(jobId: String) -> [String: Any] {
    guard let job = jobs[jobId] else {
      return [
        "jobId": jobId,
        "status": "failed",
        "progress": 0,
        "errorMessage": "Export job not found."
      ]
    }
    return job.statusMap
  }

  func cancel(jobId: String) {
    jobs[jobId]?.cancel()
  }
}

private final class FusionNativeExportJob {
  let jobId: String
  private let outputURL: URL
  private let session: AVAssetExportSession
  private var statusValue: String = "exporting"
  private var errorMessage: String?

  var isTerminal: Bool {
    statusValue == "completed" || statusValue == "failed" || statusValue == "cancelled"
  }

  var statusMap: [String: Any] {
    var map: [String: Any] = [
      "jobId": jobId,
      "status": statusValue,
      "progress": min(max(Double(session.progress), 0), 1),
    ]
    if statusValue == "completed" {
      map["outputPath"] = outputURL.path
      map["progress"] = 1.0
    }
    if let errorMessage {
      map["errorMessage"] = errorMessage
    }
    return map
  }

  init(
    jobId: String,
    sourcePath: String,
    sourceStartSeconds: Double,
    sourceEndSeconds: Double?,
    projectWidth: Int?,
    projectHeight: Int?,
    clipStartSeconds: Double,
    clipEndSeconds: Double?,
    audioGain: Float,
    isMuted: Bool,
    sceneNodes: [FusionExportSceneNode],
    audioNodes: [FusionExportAudioNode],
    outputFileName: String
  ) throws {
    self.jobId = jobId

    let asset = AVURLAsset(url: URL(fileURLWithPath: sourcePath))
    guard let sourceVideoTrack = asset.tracks(withMediaType: .video).first else {
      throw FusionExportError(
        code: "missing_video_track",
        message: "Export source does not contain a video track."
      )
    }
    let durationSeconds = asset.duration.seconds.isFinite ? asset.duration.seconds : 0
    let endSeconds = min(max(sourceEndSeconds ?? durationSeconds, sourceStartSeconds), durationSeconds)
    let exportTimeRange = CMTimeRange(
      start: CMTime(seconds: sourceStartSeconds, preferredTimescale: 600),
      end: CMTime(seconds: endSeconds, preferredTimescale: 600)
    )
    let exportClipStartSeconds = clipStartSeconds
    let exportClipEndSeconds = max(
      clipEndSeconds ?? (clipStartSeconds + (endSeconds - sourceStartSeconds)),
      exportClipStartSeconds
    )

    let composition = AVMutableComposition()
    guard let compositionVideoTrack = composition.addMutableTrack(
      withMediaType: .video,
      preferredTrackID: kCMPersistentTrackID_Invalid
    ) else {
      throw FusionExportError(
        code: "composition_video_track_failed",
        message: "Unable to create composition video track."
      )
    }
    try compositionVideoTrack.insertTimeRange(
      exportTimeRange,
      of: sourceVideoTrack,
      at: .zero
    )

    var audioMixInputParameters: [AVAudioMixInputParameters] = []
    if let sourceAudioTrack = asset.tracks(withMediaType: .audio).first,
       let compositionAudioTrack = composition.addMutableTrack(
         withMediaType: .audio,
         preferredTrackID: kCMPersistentTrackID_Invalid
       ) {
      try compositionAudioTrack.insertTimeRange(
        exportTimeRange,
        of: sourceAudioTrack,
        at: .zero
      )
      let inputParameters = AVMutableAudioMixInputParameters(track: compositionAudioTrack)
      let targetVolume: Float = isMuted ? 0.0 : audioGain
      inputParameters.setVolume(targetVolume, at: .zero)
      audioMixInputParameters.append(inputParameters)
    }

    for node in audioNodes where node.clipId != jobId && (node.kind == "audio" || node.kind == "video") {
      guard
        let overlap = fusionTimelineOverlap(
          exportClipStartSeconds: exportClipStartSeconds,
          exportClipEndSeconds: exportClipEndSeconds,
          nodeClipStartSeconds: node.clipStartSeconds,
          nodeClipEndSeconds: node.clipEndSeconds,
          nodeSourceStartSeconds: node.sourceStartSeconds
        ),
        overlap.durationSeconds > 0.02
      else {
        continue
      }

      let nodeAsset = AVURLAsset(url: URL(fileURLWithPath: node.localPath))
      guard let nodeAudioTrack = nodeAsset.tracks(withMediaType: .audio).first,
            let compositionAudioTrack = composition.addMutableTrack(
              withMediaType: .audio,
              preferredTrackID: kCMPersistentTrackID_Invalid
            )
      else {
        continue
      }

      let sourceRange = CMTimeRange(
        start: CMTime(seconds: overlap.sourceStartSeconds, preferredTimescale: 600),
        duration: CMTime(seconds: overlap.durationSeconds, preferredTimescale: 600)
      )
      try compositionAudioTrack.insertTimeRange(
        sourceRange,
        of: nodeAudioTrack,
        at: CMTime(seconds: overlap.insertAtSeconds, preferredTimescale: 600)
      )
      let inputParameters = AVMutableAudioMixInputParameters(track: compositionAudioTrack)
      let targetVolume: Float = node.isMuted ? 0.0 : node.gain
      inputParameters.setVolume(
        targetVolume,
        at: CMTime(seconds: overlap.insertAtSeconds, preferredTimescale: 600)
      )
      audioMixInputParameters.append(inputParameters)
    }

    let renderSize = fusionResolvedRenderSize(
      preferredWidth: projectWidth,
      preferredHeight: projectHeight,
      sourceTrack: sourceVideoTrack
    )
    let baseTargetRect = CGRect(origin: .zero, size: renderSize)
    let overlayRootLayer = CALayer()
    overlayRootLayer.frame = CGRect(origin: .zero, size: renderSize)
    let videoLayer = CALayer()
    videoLayer.frame = overlayRootLayer.bounds
    overlayRootLayer.addSublayer(videoLayer)
    let overlayContainerLayer = CALayer()
    overlayContainerLayer.frame = overlayRootLayer.bounds
    overlayRootLayer.addSublayer(overlayContainerLayer)

    var layerInstructions: [(zIndex: Int, instruction: AVMutableVideoCompositionLayerInstruction)] = []
    let baseLayerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
    baseLayerInstruction.setTransform(
      fusionVideoTransform(
        for: sourceVideoTrack,
        targetRect: baseTargetRect,
        renderSize: renderSize
      ),
      at: .zero
    )
    layerInstructions.append((zIndex: 0, instruction: baseLayerInstruction))

    let projectSize = CGSize(
      width: CGFloat(max(projectWidth ?? Int(renderSize.width), 1)),
      height: CGFloat(max(projectHeight ?? Int(renderSize.height), 1))
    )
    for node in sceneNodes.sorted(by: { $0.zIndex < $1.zIndex }) where node.clipId != jobId {
      guard
        let overlap = fusionTimelineOverlap(
          exportClipStartSeconds: exportClipStartSeconds,
          exportClipEndSeconds: exportClipEndSeconds,
          nodeClipStartSeconds: node.clipStartSeconds,
          nodeClipEndSeconds: node.clipEndSeconds,
          nodeSourceStartSeconds: node.sourceStartSeconds
        ),
        overlap.durationSeconds > 0.02
      else {
        continue
      }

      switch node.kind {
      case "image":
        if let layer = fusionImageOverlayLayer(
          node: node,
          projectSize: projectSize,
          renderSize: renderSize,
          overlap: overlap,
          exportDurationSeconds: exportClipEndSeconds - exportClipStartSeconds
        ) {
          overlayContainerLayer.addSublayer(layer)
        }
      case "text":
        let layer = fusionTextOverlayLayer(
          node: node,
          projectSize: projectSize,
          renderSize: renderSize,
          overlap: overlap,
          exportDurationSeconds: exportClipEndSeconds - exportClipStartSeconds
        )
        overlayContainerLayer.addSublayer(layer)
      case "lipSync":
        let layer = fusionLipSyncOverlayLayer(
          node: node,
          projectSize: projectSize,
          renderSize: renderSize,
          overlap: overlap,
          exportDurationSeconds: exportClipEndSeconds - exportClipStartSeconds
        )
        overlayContainerLayer.addSublayer(layer)
      default:
        continue
      }
    }

    let builtAudioMix: AVAudioMix? = audioMixInputParameters.isEmpty
      ? nil
      : {
          let mix = AVMutableAudioMix()
          mix.inputParameters = audioMixInputParameters
          return mix
        }()

    let videoComposition = AVMutableVideoComposition()
    let nominalFrameRate = max(Int32(lroundf(sourceVideoTrack.nominalFrameRate)), 30)
    videoComposition.frameDuration = CMTime(value: 1, timescale: nominalFrameRate)
    videoComposition.renderSize = renderSize
    let compositionInstruction = AVMutableVideoCompositionInstruction()
    compositionInstruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
    compositionInstruction.layerInstructions = layerInstructions
      .sorted(by: { $0.zIndex > $1.zIndex })
      .map { $0.instruction }
    videoComposition.instructions = [compositionInstruction]
    videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
      postProcessingAsVideoLayer: videoLayer,
      in: overlayRootLayer
    )

    guard let exportSession = AVAssetExportSession(
      asset: composition,
      presetName: AVAssetExportPresetHighestQuality
    ) else {
      throw FusionExportError(
        code: "export_unavailable",
        message: "Unable to create AVAssetExportSession."
      )
    }

    let supportedTypes = exportSession.supportedFileTypes
    let resolvedFileType: AVFileType =
      supportedTypes.contains(.mp4) ? .mp4 :
      (supportedTypes.contains(.mov) ? .mov : supportedTypes.first ?? .mov)

    let exportsDir = FileManager.default.temporaryDirectory.appendingPathComponent(
      "FusionExports",
      isDirectory: true
    )
    try? FileManager.default.createDirectory(
      at: exportsDir,
      withIntermediateDirectories: true,
      attributes: nil
    )
    let sanitizedName = outputFileName.replacingOccurrences(of: "/", with: "_")
    let ext = resolvedFileType == .mov ? "mov" : "mp4"
    let baseName = URL(fileURLWithPath: sanitizedName).deletingPathExtension().lastPathComponent
    self.outputURL = exportsDir.appendingPathComponent("\(baseName).\(ext)")
    if FileManager.default.fileExists(atPath: outputURL.path) {
      try? FileManager.default.removeItem(at: outputURL)
    }

    exportSession.outputURL = outputURL
    exportSession.outputFileType = resolvedFileType
    exportSession.shouldOptimizeForNetworkUse = true
    exportSession.timeRange = CMTimeRange(
      start: .zero,
      duration: composition.duration
    )
    exportSession.audioMix = builtAudioMix
    exportSession.videoComposition = videoComposition
    self.session = exportSession
  }

  func start(completion: @escaping () -> Void) {
    session.exportAsynchronously { [weak self] in
      guard let self else { return }
      switch session.status {
      case .completed:
        self.statusValue = "completed"
      case .cancelled:
        self.statusValue = "cancelled"
      case .failed:
        self.statusValue = "failed"
        self.errorMessage = session.error?.localizedDescription ?? "Export failed."
      default:
        self.statusValue = "failed"
        self.errorMessage = session.error?.localizedDescription ?? "Export ended unexpectedly."
      }
      completion()
    }
  }

  func cancel() {
    guard !isTerminal else { return }
    session.cancelExport()
    statusValue = "cancelled"
  }
}

private struct FusionExportOverlap {
  let insertAtSeconds: Double
  let sourceStartSeconds: Double
  let durationSeconds: Double
}

private func fusionTimelineOverlap(
  exportClipStartSeconds: Double,
  exportClipEndSeconds: Double,
  nodeClipStartSeconds: Double,
  nodeClipEndSeconds: Double,
  nodeSourceStartSeconds: Double
) -> FusionExportOverlap? {
  let overlapStart = max(exportClipStartSeconds, nodeClipStartSeconds)
  let overlapEnd = min(exportClipEndSeconds, nodeClipEndSeconds)
  guard overlapEnd > overlapStart else {
    return nil
  }
  return FusionExportOverlap(
    insertAtSeconds: overlapStart - exportClipStartSeconds,
    sourceStartSeconds: nodeSourceStartSeconds + (overlapStart - nodeClipStartSeconds),
    durationSeconds: overlapEnd - overlapStart
  )
}

private func fusionResolvedRenderSize(
  preferredWidth: Int?,
  preferredHeight: Int?,
  sourceTrack: AVAssetTrack
) -> CGSize {
  if let preferredWidth, let preferredHeight, preferredWidth > 0, preferredHeight > 0 {
    return CGSize(width: preferredWidth, height: preferredHeight)
  }
  let transformedRect = CGRect(origin: .zero, size: sourceTrack.naturalSize)
    .applying(sourceTrack.preferredTransform)
  return CGSize(
    width: max(abs(transformedRect.width), 1),
    height: max(abs(transformedRect.height), 1)
  )
}

private func fusionRenderRect(
  for node: FusionExportSceneNode,
  projectSize: CGSize,
  renderSize: CGSize
) -> CGRect {
  let scaleX = renderSize.width / max(projectSize.width, 1)
  let scaleY = renderSize.height / max(projectSize.height, 1)
  return CGRect(
    x: node.x * scaleX,
    y: node.y * scaleY,
    width: max(node.width * scaleX, 1),
    height: max(node.height * scaleY, 1)
  )
}

private func fusionVideoTransform(
  for sourceTrack: AVAssetTrack,
  targetRect: CGRect,
  renderSize: CGSize
) -> CGAffineTransform {
  let preferred = sourceTrack.preferredTransform
  let transformedBounds = CGRect(origin: .zero, size: sourceTrack.naturalSize)
    .applying(preferred)
  let orientedSize = CGSize(
    width: max(abs(transformedBounds.width), 1),
    height: max(abs(transformedBounds.height), 1)
  )
  let scale = CGAffineTransform(
    scaleX: targetRect.width / orientedSize.width,
    y: targetRect.height / orientedSize.height
  )
  let scaledBounds = CGRect(origin: .zero, size: sourceTrack.naturalSize)
    .applying(preferred)
    .applying(scale)
  let targetY = renderSize.height - targetRect.maxY
  let translation = CGAffineTransform(
    translationX: targetRect.minX - scaledBounds.minX,
    y: targetY - scaledBounds.minY
  )
  return preferred.concatenating(scale).concatenating(translation)
}

private func fusionApplyVisibilityWindow(
  to layer: CALayer,
  overlap: FusionExportOverlap,
  exportDurationSeconds: Double,
  opacity: Float
) {
  guard exportDurationSeconds > 0 else {
    layer.opacity = opacity
    return
  }
  let startKey = NSNumber(value: max(min(overlap.insertAtSeconds / exportDurationSeconds, 1), 0))
  let endKey = NSNumber(
    value: max(min((overlap.insertAtSeconds + overlap.durationSeconds) / exportDurationSeconds, 1), 0)
  )
  let animation = CAKeyframeAnimation(keyPath: "opacity")
  animation.values = [0, 0, opacity, opacity, 0]
  animation.keyTimes = [0, startKey, startKey, endKey, 1]
  animation.duration = exportDurationSeconds
  animation.isRemovedOnCompletion = false
  animation.fillMode = .forwards
  layer.opacity = 0
  layer.add(animation, forKey: "fusion_visibility")
}

private func fusionImageOverlayLayer(
  node: FusionExportSceneNode,
  projectSize: CGSize,
  renderSize: CGSize,
  overlap: FusionExportOverlap,
  exportDurationSeconds: Double
) -> CALayer? {
  guard let image = UIImage(contentsOfFile: node.localPath)?.cgImage else {
    return nil
  }
  let rect = fusionRenderRect(for: node, projectSize: projectSize, renderSize: renderSize)
  let layer = CALayer()
  layer.frame = rect
  layer.contents = image
  layer.contentsGravity = .resizeAspectFill
  layer.cornerRadius = 18
  layer.masksToBounds = true
  layer.zPosition = CGFloat(node.zIndex)
  layer.opacity = Float(node.opacity)
  if node.rotationDegrees != 0 {
    layer.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(node.rotationDegrees * .pi / 180)))
  }
  fusionApplyVisibilityWindow(
    to: layer,
    overlap: overlap,
    exportDurationSeconds: exportDurationSeconds,
    opacity: Float(node.opacity)
  )
  return layer
}

private func fusionTextOverlayLayer(
  node: FusionExportSceneNode,
  projectSize: CGSize,
  renderSize: CGSize,
  overlap: FusionExportOverlap,
  exportDurationSeconds: Double
) -> CALayer {
  let rect = fusionRenderRect(for: node, projectSize: projectSize, renderSize: renderSize)
  let container = CALayer()
  container.frame = rect
  container.zPosition = CGFloat(node.zIndex)
  let textLayer = CATextLayer()
  textLayer.frame = container.bounds
  textLayer.contentsScale = UIScreen.main.scale
  textLayer.alignmentMode = .center
  textLayer.foregroundColor = UIColor.white.cgColor
  textLayer.fontSize = max(rect.height * 0.38, 20)
  textLayer.string = node.displayLabel?.isEmpty == false ? node.displayLabel : "Text"
  container.addSublayer(textLayer)
  container.opacity = Float(node.opacity)
  fusionApplyVisibilityWindow(
    to: container,
    overlap: overlap,
    exportDurationSeconds: exportDurationSeconds,
    opacity: Float(node.opacity)
  )
  return container
}

private func fusionLipSyncOverlayLayer(
  node: FusionExportSceneNode,
  projectSize: CGSize,
  renderSize: CGSize,
  overlap: FusionExportOverlap,
  exportDurationSeconds: Double
) -> CALayer {
  let rect = fusionRenderRect(for: node, projectSize: projectSize, renderSize: renderSize)
  let container = CALayer()
  container.frame = rect
  container.cornerRadius = min(rect.height * 0.28, 20)
  container.backgroundColor = UIColor(white: 0.08, alpha: 0.78).cgColor
  container.zPosition = CGFloat(node.zIndex)

  let labelLayer = CATextLayer()
  labelLayer.frame = CGRect(x: 0, y: 0, width: rect.width, height: rect.height * 0.45)
  labelLayer.contentsScale = UIScreen.main.scale
  labelLayer.alignmentMode = .center
  labelLayer.foregroundColor = UIColor.white.withAlphaComponent(0.82).cgColor
  labelLayer.fontSize = max(rect.height * 0.2, 12)
  labelLayer.string = node.displayLabel?.isEmpty == false ? node.displayLabel : "Lip Sync"
  container.addSublayer(labelLayer)

  let barsContainer = CALayer()
  barsContainer.frame = CGRect(
    x: rect.width * 0.18,
    y: rect.height * 0.5,
    width: rect.width * 0.64,
    height: rect.height * 0.22
  )
  let barCount = 7
  let spacing = barsContainer.bounds.width / CGFloat((barCount * 2) - 1)
  for index in 0..<barCount {
    let factor = 0.35 + (CGFloat(index % 3) * 0.22)
    let bar = CALayer()
    bar.frame = CGRect(
      x: CGFloat(index) * spacing * 2,
      y: barsContainer.bounds.height * (1 - factor),
      width: spacing,
      height: barsContainer.bounds.height * factor
    )
    bar.cornerRadius = spacing * 0.5
    bar.backgroundColor = UIColor.systemTeal.withAlphaComponent(0.92).cgColor
    barsContainer.addSublayer(bar)
  }
  container.addSublayer(barsContainer)
  container.opacity = Float(node.opacity)
  fusionApplyVisibilityWindow(
    to: container,
    overlap: overlap,
    exportDurationSeconds: exportDurationSeconds,
    opacity: Float(node.opacity)
  )
  return container
}

private final class FusionPreviewRegistry {
  static let shared = FusionPreviewRegistry()

  private var views: [Int64: NSHashTable<FusionPreviewNativeView>] = [:]
  private var payloads: [Int64: FusionPreviewPayload] = [:]
  private var runtimeStates: [Int64: FusionPreviewRuntimeState] = [:]
  private var eventSink: FlutterEventSink?

  private init() {}

  func attach(view: FusionPreviewNativeView, projectId: Int64) {
    let bucket = views[projectId] ?? NSHashTable<FusionPreviewNativeView>.weakObjects()
    bucket.add(view)
    views[projectId] = bucket
    if let payload = payloads[projectId] {
      view.update(
        transportRevision: payload.transportRevision,
        sourceId: payload.sourceId,
        sourcePath: payload.sourcePath,
        sourceKind: payload.sourceKind,
        upcomingSourceId: payload.upcomingSourceId,
        upcomingSourcePath: payload.upcomingSourcePath,
        upcomingSourceKind: payload.upcomingSourceKind,
        clipStartSeconds: payload.clipStartSeconds,
        clipEndSeconds: payload.clipEndSeconds,
        sourceStartSeconds: payload.sourceStartSeconds,
        sourceEndSeconds: payload.sourceEndSeconds,
        upcomingSourceStartSeconds: payload.upcomingSourceStartSeconds,
        upcomingSourceEndSeconds: payload.upcomingSourceEndSeconds,
        projectWidth: payload.projectWidth,
        projectHeight: payload.projectHeight,
        baseClipId: payload.baseClipId,
        baseClipIds: payload.baseClipIds,
        selectedClipId: payload.selectedClipId,
        baseAudioGain: payload.baseAudioGain,
        baseAudioMuted: payload.baseAudioMuted,
        sceneNodes: payload.sceneNodes,
        audioNodes: payload.audioNodes,
        positionSeconds: payload.positionSeconds,
        isPlaying: payload.isPlaying
      )
    }
  }

  func detach(view: FusionPreviewNativeView, projectId: Int64) {
    views[projectId]?.remove(view)
    if views[projectId]?.allObjects.isEmpty ?? true {
      views.removeValue(forKey: projectId)
      runtimeStates.removeValue(forKey: projectId)
    }
  }

  func update(
    projectId: Int64,
    transportRevision: Int64,
    sourceId: String?,
    sourcePath: String?,
    sourceKind: String?,
    upcomingSourceId: String?,
    upcomingSourcePath: String?,
    upcomingSourceKind: String?,
    clipStartSeconds: Double?,
    clipEndSeconds: Double?,
    sourceStartSeconds: Double?,
    sourceEndSeconds: Double?,
    upcomingSourceStartSeconds: Double?,
    upcomingSourceEndSeconds: Double?,
    projectWidth: Int?,
    projectHeight: Int?,
    baseClipId: String?,
    baseClipIds: [String],
    selectedClipId: String?,
    baseAudioGain: Double?,
    baseAudioMuted: Bool?,
    sceneNodes: [[String: Any]],
    audioNodes: [[String: Any]],
    positionSeconds: Double,
    isPlaying: Bool
  ) {
    payloads[projectId] = FusionPreviewPayload(
      transportRevision: transportRevision,
      sourceId: sourceId,
      sourcePath: sourcePath,
      sourceKind: sourceKind,
      upcomingSourceId: upcomingSourceId,
      upcomingSourcePath: upcomingSourcePath,
      upcomingSourceKind: upcomingSourceKind,
      clipStartSeconds: clipStartSeconds,
      clipEndSeconds: clipEndSeconds,
      sourceStartSeconds: sourceStartSeconds,
      sourceEndSeconds: sourceEndSeconds,
      upcomingSourceStartSeconds: upcomingSourceStartSeconds,
      upcomingSourceEndSeconds: upcomingSourceEndSeconds,
      projectWidth: projectWidth,
      projectHeight: projectHeight,
      baseClipId: baseClipId,
      baseClipIds: baseClipIds,
      selectedClipId: selectedClipId,
      baseAudioGain: baseAudioGain,
      baseAudioMuted: baseAudioMuted,
      sceneNodes: sceneNodes,
      audioNodes: audioNodes,
      positionSeconds: positionSeconds,
      isPlaying: isPlaying
    )
    views[projectId]?.allObjects.forEach {
      $0.update(
        transportRevision: transportRevision,
        sourceId: sourceId,
        sourcePath: sourcePath,
        sourceKind: sourceKind,
        upcomingSourceId: upcomingSourceId,
        upcomingSourcePath: upcomingSourcePath,
        upcomingSourceKind: upcomingSourceKind,
        clipStartSeconds: clipStartSeconds,
        clipEndSeconds: clipEndSeconds,
        sourceStartSeconds: sourceStartSeconds,
        sourceEndSeconds: sourceEndSeconds,
        upcomingSourceStartSeconds: upcomingSourceStartSeconds,
        upcomingSourceEndSeconds: upcomingSourceEndSeconds,
        projectWidth: projectWidth,
        projectHeight: projectHeight,
        baseClipId: baseClipId,
        baseClipIds: baseClipIds,
        selectedClipId: selectedClipId,
        baseAudioGain: baseAudioGain,
        baseAudioMuted: baseAudioMuted,
        sceneNodes: sceneNodes,
        audioNodes: audioNodes,
        positionSeconds: positionSeconds,
        isPlaying: isPlaying
      )
    }
    emitRuntimeEvent(projectId: projectId, payload: payloads[projectId]!)
  }

  func dispatchCommand(
    projectId: Int64,
    transportRevision: Int64,
    commandKind: String,
    positionSeconds: Double?,
    isPlaying: Bool?
  ) {
    let current = payloads[projectId] ?? FusionPreviewPayload(
      transportRevision: transportRevision,
      sourceId: nil,
      sourcePath: nil,
      sourceKind: nil,
      upcomingSourceId: nil,
      upcomingSourcePath: nil,
      upcomingSourceKind: nil,
      clipStartSeconds: nil,
      clipEndSeconds: nil,
      sourceStartSeconds: nil,
      sourceEndSeconds: nil,
      upcomingSourceStartSeconds: nil,
      upcomingSourceEndSeconds: nil,
      projectWidth: nil,
      projectHeight: nil,
      baseClipId: nil,
      baseClipIds: [],
      selectedClipId: nil,
      baseAudioGain: nil,
      baseAudioMuted: nil,
      sceneNodes: [],
      audioNodes: [],
      positionSeconds: positionSeconds ?? 0,
      isPlaying: false
    )
    let nextIsPlaying = isPlaying ?? {
      switch commandKind {
      case "play":
        return true
      case "pause":
        return false
      default:
        return current.isPlaying
      }
    }()
    update(
      projectId: projectId,
      transportRevision: transportRevision,
      sourceId: current.sourceId,
      sourcePath: current.sourcePath,
      sourceKind: current.sourceKind,
      upcomingSourceId: current.upcomingSourceId,
      upcomingSourcePath: current.upcomingSourcePath,
      upcomingSourceKind: current.upcomingSourceKind,
      clipStartSeconds: current.clipStartSeconds,
      clipEndSeconds: current.clipEndSeconds,
      sourceStartSeconds: current.sourceStartSeconds,
      sourceEndSeconds: current.sourceEndSeconds,
      upcomingSourceStartSeconds: current.upcomingSourceStartSeconds,
      upcomingSourceEndSeconds: current.upcomingSourceEndSeconds,
      projectWidth: current.projectWidth,
      projectHeight: current.projectHeight,
      baseClipId: current.baseClipId,
      baseClipIds: current.baseClipIds,
      selectedClipId: current.selectedClipId,
      baseAudioGain: current.baseAudioGain,
      baseAudioMuted: current.baseAudioMuted,
      sceneNodes: current.sceneNodes,
      audioNodes: current.audioNodes,
      positionSeconds: positionSeconds ?? current.positionSeconds,
      isPlaying: nextIsPlaying
    )
  }

  func setEventSink(_ sink: FlutterEventSink?) {
    eventSink = sink
    guard let sink else { return }
    for (projectId, payload) in payloads {
      emitRuntimeEvent(projectId: projectId, payload: payload, sink: sink)
    }
  }

  func reportRuntimeState(projectId: Int64, state: FusionPreviewRuntimeState) {
    runtimeStates[projectId] = state
    guard let payload = payloads[projectId] else { return }
    emitRuntimeEvent(projectId: projectId, payload: payload)
  }

  private func emitRuntimeEvent(
    projectId: Int64,
    payload: FusionPreviewPayload,
    sink: FlutterEventSink? = nil
  ) {
    let runtimeState = runtimeStates[projectId]
    let event: [String: Any] = [
      "projectId": projectId,
      "positionSeconds": runtimeState?.positionSeconds ?? payload.positionSeconds,
      "isPlaying": runtimeState?.isPlaying ?? payload.isPlaying,
      "transportRevision": runtimeState?.transportRevision ?? payload.transportRevision,
      "isBuffering": runtimeState?.isBuffering ?? false,
      "frameReady": runtimeState?.frameReady ?? (payload.sourceId != nil || payload.sourcePath != nil),
      "frameDropCount": runtimeState?.frameDropCount ?? 0,
      "audioDropCount": runtimeState?.audioDropCount ?? 0,
      "bufferUnderrunCount": runtimeState?.bufferUnderrunCount ?? 0,
      "previewLatencyMillis": runtimeState?.previewLatencyMillis ?? 0.0,
      "seekLatencyMillis": runtimeState?.seekLatencyMillis ?? 0.0,
    ]
    (sink ?? eventSink)?(event)
  }
}

private final class FusionPreviewEventsStreamHandler: NSObject, FlutterStreamHandler {
  static let shared = FusionPreviewEventsStreamHandler()

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    FusionPreviewRegistry.shared.setEventSink(events)
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    FusionPreviewRegistry.shared.setEventSink(nil)
    return nil
  }
}

private struct FusionPreviewPayload {
  let transportRevision: Int64
  let sourceId: String?
  let sourcePath: String?
  let sourceKind: String?
  let upcomingSourceId: String?
  let upcomingSourcePath: String?
  let upcomingSourceKind: String?
  let clipStartSeconds: Double?
  let clipEndSeconds: Double?
  let sourceStartSeconds: Double?
  let sourceEndSeconds: Double?
  let upcomingSourceStartSeconds: Double?
  let upcomingSourceEndSeconds: Double?
  let projectWidth: Int?
  let projectHeight: Int?
  let baseClipId: String?
  let baseClipIds: [String]
  let selectedClipId: String?
  let baseAudioGain: Double?
  let baseAudioMuted: Bool?
  let sceneNodes: [[String: Any]]
  let audioNodes: [[String: Any]]
  let positionSeconds: Double
  let isPlaying: Bool
}

private struct FusionPreviewRuntimeState {
  let positionSeconds: Double
  let isPlaying: Bool
  let transportRevision: Int64
  let isBuffering: Bool
  let frameReady: Bool
  let frameDropCount: Int
  let audioDropCount: Int
  let bufferUnderrunCount: Int
  let previewLatencyMillis: Double
  let seekLatencyMillis: Double
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
  private let overlayContainer = UIView()
  private let playerLayer = AVPlayerLayer()
  private var player: AVPlayer?
  private var playbackObserverToken: Any?
  private var currentSourceId: String?
  private var currentSourcePath: String?
  private var currentSourceKind: String?
  private var upcomingSourceId: String?
  private var upcomingSourcePath: String?
  private var upcomingSourceKind: String?
  private var currentClipStartSeconds: Double = 0
  private var currentClipEndSeconds: Double?
  private var currentSourceStartSeconds: Double = 0
  private var currentSourceEndSeconds: Double?
  private var upcomingSourceStartSeconds: Double = 0
  private var upcomingSourceEndSeconds: Double?
  private var currentProjectWidth: CGFloat = 0
  private var currentProjectHeight: CGFloat = 0
  private var currentBaseClipId: String?
  private var currentBaseClipIds: Set<String> = []
  private var currentSelectedClipId: String?
  private var currentBaseAudioGain: Float = 1.0
  private var currentBaseAudioMuted = false
  private var currentSceneNodes: [[String: Any]] = []
  private var currentAudioNodes: [[String: Any]] = []
  private var overlayVideoViews: [String: FusionOverlayVideoNodeView] = [:]
  private var overlayStaticViews: [String: FusionOverlayStaticNodeView] = [:]
  private var overlayNodeSnapshots: [String: [String: Any]] = [:]
  private var overlayAudioPlayers: [String: FusionOverlayAudioNodePlayer] = [:]
  private var overlayAudioNodeSnapshots: [String: [String: Any]] = [:]
  private var lastRenderedSceneKey = ""
  private var lastRenderedAudioKey = ""
  private var preloadedPlayer: AVPlayer?
  private var preloadedImage: UIImage?
  private var preloadedSourceId: String?
  private var preloadedSourcePath: String?
  private var preloadedSourceKind: String?
  private var preloadedSourceStartSeconds: Double = 0
  private var preloadedSourceEndSeconds: Double?
  private var lastAppliedTransportRevision: Int64 = -1
  private var runtimeIsBuffering = false
  private var runtimeFrameReady = false
  private var runtimeFrameDropCount = 0
  private var runtimeAudioDropCount = 0
  private var runtimeBufferUnderrunCount = 0
  private var runtimePreviewLatencyMillis: Double = 0
  private var runtimeSeekLatencyMillis: Double = 0
  private var lastTransportMutationTime: CFTimeInterval = 0
  private var lastRuntimeEmitTime: CFTimeInterval = 0
  private var lastFrameTickTime: CFTimeInterval = 0
  private var pendingSeekStartedTime: CFTimeInterval?
  private var awaitingPreviewFrame = false

  init(frame: CGRect, projectId: Int64) {
    self.projectId = projectId
    super.init(frame: frame)
    setupUI()
    FusionPreviewRegistry.shared.attach(view: self, projectId: projectId)
    update(
      transportRevision: 0,
      sourceId: nil,
      sourcePath: nil,
      sourceKind: nil,
      upcomingSourceId: nil,
      upcomingSourcePath: nil,
      upcomingSourceKind: nil,
      clipStartSeconds: nil,
      clipEndSeconds: nil,
      sourceStartSeconds: nil,
      sourceEndSeconds: nil,
      upcomingSourceStartSeconds: nil,
      upcomingSourceEndSeconds: nil,
      projectWidth: nil,
      projectHeight: nil,
      baseClipId: nil,
      baseClipIds: [],
      selectedClipId: nil,
      baseAudioGain: nil,
      baseAudioMuted: nil,
      sceneNodes: [],
      audioNodes: [],
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
    clearPreloadedSource()
    overlayVideoViews.values.forEach { $0.dispose() }
    overlayStaticViews.values.forEach { $0.dispose() }
    overlayAudioPlayers.values.forEach { $0.dispose() }
    FusionPreviewRegistry.shared.detach(view: self, projectId: projectId)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    imageView.frame = bounds
    playerLayer.frame = bounds
    overlayContainer.frame = bounds
    let nextKey = sceneIdentityKey()
    if nextKey != lastRenderedSceneKey {
      renderCompositionScene()
      lastRenderedSceneKey = nextKey
    }
    let nextAudioKey = audioIdentityKey()
    if nextAudioKey != lastRenderedAudioKey {
      renderAudioScene()
      lastRenderedAudioKey = nextAudioKey
    }
  }

  func update(
    transportRevision: Int64,
    sourceId: String?,
    sourcePath: String?,
    sourceKind: String?,
    upcomingSourceId: String?,
    upcomingSourcePath: String?,
    upcomingSourceKind: String?,
    clipStartSeconds: Double?,
    clipEndSeconds: Double?,
    sourceStartSeconds: Double?,
    sourceEndSeconds: Double?,
    upcomingSourceStartSeconds: Double?,
    upcomingSourceEndSeconds: Double?,
    projectWidth: Int?,
    projectHeight: Int?,
    baseClipId: String?,
    baseClipIds: [String],
    selectedClipId: String?,
    baseAudioGain: Double?,
    baseAudioMuted: Bool?,
    sceneNodes: [[String: Any]],
    audioNodes: [[String: Any]],
    positionSeconds: Double,
    isPlaying: Bool
  ) {
    let selectionChanged = selectedClipId != currentSelectedClipId
    let playStateChanged = isPlaying != isCurrentlyPlaying
    let transportChanged = transportRevision != lastAppliedTransportRevision
    lastAppliedTransportRevision = transportRevision
    let nextSourceStartSeconds = max(0, sourceStartSeconds ?? 0)
    let nextHasSource = sourceId != nil || sourcePath != nil || sourceKind != nil
    let currentHasSource =
      currentSourceId != nil || currentSourcePath != nil || currentSourceKind != nil
    let sourceChanged =
      nextHasSource != currentHasSource ||
      (
        nextHasSource &&
        !previewSourceMatches(
          sourceId: sourceId,
          sourcePath: sourcePath,
          sourceKind: sourceKind,
          sourceStartSeconds: nextSourceStartSeconds,
          sourceEndSeconds: sourceEndSeconds,
          againstId: currentSourceId,
          againstPath: currentSourcePath,
          kind: currentSourceKind,
          startSeconds: currentSourceStartSeconds,
          endSeconds: currentSourceEndSeconds
        )
      )
    currentSourceId = sourceId
    currentSourcePath = sourcePath
    currentSourceKind = sourceKind
    self.upcomingSourceId = upcomingSourceId
    self.upcomingSourcePath = upcomingSourcePath
    self.upcomingSourceKind = upcomingSourceKind
    currentClipStartSeconds = max(0, clipStartSeconds ?? 0)
    currentClipEndSeconds = clipEndSeconds
    currentSourceStartSeconds = nextSourceStartSeconds
    currentSourceEndSeconds = sourceEndSeconds
    self.upcomingSourceStartSeconds = max(0, upcomingSourceStartSeconds ?? 0)
    self.upcomingSourceEndSeconds = upcomingSourceEndSeconds
    currentProjectWidth = CGFloat(projectWidth ?? 0)
    currentProjectHeight = CGFloat(projectHeight ?? 0)
    currentBaseClipId = baseClipId
    currentBaseClipIds = Set(baseClipIds)
    if let baseClipId {
      currentBaseClipIds.insert(baseClipId)
    }
    currentSelectedClipId = selectedClipId
    currentBaseAudioGain = Float(baseAudioGain ?? 1.0)
    currentBaseAudioMuted = baseAudioMuted ?? false
    currentSceneNodes = sceneNodes
    currentAudioNodes = audioNodes
    currentPosition = positionSeconds
    isCurrentlyPlaying = isPlaying
    if sourceChanged || transportChanged || playStateChanged {
      noteTransportMutation(expectFrame: currentSourceKind == "video")
    }
    if sourceChanged {
      loadSource()
    }
    prepareUpcomingSource()
    let nextKey = sceneIdentityKey()
    if nextKey != lastRenderedSceneKey || (selectionChanged && !isCurrentlyPlaying && !playStateChanged) {
      renderCompositionScene()
      lastRenderedSceneKey = nextKey
    }
    let nextAudioKey = audioIdentityKey()
    if nextAudioKey != lastRenderedAudioKey {
      renderAudioScene()
      lastRenderedAudioKey = nextAudioKey
    }
    applyTransport(shouldRetarget: sourceChanged || transportChanged)
    applyOverlayTransport()
    applyAudioTransport()
    reportRuntimeState(force: true)
  }

  private var currentPosition: Double = 0
  private var isCurrentlyPlaying = false

  private func applyBaseAudioSettings() {
    guard let player else { return }
    player.volume = currentBaseAudioMuted ? 0.0 : currentBaseAudioGain
    player.isMuted = currentBaseAudioMuted
  }

  private func silencePlayer(_ player: AVPlayer?) {
    guard let player else { return }
    player.volume = 0.0
    player.isMuted = true
  }

  private func setupUI() {
    backgroundColor = .black
    clipsToBounds = true

    imageView.frame = bounds
    imageView.contentMode = .scaleAspectFit
    imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    imageView.isHidden = true
    addSubview(imageView)

    playerLayer.videoGravity = .resizeAspect
    playerLayer.frame = bounds
    layer.addSublayer(playerLayer)
    playerLayer.isHidden = true

    overlayContainer.frame = bounds
    overlayContainer.backgroundColor = .clear
    overlayContainer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    overlayContainer.isUserInteractionEnabled = false
    addSubview(overlayContainer)
  }

  private func loadSource() {
    guard let sourceKind = currentSourceKind, let sourcePath = currentSourcePath else {
      silencePlayer(player)
      player?.pause()
      removePlaybackObserver()
      player = nil
      playerLayer.player = nil
      playerLayer.isHidden = true
      imageView.image = nil
      imageView.isHidden = true
      currentSourceId = nil
      clearPreloadedSource()
      runtimeFrameReady = false
      awaitingPreviewFrame = false
      runtimeIsBuffering = false
      reportRuntimeState(force: true)
      return
    }

    switch sourceKind {
    case "video":
      imageView.image = nil
      imageView.isHidden = true
      let newPlayer = takePreloadedPlayerIfMatching() ?? makePlayer(for: sourcePath)
      removePlaybackObserver()
      silencePlayer(player)
      player?.pause()
      player = newPlayer
      playerLayer.player = newPlayer
      playerLayer.isHidden = false
      runtimeFrameReady = false
      addPlaybackObserver(to: newPlayer)
      applyBaseAudioSettings()
    case "image":
      silencePlayer(player)
      player?.pause()
      removePlaybackObserver()
      player = nil
      playerLayer.player = nil
      playerLayer.isHidden = true
      imageView.image = takePreloadedImageIfMatching() ?? UIImage(contentsOfFile: sourcePath)
      imageView.isHidden = false
      runtimeFrameReady = imageView.image != nil
      awaitingPreviewFrame = false
      runtimeIsBuffering = false
      reportRuntimeState(force: true)
    default:
      silencePlayer(player)
      player?.pause()
      removePlaybackObserver()
      player = nil
      playerLayer.player = nil
      playerLayer.isHidden = true
      imageView.image = nil
      imageView.isHidden = true
      runtimeFrameReady = false
      awaitingPreviewFrame = false
      runtimeIsBuffering = false
      reportRuntimeState(force: true)
    }
  }

  private func makePlayer(for sourcePath: String) -> AVPlayer {
    let url = URL(fileURLWithPath: sourcePath)
    let newPlayer = AVPlayer(url: url)
    newPlayer.actionAtItemEnd = .pause
    newPlayer.automaticallyWaitsToMinimizeStalling = false
    newPlayer.currentItem?.preferredForwardBufferDuration = 0
    newPlayer.volume = 1.0
    newPlayer.isMuted = false
    return newPlayer
  }

  private func prepareUpcomingSource() {
    guard
      let sourceId = upcomingSourceId,
      let sourcePath = upcomingSourcePath,
      let sourceKind = upcomingSourceKind
    else {
      clearPreloadedSource()
      return
    }

    if previewSourceMatches(
      sourceId: sourceId,
      sourcePath: sourcePath,
      sourceKind: sourceKind,
      sourceStartSeconds: upcomingSourceStartSeconds,
      sourceEndSeconds: upcomingSourceEndSeconds,
      againstId: currentSourceId,
      againstPath: currentSourcePath,
      kind: currentSourceKind,
      startSeconds: currentSourceStartSeconds,
      endSeconds: currentSourceEndSeconds
    ) {
      clearPreloadedSource()
      return
    }

    if previewSourceMatches(
      sourceId: sourceId,
      sourcePath: sourcePath,
      sourceKind: sourceKind,
      sourceStartSeconds: upcomingSourceStartSeconds,
      sourceEndSeconds: upcomingSourceEndSeconds,
      againstId: preloadedSourceId,
      againstPath: preloadedSourcePath,
      kind: preloadedSourceKind,
      startSeconds: preloadedSourceStartSeconds,
      endSeconds: preloadedSourceEndSeconds
    ) {
      return
    }

    clearPreloadedSource()
    preloadedSourceId = sourceId
    preloadedSourcePath = sourcePath
    preloadedSourceKind = sourceKind
    preloadedSourceStartSeconds = upcomingSourceStartSeconds
    preloadedSourceEndSeconds = upcomingSourceEndSeconds

    switch sourceKind {
    case "video":
      let nextPlayer = makePlayer(for: sourcePath)
      nextPlayer.isMuted = true
      nextPlayer.volume = 0
      seekPlayer(
        nextPlayer,
        to: CMTime(seconds: max(0, upcomingSourceStartSeconds), preferredTimescale: 600)
      )
      preloadedPlayer = nextPlayer
    case "image":
      preloadedImage = UIImage(contentsOfFile: sourcePath)
    default:
      clearPreloadedSource()
    }
  }

  private func takePreloadedPlayerIfMatching() -> AVPlayer? {
    guard
      previewSourceMatches(
        sourceId: currentSourceId,
        sourcePath: currentSourcePath,
        sourceKind: currentSourceKind,
        sourceStartSeconds: currentSourceStartSeconds,
        sourceEndSeconds: currentSourceEndSeconds,
        againstId: preloadedSourceId,
        againstPath: preloadedSourcePath,
        kind: preloadedSourceKind,
        startSeconds: preloadedSourceStartSeconds,
        endSeconds: preloadedSourceEndSeconds
      ),
      let nextPlayer = preloadedPlayer
    else {
      return nil
    }

    clearPreloadedSource(keepCurrentPlayer: true)
    return nextPlayer
  }

  private func takePreloadedImageIfMatching() -> UIImage? {
    guard
      previewSourceMatches(
        sourceId: currentSourceId,
        sourcePath: currentSourcePath,
        sourceKind: currentSourceKind,
        sourceStartSeconds: currentSourceStartSeconds,
        sourceEndSeconds: currentSourceEndSeconds,
        againstId: preloadedSourceId,
        againstPath: preloadedSourcePath,
        kind: preloadedSourceKind,
        startSeconds: preloadedSourceStartSeconds,
        endSeconds: preloadedSourceEndSeconds
      ),
      let nextImage = preloadedImage
    else {
      return nil
    }

    clearPreloadedSource()
    return nextImage
  }

  private func clearPreloadedSource(keepCurrentPlayer: Bool = false) {
    if !keepCurrentPlayer {
      silencePlayer(preloadedPlayer)
      preloadedPlayer?.pause()
    }
    preloadedPlayer = nil
    preloadedImage = nil
    preloadedSourceId = nil
    preloadedSourcePath = nil
    preloadedSourceKind = nil
    preloadedSourceStartSeconds = 0
    preloadedSourceEndSeconds = nil
  }

  private func previewSourceMatches(
    sourceId: String?,
    sourcePath: String?,
    sourceKind: String?,
    sourceStartSeconds: Double,
    sourceEndSeconds: Double?,
    againstId: String?,
    againstPath: String?,
    kind: String?,
    startSeconds: Double,
    endSeconds: Double?
  ) -> Bool {
    if let sourcePath, let sourceKind, let againstPath, let kind {
      return sourcePath == againstPath &&
        sourceKind == kind &&
        abs(sourceStartSeconds - startSeconds) <= 0.001 &&
        abs((sourceEndSeconds ?? 0) - (endSeconds ?? 0)) <= 0.001
    }
    if let sourceId, let againstId {
      return sourceId == againstId
    }
    return sourceId == nil &&
      sourcePath == nil &&
      sourceKind == nil &&
      againstId == nil &&
      againstPath == nil &&
      kind == nil
  }

  private func seekPlayer(_ player: AVPlayer, to target: CMTime) {
    pendingSeekStartedTime = CACurrentMediaTime()
    runtimeIsBuffering = true
    player.seek(
      to: target,
      toleranceBefore: .zero,
      toleranceAfter: .zero
    ) { [weak self] _ in
      guard let self else { return }
      if let pendingSeekStartedTime = self.pendingSeekStartedTime {
        self.runtimeSeekLatencyMillis = max(0, (CACurrentMediaTime() - pendingSeekStartedTime) * 1000.0)
      }
      self.pendingSeekStartedTime = nil
      self.runtimeIsBuffering = false
      self.reportRuntimeState(force: true)
    }
  }

  private func noteTransportMutation(expectFrame: Bool) {
    lastTransportMutationTime = CACurrentMediaTime()
    awaitingPreviewFrame = expectFrame
    if expectFrame {
      runtimeFrameReady = false
    } else {
      runtimeFrameReady = currentSourceKind == "image" && currentSourcePath != nil
      runtimePreviewLatencyMillis = 0
    }
  }

  private func noteFrameTick() {
    let now = CACurrentMediaTime()
    if isCurrentlyPlaying && lastFrameTickTime > 0 {
      let delta = now - lastFrameTickTime
      if delta >= 0.12 {
        let estimatedDrops = max(1, Int((delta / (1.0 / 30.0)).rounded(.down)) - 1)
        runtimeFrameDropCount += estimatedDrops
      }
    }
    lastFrameTickTime = now
    runtimeFrameReady = true
    runtimeIsBuffering = false
    if awaitingPreviewFrame && lastTransportMutationTime > 0 {
      runtimePreviewLatencyMillis = max(0, (now - lastTransportMutationTime) * 1000.0)
      awaitingPreviewFrame = false
    }
    reportRuntimeState()
  }

  private func reportRuntimeState(force: Bool = false) {
    let now = CACurrentMediaTime()
    let minEmitInterval = isCurrentlyPlaying ? 0.18 : (1.0 / 30.0)
    if !force && (now - lastRuntimeEmitTime) < minEmitInterval {
      return
    }
    lastRuntimeEmitTime = now
    FusionPreviewRegistry.shared.reportRuntimeState(
      projectId: projectId,
      state: FusionPreviewRuntimeState(
        positionSeconds: currentProjectPlaybackSeconds(),
        isPlaying: isCurrentlyPlaying,
        transportRevision: max(0, lastAppliedTransportRevision),
        isBuffering: runtimeIsBuffering,
        frameReady: runtimeFrameReady,
        frameDropCount: runtimeFrameDropCount,
        audioDropCount: runtimeAudioDropCount,
        bufferUnderrunCount: runtimeBufferUnderrunCount,
        previewLatencyMillis: runtimePreviewLatencyMillis,
        seekLatencyMillis: runtimeSeekLatencyMillis
      )
    )
  }

  private func applyTransport(shouldRetarget: Bool) {
    guard currentSourceKind == "video", let player else { return }

    let targetSeconds = clampedPositionSeconds(currentPosition)
    let target = CMTime(seconds: targetSeconds, preferredTimescale: 600)
    let current = player.currentTime().seconds
    let seekThreshold = isCurrentlyPlaying ? 0.18 : 0.04
    let shouldSeek =
      shouldRetarget &&
      (!current.isFinite || abs(current - targetSeconds) > seekThreshold)
    let seekTolerance = CMTime(
      seconds: isCurrentlyPlaying ? (1.0 / 60.0) : 0.0,
      preferredTimescale: 600
    )

    let playOrPause = { [weak self] in
      guard let self else { return }
      if self.isCurrentlyPlaying {
        player.play()
      } else {
        player.pause()
      }
    }

    if shouldSeek {
      runtimeIsBuffering = true
      pendingSeekStartedTime = CACurrentMediaTime()
      player.seek(
        to: target,
        toleranceBefore: seekTolerance,
        toleranceAfter: seekTolerance
      ) { [weak self] _ in
        guard let self else { return }
        if let pendingSeekStartedTime = self.pendingSeekStartedTime {
          self.runtimeSeekLatencyMillis = max(
            0,
            (CACurrentMediaTime() - pendingSeekStartedTime) * 1000.0
          )
        }
        self.pendingSeekStartedTime = nil
        self.runtimeIsBuffering = false
        playOrPause()
        self.applyOverlayTransport(referenceProjectSeconds: self.currentProjectPlaybackSeconds())
        self.reportRuntimeState(force: true)
      }
    } else {
      playOrPause()
      applyOverlayTransport(referenceProjectSeconds: currentProjectPlaybackSeconds())
      reportRuntimeState(force: true)
    }
  }

  private func addPlaybackObserver(to player: AVPlayer) {
    playbackObserverToken = player.addPeriodicTimeObserver(
      forInterval: CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600),
      queue: .main
    ) { [weak self] _ in
      guard let self else { return }
      self.noteFrameTick()
      self.applyOverlayTransport(referenceProjectSeconds: self.currentProjectPlaybackSeconds())
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

  private func renderCompositionScene() {
    overlayContainer.subviews.forEach { $0.removeFromSuperview() }
    var reusableVideoViews = overlayVideoViews
    var reusableStaticViews = overlayStaticViews
    overlayVideoViews = [:]
    overlayStaticViews = [:]
    overlayNodeSnapshots = [:]

    guard currentProjectWidth > 0, currentProjectHeight > 0 else {
      reusableVideoViews.values.forEach { $0.dispose() }
      reusableStaticViews.values.forEach { $0.dispose() }
      return
    }

    let widthScale = bounds.width / currentProjectWidth
    let heightScale = bounds.height / currentProjectHeight

    let sortedNodes = currentSceneNodes.sorted {
      (($0["zIndex"] as? NSNumber)?.intValue ?? 0) <
        (($1["zIndex"] as? NSNumber)?.intValue ?? 0)
    }

    for node in sortedNodes {
      guard let clipId = node["clipId"] as? String else { continue }
      if currentBaseClipIds.contains(clipId) { continue }
      let kind = node["kind"] as? String ?? "video"

      let x = (node["x"] as? NSNumber)?.doubleValue ?? 0
      let y = (node["y"] as? NSNumber)?.doubleValue ?? 0
      let width = (node["width"] as? NSNumber)?.doubleValue ?? 0
      let height = (node["height"] as? NSNumber)?.doubleValue ?? 0
      if width <= 0 || height <= 0 { continue }

      let frame = CGRect(
        x: x * widthScale,
        y: y * heightScale,
        width: width * widthScale,
        height: height * heightScale
      )

      let container = UIView(frame: frame)
      applyChrome(
        to: container,
        kind: kind,
        isSelected: !isCurrentlyPlaying && clipId == currentSelectedClipId
      )
      container.alpha = CGFloat((node["opacity"] as? NSNumber)?.doubleValue ?? 1.0)
      container.transform = CGAffineTransform(
        rotationAngle: CGFloat(
          ((node["rotationDegrees"] as? NSNumber)?.doubleValue ?? 0) * .pi / 180.0
        )
      )

      let localPath = node["localPath"] as? String
      let displayLabel = node["displayLabel"] as? String
      let content: UIView
      if kind == "image", let localPath, UIImage(contentsOfFile: localPath) != nil {
        let staticView =
          reusableStaticViews.removeValue(forKey: clipId)
          ?? FusionOverlayStaticNodeView(frame: container.bounds)
        staticView.frame = container.bounds
        staticView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        staticView.configure(
          kind: kind,
          localPath: localPath,
          displayLabel: displayLabel
        )
        overlayStaticViews[clipId] = staticView
        content = staticView
      } else if kind == "video", let localPath {
        let videoView =
          reusableVideoViews.removeValue(forKey: clipId)
          ?? FusionOverlayVideoNodeView(frame: container.bounds)
        videoView.frame = container.bounds
        videoView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        videoView.configure(
          sourcePath: localPath,
          sourceStartSeconds: (node["sourceStartSeconds"] as? NSNumber)?.doubleValue ?? 0,
          sourceEndSeconds: (node["sourceEndSeconds"] as? NSNumber)?.doubleValue
        )
        overlayVideoViews[clipId] = videoView
        overlayNodeSnapshots[clipId] = node
        content = videoView
      } else {
        let staticView =
          reusableStaticViews.removeValue(forKey: clipId)
          ?? FusionOverlayStaticNodeView(frame: container.bounds)
        staticView.frame = container.bounds
        staticView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        staticView.configure(
          kind: kind,
          localPath: localPath,
          displayLabel: displayLabel
        )
        overlayStaticViews[clipId] = staticView
        content = staticView
      }

      container.addSubview(content)
      overlayContainer.addSubview(container)
    }

    reusableVideoViews.values.forEach { $0.dispose() }
    reusableStaticViews.values.forEach { $0.dispose() }
    applyOverlayTransport()
  }

  private func renderAudioScene() {
    var reusableAudioPlayers = overlayAudioPlayers
    overlayAudioPlayers = [:]
    overlayAudioNodeSnapshots = [:]
    applyBaseAudioSettings()

    for node in currentAudioNodes {
      guard let clipId = node["clipId"] as? String else { continue }
      if currentBaseClipIds.contains(clipId) { continue }
      guard let localPath = node["localPath"] as? String else { continue }
      if currentSourceKind == "video", localPath == currentSourcePath {
        continue
      }
      let audioPlayer =
        reusableAudioPlayers.removeValue(forKey: clipId)
        ?? FusionOverlayAudioNodePlayer()
      audioPlayer.configure(
        sourcePath: localPath,
        sourceStartSeconds: (node["sourceStartSeconds"] as? NSNumber)?.doubleValue ?? 0,
        sourceEndSeconds: (node["sourceEndSeconds"] as? NSNumber)?.doubleValue,
        gain: (node["gain"] as? NSNumber)?.floatValue ?? 1.0,
        isMuted: (node["isMuted"] as? Bool) ?? false
      )
      overlayAudioPlayers[clipId] = audioPlayer
      overlayAudioNodeSnapshots[clipId] = node
    }

    reusableAudioPlayers.values.forEach { $0.dispose() }
    applyAudioTransport()
  }

  private func applyChrome(
    to container: UIView,
    kind: String,
    isSelected: Bool
  ) {
    let selectedColor = UIColor(red: 0.28, green: 0.88, blue: 0.83, alpha: 1.0)
    let idleBorder = UIColor.white.withAlphaComponent(0.14).cgColor

    switch kind {
    case "text", "lipSync":
      container.clipsToBounds = false
      container.backgroundColor = .clear
      container.layer.cornerRadius = 0
      container.layer.shadowOpacity = 0
      container.layer.shadowRadius = 0
      container.layer.shadowOffset = .zero
      container.layer.shadowColor = UIColor.clear.cgColor
      container.layer.borderWidth = isSelected ? 1.5 : 0
      container.layer.borderColor = isSelected ? selectedColor.cgColor : UIColor.clear.cgColor
    case "image", "video":
      container.clipsToBounds = true
      container.backgroundColor = UIColor.clear
      container.layer.cornerRadius = 12
      container.layer.borderWidth = isSelected ? 2 : 1
      container.layer.borderColor = isSelected ? selectedColor.cgColor : idleBorder
      container.layer.shadowColor = UIColor.black.withAlphaComponent(0.24).cgColor
      container.layer.shadowOpacity = 1
      container.layer.shadowRadius = 12
      container.layer.shadowOffset = CGSize(width: 0, height: 4)
    default:
      container.clipsToBounds = true
      container.backgroundColor = UIColor.clear
      container.layer.cornerRadius = 10
      container.layer.borderWidth = isSelected ? 1.5 : 1
      container.layer.borderColor = isSelected ? selectedColor.cgColor : idleBorder
      container.layer.shadowOpacity = 0
      container.layer.shadowRadius = 0
      container.layer.shadowOffset = .zero
      container.layer.shadowColor = UIColor.clear.cgColor
    }
  }

  private func applyOverlayTransport() {
    applyOverlayTransport(referenceProjectSeconds: currentProjectPlaybackSeconds())
  }

  private func applyOverlayTransport(referenceProjectSeconds: Double?) {
    let projectSeconds = referenceProjectSeconds ?? currentProjectPlaybackSeconds()
    for (clipId, overlayView) in overlayVideoViews {
      guard let node = overlayNodeSnapshots[clipId] else { continue }
      let clipStartSeconds = (node["clipStartSeconds"] as? NSNumber)?.doubleValue ?? 0
      let sourceStartSeconds = (node["sourceStartSeconds"] as? NSNumber)?.doubleValue ?? 0
      let positionSeconds = sourceStartSeconds + max(0, projectSeconds - clipStartSeconds)
      overlayView.sync(
        positionSeconds: positionSeconds,
        isPlaying: isCurrentlyPlaying
      )
    }
  }

  private func applyAudioTransport() {
    applyAudioTransport(referenceProjectSeconds: currentProjectPlaybackSeconds())
  }

  private func applyAudioTransport(referenceProjectSeconds: Double?) {
    let projectSeconds = referenceProjectSeconds ?? currentProjectPlaybackSeconds()
    for (clipId, audioPlayer) in overlayAudioPlayers {
      guard let node = overlayAudioNodeSnapshots[clipId] else { continue }
      let clipStartSeconds = (node["clipStartSeconds"] as? NSNumber)?.doubleValue ?? 0
      let sourceStartSeconds = (node["sourceStartSeconds"] as? NSNumber)?.doubleValue ?? 0
      let positionSeconds = sourceStartSeconds + max(0, projectSeconds - clipStartSeconds)
      audioPlayer.sync(
        positionSeconds: positionSeconds,
        isPlaying: isCurrentlyPlaying
      )
    }
  }

  private func currentProjectPlaybackSeconds() -> Double {
    if currentSourceKind == "video", let player {
      let currentSeconds = player.currentTime().seconds
      if currentSeconds.isFinite {
        let offsetWithinClip = currentSeconds - currentSourceStartSeconds
        let projectSeconds = currentClipStartSeconds + max(0, offsetWithinClip)
        if let clipEndSeconds = currentClipEndSeconds {
          return min(projectSeconds, clipEndSeconds)
        }
        return projectSeconds
      }
    }

    let fallbackOffset = currentPosition - currentSourceStartSeconds
    let fallbackSeconds = currentClipStartSeconds + max(0, fallbackOffset)
    if let clipEndSeconds = currentClipEndSeconds {
      return min(fallbackSeconds, clipEndSeconds)
    }
    return fallbackSeconds
  }

  private func sceneIdentityKey() -> String {
    var parts = [
      "pw:\(Int(currentProjectWidth))",
      "ph:\(Int(currentProjectHeight))",
      "count:\(currentSceneNodes.count)"
    ]
    let overlayNodes = currentSceneNodes.filter { node in
      guard let clipId = node["clipId"] as? String else { return true }
      return !currentBaseClipIds.contains(clipId)
    }
    parts[2] = "count:\(overlayNodes.count)"
    for node in overlayNodes.sorted(by: {
      (($0["clipId"] as? String) ?? "") < (($1["clipId"] as? String) ?? "")
    }) {
      parts.append(
        [
          node["clipId"] as? String ?? "",
          node["kind"] as? String ?? "",
          node["localPath"] as? String ?? "",
          node["displayLabel"] as? String ?? "",
          "\((node["x"] as? NSNumber)?.doubleValue ?? 0)",
          "\((node["y"] as? NSNumber)?.doubleValue ?? 0)",
          "\((node["width"] as? NSNumber)?.doubleValue ?? 0)",
          "\((node["height"] as? NSNumber)?.doubleValue ?? 0)",
          "\((node["opacity"] as? NSNumber)?.doubleValue ?? 1)",
          "\((node["rotationDegrees"] as? NSNumber)?.doubleValue ?? 0)",
          "\((node["zIndex"] as? NSNumber)?.intValue ?? 0)"
        ].joined(separator: "|")
      )
    }
    return parts.joined(separator: "||")
  }

  private func audioIdentityKey() -> String {
    let renderedNodes = currentAudioNodes.filter { node in
      let clipId = node["clipId"] as? String
      if let clipId, currentBaseClipIds.contains(clipId) {
        return false
      }
      if currentSourceKind == "video",
        let localPath = node["localPath"] as? String,
        localPath == currentSourcePath {
        return false
      }
      return true
    }
    var parts = [
      "count:\(renderedNodes.count)"
    ]
    for node in renderedNodes.sorted(by: {
      (($0["clipId"] as? String) ?? "") < (($1["clipId"] as? String) ?? "")
    }) {
      parts.append(
        [
          node["clipId"] as? String ?? "",
          node["kind"] as? String ?? "",
          node["localPath"] as? String ?? "",
          node["displayLabel"] as? String ?? "",
          "\((node["clipStartSeconds"] as? NSNumber)?.doubleValue ?? 0)",
          "\((node["clipEndSeconds"] as? NSNumber)?.doubleValue ?? 0)",
          "\((node["sourceStartSeconds"] as? NSNumber)?.doubleValue ?? 0)",
          "\((node["sourceEndSeconds"] as? NSNumber)?.doubleValue ?? 0)",
          "\((node["gain"] as? NSNumber)?.doubleValue ?? 1)",
          "\((node["isMuted"] as? Bool) ?? false)"
        ].joined(separator: "|")
      )
    }
    return parts.joined(separator: "||")
  }
}

private final class FusionOverlayVideoNodeView: UIView {
  private let playerLayer = AVPlayerLayer()
  private var player: AVPlayer?
  private var playbackObserverToken: Any?
  private var currentSourcePath: String?
  private var currentSourceStartSeconds: Double = 0
  private var currentSourceEndSeconds: Double?

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .clear
    clipsToBounds = true
    playerLayer.videoGravity = .resizeAspectFill
    layer.addSublayer(playerLayer)
  }

  required init?(coder: NSCoder) {
    return nil
  }

  deinit {
    dispose()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    playerLayer.frame = bounds
  }

  func configure(
    sourcePath: String,
    sourceStartSeconds: Double,
    sourceEndSeconds: Double?
  ) {
    currentSourceStartSeconds = max(0, sourceStartSeconds)
    currentSourceEndSeconds = sourceEndSeconds
    guard sourcePath != currentSourcePath else { return }
    currentSourcePath = sourcePath
    let newPlayer = AVPlayer(url: URL(fileURLWithPath: sourcePath))
    newPlayer.actionAtItemEnd = .pause
    newPlayer.automaticallyWaitsToMinimizeStalling = false
    newPlayer.currentItem?.preferredForwardBufferDuration = 0
    newPlayer.isMuted = true
    removePlaybackObserver()
    player?.pause()
    player = newPlayer
    playerLayer.player = newPlayer
    addPlaybackObserver(to: newPlayer)
  }

  func sync(positionSeconds: Double, isPlaying: Bool) {
    guard let player else { return }
    let targetSeconds = clampedPositionSeconds(positionSeconds)
    let current = player.currentTime().seconds
    let seekThreshold = isPlaying ? 0.18 : 0.05
    let shouldSeek = !current.isFinite || abs(current - targetSeconds) > seekThreshold
    let seekTolerance = CMTime(
      seconds: isPlaying ? (1.0 / 60.0) : 0.0,
      preferredTimescale: 600
    )

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
      if isPlaying {
        player.play()
      } else {
        player.pause()
      }
    }

    if shouldSeek {
      player.seek(
        to: CMTime(seconds: targetSeconds, preferredTimescale: 600),
        toleranceBefore: seekTolerance,
        toleranceAfter: seekTolerance
      ) { _ in
        playOrPause()
      }
    } else {
      playOrPause()
    }
  }

  func dispose() {
    player?.volume = 0
    player?.isMuted = true
    player?.pause()
    removePlaybackObserver()
    playerLayer.player = nil
    player = nil
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

private final class FusionOverlayAudioNodePlayer {
  private var player: AVPlayer?
  private var playbackObserverToken: Any?
  private var currentSourcePath: String?
  private var currentSourceStartSeconds: Double = 0
  private var currentSourceEndSeconds: Double?

  deinit {
    dispose()
  }

  func configure(
    sourcePath: String,
    sourceStartSeconds: Double,
    sourceEndSeconds: Double?,
    gain: Float,
    isMuted: Bool
  ) {
    currentSourceStartSeconds = max(0, sourceStartSeconds)
    currentSourceEndSeconds = sourceEndSeconds
    if sourcePath == currentSourcePath, let player {
      player.volume = gain
      player.isMuted = isMuted
      return
    }
    currentSourcePath = sourcePath
    let newPlayer = AVPlayer(url: URL(fileURLWithPath: sourcePath))
    newPlayer.actionAtItemEnd = .pause
    newPlayer.automaticallyWaitsToMinimizeStalling = false
    newPlayer.currentItem?.preferredForwardBufferDuration = 0
    newPlayer.volume = gain
    newPlayer.isMuted = isMuted
    removePlaybackObserver()
    player?.volume = 0
    player?.isMuted = true
    player?.pause()
    player = newPlayer
    addPlaybackObserver(to: newPlayer)
  }

  func sync(positionSeconds: Double, isPlaying: Bool) {
    guard let player else { return }
    let targetSeconds = clampedPositionSeconds(positionSeconds)
    let current = player.currentTime().seconds
    let seekThreshold = isPlaying ? 0.18 : 0.05
    let shouldSeek = !current.isFinite || abs(current - targetSeconds) > seekThreshold
    let seekTolerance = CMTime(
      seconds: isPlaying ? (1.0 / 60.0) : 0.0,
      preferredTimescale: 600
    )

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
      if isPlaying {
        player.play()
      } else {
        player.pause()
      }
    }

    if shouldSeek {
      player.seek(
        to: CMTime(seconds: targetSeconds, preferredTimescale: 600),
        toleranceBefore: seekTolerance,
        toleranceAfter: seekTolerance
      ) { _ in
        playOrPause()
      }
    } else {
      playOrPause()
    }
  }

  func dispose() {
    player?.volume = 0
    player?.isMuted = true
    player?.pause()
    removePlaybackObserver()
    player = nil
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

private final class FusionOverlayStaticNodeView: UIView {
  private let imageView = UIImageView()
  private let iconLabel = UILabel()
  private let titleLabel = UILabel()
  private let textContentLabel = UILabel()
  private let barsContainer = UIStackView()
  private var currentKind: String?
  private var currentPath: String?
  private var currentLabel: String?

  override init(frame: CGRect) {
    super.init(frame: frame)
    setupUI()
  }

  required init?(coder: NSCoder) {
    return nil
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let dynamicFontSize = min(max(bounds.height * 0.23, 18), 72)
    textContentLabel.font = UIFont.systemFont(ofSize: dynamicFontSize, weight: .heavy)
  }

  func configure(
    kind: String,
    localPath: String?,
    displayLabel: String?
  ) {
    if currentKind == kind && currentPath == localPath && currentLabel == displayLabel {
      return
    }
    currentKind = kind
    currentPath = localPath
    currentLabel = displayLabel

    imageView.isHidden = true
    iconLabel.isHidden = false
    titleLabel.isHidden = false
    textContentLabel.isHidden = true
    barsContainer.isHidden = true
    backgroundColor = UIColor(white: 0.12, alpha: 0.92)
    titleLabel.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
    titleLabel.textColor = UIColor.white.withAlphaComponent(0.88)

    switch kind {
    case "image":
      if let localPath, let image = UIImage(contentsOfFile: localPath) {
        imageView.image = image
        imageView.isHidden = false
        iconLabel.isHidden = true
        titleLabel.isHidden = true
      } else {
        iconLabel.text = "▣"
        titleLabel.text = displayLabel ?? "Image"
      }
    case "text":
      iconLabel.isHidden = true
      titleLabel.isHidden = true
      textContentLabel.isHidden = false
      textContentLabel.text =
        (displayLabel?.isEmpty == false ? displayLabel : "New Text")
      backgroundColor = .clear
    case "lipSync":
      iconLabel.isHidden = true
      titleLabel.text = displayLabel ?? "Lip Sync"
      titleLabel.font = UIFont.systemFont(ofSize: 11, weight: .medium)
      titleLabel.textColor = UIColor.white.withAlphaComponent(0.76)
      barsContainer.isHidden = false
      backgroundColor = .clear
    default:
      iconLabel.text = "▶"
      titleLabel.text = displayLabel ?? "Video"
    }
  }

  func dispose() {}

  private func setupUI() {
    backgroundColor = UIColor(white: 0.12, alpha: 0.92)
    clipsToBounds = true
    layer.cornerRadius = 11

    imageView.frame = bounds
    imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    imageView.contentMode = .scaleAspectFill
    imageView.isHidden = true
    addSubview(imageView)

    iconLabel.translatesAutoresizingMaskIntoConstraints = false
    iconLabel.font = UIFont.systemFont(ofSize: 24, weight: .bold)
    iconLabel.textColor = UIColor.white.withAlphaComponent(0.88)
    addSubview(iconLabel)

    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
    titleLabel.textColor = UIColor.white.withAlphaComponent(0.88)
    titleLabel.textAlignment = .center
    titleLabel.numberOfLines = 2
    addSubview(titleLabel)

    textContentLabel.translatesAutoresizingMaskIntoConstraints = false
    textContentLabel.font = UIFont.systemFont(ofSize: 26, weight: .heavy)
    textContentLabel.textColor = UIColor.white.withAlphaComponent(0.96)
    textContentLabel.textAlignment = .center
    textContentLabel.numberOfLines = 0
    textContentLabel.adjustsFontSizeToFitWidth = true
    textContentLabel.minimumScaleFactor = 0.45
    textContentLabel.layer.shadowColor = UIColor.black.withAlphaComponent(0.36).cgColor
    textContentLabel.layer.shadowOpacity = 1
    textContentLabel.layer.shadowRadius = 8
    textContentLabel.layer.shadowOffset = CGSize(width: 0, height: 3)
    textContentLabel.isHidden = true
    addSubview(textContentLabel)

    barsContainer.translatesAutoresizingMaskIntoConstraints = false
    barsContainer.axis = .horizontal
    barsContainer.alignment = .center
    barsContainer.distribution = .fillEqually
    barsContainer.spacing = 4
    barsContainer.isHidden = true
    addSubview(barsContainer)

    for height in [14.0, 22.0, 18.0, 26.0, 16.0] {
      let bar = UIView()
      bar.backgroundColor = UIColor(red: 0.28, green: 0.88, blue: 0.83, alpha: 0.92)
      bar.layer.cornerRadius = 2
      bar.translatesAutoresizingMaskIntoConstraints = false
      NSLayoutConstraint.activate([
        bar.widthAnchor.constraint(equalToConstant: 5),
        bar.heightAnchor.constraint(equalToConstant: height),
      ])
      barsContainer.addArrangedSubview(bar)
    }

    NSLayoutConstraint.activate([
      iconLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
      iconLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -10),
      titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 8),
      titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
      titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
      titleLabel.topAnchor.constraint(equalTo: iconLabel.bottomAnchor, constant: 6),
      textContentLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
      textContentLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
      textContentLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
      barsContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
      barsContainer.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -6),
      barsContainer.heightAnchor.constraint(equalToConstant: 30),
      titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -8),
    ])
  }
}
