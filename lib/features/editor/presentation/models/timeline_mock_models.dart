enum TimelineTrackKind {
  video,
  image,
  audio,
  text,
  lipSync,
}

enum TimelineClipTone {
  hero,
  heroMuted,
  placeholder,
}

enum TimelineClipType {
  media,
  placeholder,
}

class TimelineClipData {
  const TimelineClipData({
    required this.id,
    required this.duration,
    required this.type,
    required this.tone,
    this.label,
    this.splitGroupId,
  });

  final String id;
  final double duration;
  final TimelineClipType type;
  final TimelineClipTone tone;
  final String? label;
  final String? splitGroupId;

  TimelineClipData copyWith({
    String? id,
    double? duration,
    TimelineClipType? type,
    TimelineClipTone? tone,
    String? label,
    String? splitGroupId,
  }) {
    return TimelineClipData(
      id: id ?? this.id,
      duration: duration ?? this.duration,
      type: type ?? this.type,
      tone: tone ?? this.tone,
      label: label ?? this.label,
      splitGroupId: splitGroupId ?? this.splitGroupId,
    );
  }

  double visualWidth(double secondsWidth) {
    final baseWidth = duration * secondsWidth;
    final minWidth = type == TimelineClipType.media ? 84.0 : 118.0;
    return baseWidth < minWidth ? minWidth : baseWidth;
  }
}

class TimelineTrackData {
  const TimelineTrackData({
    required this.kind,
    required this.clips,
    this.placeholderLabel,
  });

  final TimelineTrackKind kind;
  final List<TimelineClipData> clips;
  final String? placeholderLabel;

  TimelineTrackData copyWith({
    TimelineTrackKind? kind,
    List<TimelineClipData>? clips,
    String? placeholderLabel,
  }) {
    return TimelineTrackData(
      kind: kind ?? this.kind,
      clips: clips ?? this.clips,
      placeholderLabel: placeholderLabel ?? this.placeholderLabel,
    );
  }
}

List<TimelineTrackData> buildMockTimelineTracks() {
  return const [
    TimelineTrackData(
      kind: TimelineTrackKind.video,
      clips: [
        TimelineClipData(
          id: 'video-1',
          duration: 3.15,
          type: TimelineClipType.media,
          tone: TimelineClipTone.hero,
        ),
        TimelineClipData(
          id: 'video-2',
          duration: 0.72,
          type: TimelineClipType.media,
          tone: TimelineClipTone.heroMuted,
        ),
      ],
    ),
    TimelineTrackData(
      kind: TimelineTrackKind.image,
      placeholderLabel: 'Add image',
      clips: [
        TimelineClipData(
          id: 'image-1',
          duration: 1.4,
          type: TimelineClipType.placeholder,
          tone: TimelineClipTone.placeholder,
          label: 'Add image',
        ),
        TimelineClipData(
          id: 'image-2',
          duration: 1.12,
          type: TimelineClipType.placeholder,
          tone: TimelineClipTone.placeholder,
          label: 'Add image',
        ),
      ],
    ),
    TimelineTrackData(
      kind: TimelineTrackKind.audio,
      placeholderLabel: 'Add audio',
      clips: [
        TimelineClipData(
          id: 'audio-1',
          duration: 1.48,
          type: TimelineClipType.placeholder,
          tone: TimelineClipTone.placeholder,
          label: 'Add audio',
        ),
      ],
    ),
    TimelineTrackData(
      kind: TimelineTrackKind.text,
      placeholderLabel: 'Add text',
      clips: [
        TimelineClipData(
          id: 'text-1',
          duration: 1.52,
          type: TimelineClipType.placeholder,
          tone: TimelineClipTone.placeholder,
          label: 'Add text',
        ),
      ],
    ),
    TimelineTrackData(
      kind: TimelineTrackKind.lipSync,
      placeholderLabel: 'Lip sync',
      clips: [
        TimelineClipData(
          id: 'lip-1',
          duration: 1.1,
          type: TimelineClipType.placeholder,
          tone: TimelineClipTone.placeholder,
          label: 'Lip sync',
        ),
        TimelineClipData(
          id: 'lip-2',
          duration: 1.25,
          type: TimelineClipType.placeholder,
          tone: TimelineClipTone.placeholder,
          label: 'Lip sync',
        ),
      ],
    ),
  ];
}
