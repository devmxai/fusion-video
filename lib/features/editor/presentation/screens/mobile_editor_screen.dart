import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../../core/theme/app_theme.dart';
import '../models/editor_media_tab.dart';
import '../models/mock_asset_item.dart';
import '../models/timeline_mock_models.dart';
import '../widgets/editor_tools_bar.dart';
import '../widgets/editor_top_bar.dart';
import '../widgets/media_bottom_sheet.dart';
import '../widgets/media_dock.dart';
import '../widgets/preview_stage.dart';
import '../widgets/timeline_panel.dart';

class MobileEditorScreen extends StatefulWidget {
  const MobileEditorScreen({super.key});

  @override
  State<MobileEditorScreen> createState() => _MobileEditorScreenState();
}

class _MobileEditorScreenState extends State<MobileEditorScreen>
    with TickerProviderStateMixin {
  static const double _timelineDuration = 5;

  EditorMediaTab activeTab = EditorMediaTab.video;
  late final Ticker _playbackTicker;
  Duration? _lastPlaybackTick;
  bool _isPlaying = false;
  double _currentSeconds = 0;
  String? _selectedClipId = 'video-1';
  late List<TimelineTrackData> _tracks;

  static const mockAssets = <MockAssetItem>[
    MockAssetItem(
        id: 'v1', tab: EditorMediaTab.video, label: 'Travel Story', tone: 28),
    MockAssetItem(
        id: 'v2', tab: EditorMediaTab.video, label: 'Portrait Reel', tone: 210),
    MockAssetItem(
        id: 'i1', tab: EditorMediaTab.image, label: 'Cover Image', tone: 36),
    MockAssetItem(
        id: 'i2', tab: EditorMediaTab.image, label: 'Sticker Pack', tone: 162),
    MockAssetItem(
        id: 'a1', tab: EditorMediaTab.audio, label: 'Voice Track', tone: 286),
    MockAssetItem(
        id: 'a2', tab: EditorMediaTab.audio, label: 'Ambient Bed', tone: 248),
    MockAssetItem(
        id: 't1', tab: EditorMediaTab.text, label: 'Title Preset', tone: 118),
    MockAssetItem(
        id: 't2', tab: EditorMediaTab.text, label: 'Caption Block', tone: 78),
    MockAssetItem(
        id: 'l1',
        tab: EditorMediaTab.lipSync,
        label: 'Arabic Mouth Pack',
        tone: 342),
  ];

  @override
  void initState() {
    super.initState();
    _tracks = buildMockTimelineTracks();
    _playbackTicker = createTicker(_handlePlaybackTick);
  }

  @override
  void dispose() {
    _playbackTicker.dispose();
    super.dispose();
  }

  void _handlePlaybackTick(Duration elapsed) {
    if (!_isPlaying) {
      return;
    }

    if (_lastPlaybackTick == null) {
      _lastPlaybackTick = elapsed;
      return;
    }

    final deltaSeconds =
        (elapsed - _lastPlaybackTick!).inMicroseconds / 1000000.0;
    _lastPlaybackTick = elapsed;
    if (deltaSeconds <= 0) {
      return;
    }

    final nextSeconds = (_currentSeconds + deltaSeconds).clamp(
      0.0,
      _timelineDuration,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _currentSeconds = nextSeconds;
    });

    if (nextSeconds >= _timelineDuration) {
      _togglePlayback(forceStop: true);
    }
  }

  void _togglePlayback({bool forceStop = false}) {
    if (_isPlaying || forceStop) {
      _playbackTicker.stop();
      setState(() {
        _isPlaying = false;
      });
      _lastPlaybackTick = null;
      return;
    }

    _lastPlaybackTick = null;
    setState(() {
      _isPlaying = true;
    });
    _playbackTicker.start();
  }

  void _setCurrentSeconds(double value) {
    final next = value.clamp(0.0, _timelineDuration);
    if ((next - _currentSeconds).abs() < 0.001) {
      return;
    }
    setState(() {
      _currentSeconds = next;
    });
  }

  void _selectClip(String clipId) {
    setState(() {
      _selectedClipId = clipId;
    });
  }

  void _splitSelectedClip() {
    final selectedClipId = _selectedClipId;
    if (selectedClipId == null) {
      return;
    }

    final updatedTracks = <TimelineTrackData>[];
    var didSplit = false;
    final splitStamp = DateTime.now().microsecondsSinceEpoch.toString();

    for (final track in _tracks) {
      var elapsed = 0.0;
      final nextClips = <TimelineClipData>[];

      for (final clip in track.clips) {
        final start = elapsed;
        final end = start + clip.duration;
        elapsed = end;

        if (!didSplit &&
            clip.id == selectedClipId &&
            clip.type == TimelineClipType.media &&
            _currentSeconds > start + 0.05 &&
            _currentSeconds < end - 0.05) {
          final leftDuration = _currentSeconds - start;
          final rightDuration = end - _currentSeconds;
          final splitGroupId = 'bridge_$splitStamp';

          final leftClip = clip.copyWith(
            id: '${clip.id}_a_$splitStamp',
            duration: leftDuration,
            splitGroupId: splitGroupId,
          );
          final rightClip = clip.copyWith(
            id: '${clip.id}_b_$splitStamp',
            duration: rightDuration,
            splitGroupId: splitGroupId,
          );

          nextClips
            ..add(leftClip)
            ..add(rightClip);
          didSplit = true;
          continue;
        }

        nextClips.add(clip);
      }

      updatedTracks.add(track.copyWith(clips: nextClips));
    }

    if (!didSplit) {
      return;
    }

    setState(() {
      _tracks = updatedTracks;
      _selectedClipId = '${selectedClipId}_b_$splitStamp';
    });
  }

  Future<void> _openMediaSheet(EditorMediaTab tab) async {
    setState(() => activeTab = tab);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.52),
      isScrollControlled: true,
      builder: (context) {
        return MediaBottomSheet(
          activeTab: activeTab,
          assets: mockAssets,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Container(
              color: FxPalette.background,
              child: Column(
                children: [
                  const EditorTopBar(),
                  Expanded(
                    flex: 4,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 220),
                      child: const PreviewStage(),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    flex: 4,
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(2, 0, 2, 4),
                      decoration: BoxDecoration(
                        color: FxPalette.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: FxPalette.divider,
                          width: 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 4, 4, 3),
                            child: EditorToolsBar(
                              embedded: true,
                              isPlaying: _isPlaying,
                              onSplit: _splitSelectedClip,
                              onPlayToggle: _togglePlayback,
                            ),
                          ),
                          Divider(
                            height: 1,
                            thickness: 1,
                            color: FxPalette.dividerSoft.withOpacity(0.9),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(0, 2, 0, 0),
                              child: TimelinePanel(
                                embedded: true,
                                tracks: _tracks,
                                currentSeconds: _currentSeconds,
                                timelineDuration: _timelineDuration,
                                isPlaying: _isPlaying,
                                selectedClipId: _selectedClipId,
                                onTimeChanged: _setCurrentSeconds,
                                onClipSelected: _selectClip,
                              ),
                            ),
                          ),
                          Divider(
                            height: 1,
                            thickness: 1,
                            color: FxPalette.dividerSoft.withOpacity(0.9),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 3, 4, 3),
                            child: MediaDock(
                              activeTab: activeTab,
                              onTap: _openMediaSheet,
                              embedded: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
