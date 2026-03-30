import 'package:flutter/material.dart';

import '../../../../core/engine/engine_contract.dart';
import 'composition_preview_overlay.dart';

class PreviewTransformOverlay extends StatefulWidget {
  const PreviewTransformOverlay({
    super.key,
    required this.nodes,
    required this.projectWidth,
    required this.projectHeight,
    required this.baseClipId,
    required this.selectedClipId,
    required this.selectedNode,
    required this.enabled,
    required this.onTransformStart,
    required this.onTransformChanged,
    required this.onTransformCommitted,
  });

  final List<EngineCompositionNodeSnapshot> nodes;
  final int projectWidth;
  final int projectHeight;
  final String? baseClipId;
  final String? selectedClipId;
  final EngineCompositionNodeSnapshot? selectedNode;
  final bool enabled;
  final VoidCallback onTransformStart;
  final ValueChanged<EngineVisualTransformSnapshot> onTransformChanged;
  final ValueChanged<EngineVisualTransformSnapshot> onTransformCommitted;

  @override
  State<PreviewTransformOverlay> createState() =>
      _PreviewTransformOverlayState();
}

class _PreviewTransformOverlayState extends State<PreviewTransformOverlay> {
  bool _gestureAccepted = false;
  double _focalRatioX = 0.5;
  double _focalRatioY = 0.5;
  EngineVisualTransformSnapshot? _gestureStartTransform;
  EngineVisualTransformSnapshot? _latestTransform;

  @override
  Widget build(BuildContext context) {
    if (widget.projectWidth <= 0 || widget.projectHeight <= 0) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final selectedNode = widget.selectedNode;
        return Stack(
          fit: StackFit.expand,
          children: [
            CompositionPreviewOverlay(
              nodes: widget.nodes,
              projectWidth: widget.projectWidth,
              projectHeight: widget.projectHeight,
              baseClipId: widget.baseClipId,
              selectedClipId: widget.selectedClipId,
            ),
            if (widget.enabled && selectedNode != null)
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onScaleStart: (details) =>
                    _handleScaleStart(details, constraints, selectedNode),
                onScaleUpdate: (details) =>
                    _handleScaleUpdate(details, constraints),
                onScaleEnd: _handleScaleEnd,
              ),
          ],
        );
      },
    );
  }

  void _handleScaleStart(
    ScaleStartDetails details,
    BoxConstraints constraints,
    EngineCompositionNodeSnapshot selectedNode,
  ) {
    final projectPoint = _projectOffset(details.localFocalPoint, constraints);
    final rect = Rect.fromLTWH(
      selectedNode.transform.x,
      selectedNode.transform.y,
      selectedNode.transform.width,
      selectedNode.transform.height,
    ).inflate(32);
    if (!rect.contains(projectPoint)) {
      _gestureAccepted = false;
      _gestureStartTransform = null;
      _latestTransform = null;
      return;
    }

    _gestureAccepted = true;
    _gestureStartTransform = selectedNode.transform;
    _latestTransform = selectedNode.transform;
    _focalRatioX = ((projectPoint.dx - selectedNode.transform.x) /
            selectedNode.transform.width)
        .clamp(0.0, 1.0)
        .toDouble();
    _focalRatioY = ((projectPoint.dy - selectedNode.transform.y) /
            selectedNode.transform.height)
        .clamp(0.0, 1.0)
        .toDouble();
    widget.onTransformStart();
  }

  void _handleScaleUpdate(
    ScaleUpdateDetails details,
    BoxConstraints constraints,
  ) {
    if (!_gestureAccepted) {
      return;
    }

    final start = _gestureStartTransform;
    if (start == null) {
      return;
    }

    final focalPoint = _projectOffset(details.localFocalPoint, constraints);
    final maxWidth = widget.projectWidth * 4.0;
    final maxHeight = widget.projectHeight * 4.0;
    final isBaseClip = widget.baseClipId != null &&
        widget.baseClipId == widget.selectedNode?.clipId;
    final minWidth = isBaseClip ? widget.projectWidth.toDouble() : 80.0;
    final minHeight = isBaseClip ? widget.projectHeight.toDouble() : 80.0;
    final nextWidth =
        (start.width * details.scale).clamp(minWidth, maxWidth).toDouble();
    final nextHeight =
        (start.height * details.scale).clamp(minHeight, maxHeight).toDouble();
    var nextTransform = start.copyWith(
      x: focalPoint.dx - (_focalRatioX * nextWidth),
      y: focalPoint.dy - (_focalRatioY * nextHeight),
      width: nextWidth,
      height: nextHeight,
    );
    if (isBaseClip) {
      nextTransform = _clampBaseClipTransform(nextTransform);
    }
    _latestTransform = nextTransform;
    widget.onTransformChanged(nextTransform);
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    if (!_gestureAccepted) {
      return;
    }

    final committed = _latestTransform;
    _gestureAccepted = false;
    _gestureStartTransform = null;
    _latestTransform = null;
    if (committed != null) {
      widget.onTransformCommitted(committed);
    }
  }

  Offset _projectOffset(Offset localPoint, BoxConstraints constraints) {
    final width = constraints.maxWidth <= 0 ? 1.0 : constraints.maxWidth;
    final height = constraints.maxHeight <= 0 ? 1.0 : constraints.maxHeight;
    return Offset(
      localPoint.dx / width * widget.projectWidth,
      localPoint.dy / height * widget.projectHeight,
    );
  }

  EngineVisualTransformSnapshot _clampBaseClipTransform(
    EngineVisualTransformSnapshot transform,
  ) {
    final minWidth = widget.projectWidth.toDouble();
    final minHeight = widget.projectHeight.toDouble();
    final width = transform.width < minWidth ? minWidth : transform.width;
    final height = transform.height < minHeight ? minHeight : transform.height;
    final minX = widget.projectWidth.toDouble() - width;
    final minY = widget.projectHeight.toDouble() - height;
    return transform.copyWith(
      x: transform.x.clamp(minX, 0.0).toDouble(),
      y: transform.y.clamp(minY, 0.0).toDouble(),
      width: width,
      height: height,
    );
  }
}
