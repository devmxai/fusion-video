import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../models/timeline_mock_models.dart';

class TimelinePanel extends StatefulWidget {
  const TimelinePanel({
    super.key,
    this.embedded = false,
    required this.tracks,
    required this.currentSeconds,
    required this.timelineDuration,
    required this.isPlaying,
    required this.selectedClipId,
    required this.onTimeChanged,
    required this.onClipSelected,
  });

  final bool embedded;
  final List<TimelineTrackData> tracks;
  final double currentSeconds;
  final double timelineDuration;
  final bool isPlaying;
  final String? selectedClipId;
  final ValueChanged<double> onTimeChanged;
  final ValueChanged<String> onClipSelected;

  @override
  State<TimelinePanel> createState() => _TimelinePanelState();
}

class _TimelinePanelState extends State<TimelinePanel> {
  static const double _panelPadding = 8;
  static const double _rowHeight = 38;
  static const double _rowGap = 6;
  static const double _controlTileSize = 36;
  static const double _controlGap = 8;
  static const double _trailingPadding = 120;
  static const double _minSecondsWidth = 92;
  static const double _maxSecondsWidth = 260;

  final ScrollController _scrollController = ScrollController();
  final ScrollController _verticalController = ScrollController();

  double _playheadLeft = 0;
  double _leadingOffset = 0;
  double _secondsWidth = 118;
  double _scaleStartSecondsWidth = 118;
  double _scaleStartFocusTime = 0;
  bool _isSyncingFromExternal = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
  }

  @override
  void didUpdateWidget(covariant TimelinePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.currentSeconds - widget.currentSeconds).abs() > 0.001 ||
        oldWidget.isPlaying != widget.isPlaying) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncToTime());
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _scaleStartSecondsWidth = _secondsWidth;
    _scaleStartFocusTime = widget.currentSeconds;
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount < 2) {
      return;
    }

    final nextWidth = (_scaleStartSecondsWidth * details.scale)
        .clamp(_minSecondsWidth, _maxSecondsWidth)
        .toDouble();

    if ((nextWidth - _secondsWidth).abs() < 0.5) {
      return;
    }

    setState(() {
      _secondsWidth = nextWidth;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      final nextOffset = (_scaleStartFocusTime * _secondsWidth)
          .clamp(0, _scrollController.position.maxScrollExtent)
          .toDouble();
      _scrollController.jumpTo(nextOffset);
    });
  }

  void _handleScroll() {
    if (_isSyncingFromExternal) {
      return;
    }

    final offset = _scrollController.hasClients
        ? _scrollController.offset.clamp(0, double.infinity)
        : 0.0;
    final nextSeconds =
        (offset / _secondsWidth).clamp(0, widget.timelineDuration).toDouble();

    if ((nextSeconds - widget.currentSeconds).abs() > 0.005) {
      widget.onTimeChanged(nextSeconds);
    }
  }

  void _syncToTime() {
    if (!_scrollController.hasClients) {
      return;
    }

    final target = (widget.currentSeconds * _secondsWidth)
        .clamp(0, _scrollController.position.maxScrollExtent)
        .toDouble();

    if ((_scrollController.offset - target).abs() < 0.5) {
      return;
    }

    _isSyncingFromExternal = true;
    _scrollController.jumpTo(target);
    _isSyncingFromExternal = false;
  }

  String _formatClock(double value) {
    final totalMillis =
        (value.clamp(0, widget.timelineDuration) * 1000).round();
    final seconds = (totalMillis ~/ 1000).toString().padLeft(2, '0');
    final millis = (totalMillis % 1000).toString().padLeft(3, '0');
    return '00:$seconds.$millis';
  }

  String _formatWholeSeconds(double value) {
    final seconds = value.round().toString().padLeft(2, '0');
    return '00:$seconds';
  }

  double _buildContentWidth() {
    final farthest = widget.tracks.fold<double>(
      0,
      (maxWidth, track) {
        final clipsWidth = track.clips.fold<double>(
          0,
          (sum, clip) => sum + clip.visualWidth(_secondsWidth) + _controlGap,
        );
        return math.max(maxWidth, clipsWidth);
      },
    );

    return _leadingOffset +
        _controlTileSize +
        _controlGap +
        farthest +
        _trailingPadding;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final contentViewportWidth = constraints.maxWidth - (_panelPadding * 2);
        _playheadLeft = math.min(contentViewportWidth * 0.46, 156);
        _leadingOffset = math.max(
          6,
          _playheadLeft - _controlTileSize - _controlGap,
        );
        final contentWidth = _buildContentWidth();

        return Container(
          padding: const EdgeInsets.fromLTRB(
            _panelPadding,
            _panelPadding,
            _panelPadding,
            10,
          ),
          decoration: BoxDecoration(
            color: widget.embedded ? Colors.transparent : FxPalette.surface,
            borderRadius: BorderRadius.circular(widget.embedded ? 0 : 20),
            border: widget.embedded
                ? null
                : Border.all(color: FxPalette.divider, width: 1),
          ),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 18,
                    child: Stack(
                      children: [
                        Positioned(
                          left: 0,
                          top: 0,
                          child: Text(
                            '${_formatClock(widget.currentSeconds)} / ${_formatWholeSeconds(widget.timelineDuration)}',
                            style: const TextStyle(
                              color: FxPalette.textPrimary,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.1,
                            ),
                          ),
                        ),
                        Positioned.fill(
                          left: _leadingOffset,
                          child: IgnorePointer(
                            child: Row(
                              children: List.generate(
                                widget.timelineDuration.floor() + 1,
                                (index) => Expanded(
                                  child: Align(
                                    alignment: Alignment.topLeft,
                                    child: Text(
                                      _formatWholeSeconds(index.toDouble()),
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.58),
                                        fontSize: 9,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onScaleStart: _handleScaleStart,
                      onScaleUpdate: _handleScaleUpdate,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SingleChildScrollView(
                          controller: _scrollController,
                          scrollDirection: Axis.horizontal,
                          physics: const ClampingScrollPhysics(),
                          child: SizedBox(
                            width: contentWidth,
                            child: SingleChildScrollView(
                              controller: _verticalController,
                              physics: const ClampingScrollPhysics(),
                              child: Column(
                                children: [
                                  for (var i = 0;
                                      i < widget.tracks.length;
                                      i++) ...[
                                    _TimelineTrackRow(
                                      leadingOffset: _leadingOffset,
                                      controlTileSize: _controlTileSize,
                                      controlGap: _controlGap,
                                      rowHeight: _rowHeight,
                                      secondsWidth: _secondsWidth,
                                      track: widget.tracks[i],
                                      selectedClipId: widget.selectedClipId,
                                      onClipSelected: widget.onClipSelected,
                                    ),
                                    if (i != widget.tracks.length - 1)
                                      const SizedBox(height: _rowGap),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Positioned(
                left: _playheadLeft,
                top: 30,
                bottom: 10,
                child: IgnorePointer(
                  child: Container(
                    width: 2,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.white.withOpacity(0.18),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TimelineTrackRow extends StatelessWidget {
  const _TimelineTrackRow({
    required this.leadingOffset,
    required this.controlTileSize,
    required this.controlGap,
    required this.rowHeight,
    required this.secondsWidth,
    required this.track,
    required this.selectedClipId,
    required this.onClipSelected,
  });

  final double leadingOffset;
  final double controlTileSize;
  final double controlGap;
  final double rowHeight;
  final double secondsWidth;
  final TimelineTrackData track;
  final String? selectedClipId;
  final ValueChanged<String> onClipSelected;

  IconData get _trackIcon {
    switch (track.kind) {
      case TimelineTrackKind.video:
        return Icons.videocam_rounded;
      case TimelineTrackKind.image:
        return Icons.image_rounded;
      case TimelineTrackKind.audio:
        return Icons.music_note_rounded;
      case TimelineTrackKind.text:
        return Icons.text_fields_rounded;
      case TimelineTrackKind.lipSync:
        return Icons.graphic_eq_rounded;
    }
  }

  IconData get _clipIcon {
    switch (track.kind) {
      case TimelineTrackKind.video:
        return Icons.videocam_rounded;
      case TimelineTrackKind.image:
        return Icons.image_rounded;
      case TimelineTrackKind.audio:
        return Icons.music_note_rounded;
      case TimelineTrackKind.text:
        return Icons.text_fields_rounded;
      case TimelineTrackKind.lipSync:
        return Icons.graphic_eq_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final rowChildren = <Widget>[
      SizedBox(width: leadingOffset),
      Container(
        width: controlTileSize,
        height: controlTileSize,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Colors.white.withOpacity(0.05),
            width: 1,
          ),
        ),
        child: Icon(
          _trackIcon,
          size: 18,
          color: FxPalette.textMuted,
        ),
      ),
      SizedBox(width: controlGap),
    ];

    for (var i = 0; i < track.clips.length; i++) {
      final clip = track.clips[i];
      final isSelected = selectedClipId == clip.id;

      rowChildren.add(
        clip.type == TimelineClipType.placeholder
            ? _TimelinePlaceholderClip(
                width: clip.visualWidth(secondsWidth),
                label: clip.label ?? track.placeholderLabel ?? 'Add',
                isSelected: isSelected,
                onTap: () => onClipSelected(clip.id),
              )
            : _TimelineMediaClip(
                width: clip.visualWidth(secondsWidth),
                tone: clip.tone,
                icon: _clipIcon,
                isSelected: isSelected,
                onTap: () => onClipSelected(clip.id),
              ),
      );

      if (i != track.clips.length - 1) {
        final next = track.clips[i + 1];
        final showBridge =
            clip.splitGroupId != null && clip.splitGroupId == next.splitGroupId;

        rowChildren.add(
          showBridge ? const _TransitionBridge() : SizedBox(width: controlGap),
        );
      }
    }

    return SizedBox(
      height: rowHeight,
      child: Row(children: rowChildren),
    );
  }
}

class _TimelineMediaClip extends StatelessWidget {
  const _TimelineMediaClip({
    required this.width,
    required this.tone,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final double width;
  final TimelineClipTone tone;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      TimelineClipTone.hero => const Color(0xFF7BFF43),
      TimelineClipTone.heroMuted => const Color(0xFF5BD83A),
      TimelineClipTone.placeholder => FxPalette.clipFill,
    };

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: width,
        height: 34,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? FxPalette.accent.withOpacity(0.95)
                : color.withOpacity(0.0),
            width: isSelected ? 1.4 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: FxPalette.accent.withOpacity(0.16),
                    blurRadius: 8,
                  ),
                ]
              : null,
        ),
        child: Row(
          children: List.generate(
            math.max(2, width ~/ 74),
            (index) => Expanded(
              child: Center(
                child: Icon(
                  icon,
                  size: 18,
                  color: Colors.black.withOpacity(0.85),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TimelinePlaceholderClip extends StatelessWidget {
  const _TimelinePlaceholderClip({
    required this.width,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final double width;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isCompact = width < 126;
    final hideLabel = width < 108;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: width,
        height: 34,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? FxPalette.accent.withOpacity(0.85)
                : Colors.white.withOpacity(0.03),
            width: isSelected ? 1.2 : 1,
          ),
        ),
        padding: EdgeInsets.symmetric(horizontal: isCompact ? 8 : 12),
        child: Row(
          children: [
            const Icon(
              Icons.add_rounded,
              size: 18,
              color: FxPalette.textMuted,
            ),
            if (!hideLabel) ...[
              SizedBox(width: isCompact ? 4 : 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: FxPalette.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TransitionBridge extends StatelessWidget {
  const _TransitionBridge();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: SizedBox(
        width: 18,
        height: 34,
        child: Center(
          child: Container(
            width: 16,
            height: 12,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: FxPalette.accent.withOpacity(0.28),
                width: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
