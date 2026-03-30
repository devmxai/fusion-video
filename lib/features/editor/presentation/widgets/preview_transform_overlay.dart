import 'package:flutter/material.dart';

import '../../../../core/engine/engine_contract.dart';
import '../../../../core/theme/app_theme.dart';
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
  State<PreviewTransformOverlay> createState() => _PreviewTransformOverlayState();
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
            if (selectedNode != null)
              IgnorePointer(
                child: _SelectedClipBounds(
                  node: selectedNode,
                  projectWidth: widget.projectWidth,
                  projectHeight: widget.projectHeight,
                ),
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
    final nextWidth =
        (start.width * details.scale).clamp(80.0, maxWidth).toDouble();
    final nextHeight =
        (start.height * details.scale).clamp(80.0, maxHeight).toDouble();
    final nextTransform = start.copyWith(
      x: focalPoint.dx - (_focalRatioX * nextWidth),
      y: focalPoint.dy - (_focalRatioY * nextHeight),
      width: nextWidth,
      height: nextHeight,
    );
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
}

class _SelectedClipBounds extends StatelessWidget {
  const _SelectedClipBounds({
    required this.node,
    required this.projectWidth,
    required this.projectHeight,
  });

  final EngineCompositionNodeSnapshot node;
  final int projectWidth;
  final int projectHeight;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final widthScale = constraints.maxWidth / projectWidth;
        final heightScale = constraints.maxHeight / projectHeight;
        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              left: node.transform.x * widthScale,
              top: node.transform.y * heightScale,
              width: node.transform.width * widthScale,
              height: node.transform.height * heightScale,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.74),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: FxPalette.accent.withOpacity(0.18),
                      blurRadius: 14,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
