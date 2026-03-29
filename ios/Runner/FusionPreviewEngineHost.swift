import Foundation

struct FusionPreviewResolvedConfiguration {
  let projectId: Int64
  let positionSeconds: Double
  let isPlaying: Bool
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
  let continuityKind: String?
  let sceneNodes: [[String: Any]]
  let audioNodes: [[String: Any]]
}

struct FusionPreviewTransportCommandEnvelope {
  let projectId: Int64
  let transportRevision: Int64
  let kind: String
  let positionSeconds: Double?
  let isPlaying: Bool?
}

final class FusionPreviewEngineHost {
  let isScaffoldReady = true
  private(set) var lastConfiguration: FusionPreviewResolvedConfiguration?
  private(set) var lastCommand: FusionPreviewTransportCommandEnvelope?

  func configurePreviewEngine(_ configuration: FusionPreviewResolvedConfiguration) {
    lastConfiguration = configuration
  }

  func dispatchPreviewCommand(_ command: FusionPreviewTransportCommandEnvelope) {
    lastCommand = command
  }
}
