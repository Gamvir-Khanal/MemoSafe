import 'dart:convert';

import 'package:flutter/material.dart';

/// A single freehand stroke: an ordered list of points plus the color and
/// width it was drawn with. Points are stored in the canvas's local pixel
/// coordinates at the time of drawing.
class DrawStroke {
  final List<Offset> points;
  final Color color;
  final double width;

  DrawStroke({required this.points, required this.color, required this.width});

  Map<String, dynamic> toJson() => {
    'points': points.map((p) => [p.dx, p.dy]).toList(),
    'color': color.value,
    'width': width,
  };

  factory DrawStroke.fromJson(Map<String, dynamic> json) {
    final rawPoints = json['points'] as List<dynamic>? ?? [];
    return DrawStroke(
      points: rawPoints
          .map(
            (p) => Offset((p[0] as num).toDouble(), (p[1] as num).toDouble()),
          )
          .toList(),
      color: Color((json['color'] as num?)?.toInt() ?? Colors.black.value),
      width: (json['width'] as num?)?.toDouble() ?? 4.0,
    );
  }

  static String encodeList(List<DrawStroke> strokes) =>
      jsonEncode(strokes.map((e) => e.toJson()).toList());

  static List<DrawStroke> decodeList(String? raw) {
    if (raw == null || raw.trim().isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((e) => DrawStroke.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }
}

/// Paints every stroke onto the canvas, plus whatever stroke is currently
/// mid-draw.
class SketchPainter extends CustomPainter {
  final List<DrawStroke> strokes;
  final DrawStroke? liveStroke;

  // Use the existing paint logic[cite: 1]
  SketchPainter({required this.strokes, this.liveStroke});

  void _paintStroke(Canvas canvas, DrawStroke stroke) {
    if (stroke.points.isEmpty) return;
    final paint = Paint()
      ..color = stroke.color
      ..strokeWidth = stroke.width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    if (stroke.points.length == 1) {
      canvas.drawCircle(
        stroke.points.first,
        stroke.width / 2,
        paint..style = PaintingStyle.fill,
      );
      return;
    }
    final path = Path()..moveTo(stroke.points.first.dx, stroke.points.first.dy);
    for (final point in stroke.points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      _paintStroke(canvas, stroke);
    }
    if (liveStroke != null) _paintStroke(canvas, liveStroke!);
  }

  @override
  bool shouldRepaint(covariant SketchPainter oldDelegate) => true;
}

/// Interactive freehand sketch canvas supporting 2D scrolling, zoom, undo, and redo.
class SketchPad extends StatefulWidget {
  final List<DrawStroke> initialStrokes;
  final ValueChanged<List<DrawStroke>> onChanged;
  final Color color;
  final double strokeWidth;

  const SketchPad({
    super.key,
    required this.initialStrokes,
    required this.onChanged,
    required this.color,
    required this.strokeWidth,
  });

  @override
  State<SketchPad> createState() => SketchPadState();
}

class SketchPadState extends State<SketchPad> {
  late List<DrawStroke> _strokes;
  final List<DrawStroke> _redoStack = []; // Holds undone strokes
  DrawStroke? _live;

  final TransformationController _transformationController =
      TransformationController();

  bool _isDrawing = false;
  late Matrix4 _startMatrix;
  late Offset _startFocalPoint;

  @override
  void initState() {
    super.initState();
    _strokes = List.of(widget.initialStrokes);
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  Offset _screenToCanvas(Offset screenOffset) {
    return _transformationController.toScene(screenOffset);
  }

  void _startStroke(Offset canvasPoint) {
    setState(() {
      _isDrawing = true;
      _live = DrawStroke(
        points: [canvasPoint],
        color: widget.color,
        width: widget.strokeWidth,
      );
    });
  }

  void _extendStroke(Offset canvasPoint) {
    if (_live == null) return;
    setState(() {
      _live = DrawStroke(
        points: [..._live!.points, canvasPoint],
        color: _live!.color,
        width: _live!.width,
      );
    });
  }

  void _endStroke() {
    _isDrawing = false;
    if (_live == null) return;
    setState(() {
      _strokes.add(_live!);
      _live = null;
      _redoStack.clear(); // Drawing breaks the old timeline, clear redo cash!
    });
    widget.onChanged(_strokes);
  }

  void undo() {
    if (_strokes.isEmpty) return;
    setState(() {
      final popped = _strokes.removeLast();
      _redoStack.add(popped); // Save to redo stack
    });
    widget.onChanged(_strokes);
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    setState(() {
      final restored = _redoStack.removeLast();
      _strokes.add(restored); // Put back onto visible canvas
    });
    widget.onChanged(_strokes);
  }

  void clear() {
    if (_strokes.isEmpty && _redoStack.isEmpty) return;
    setState(() {
      _strokes.clear();
      _redoStack.clear();
    });
    widget.onChanged(_strokes);
  }

  bool get isEmpty => _strokes.isEmpty;
  bool get canUndo => _strokes.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  void resetView() {
    setState(() {
      _transformationController.value = Matrix4.identity();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        color: Colors.white,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onScaleStart: (details) {
            if (details.pointerCount == 1) {
              final canvasPoint = _screenToCanvas(details.localFocalPoint);
              _startStroke(canvasPoint);
            } else {
              _isDrawing = false;
              _live = null;
              _startMatrix = _transformationController.value.clone();
              _startFocalPoint = details.localFocalPoint;
            }
          },
          onScaleUpdate: (details) {
            if (details.pointerCount == 1 && _isDrawing) {
              final canvasPoint = _screenToCanvas(details.localFocalPoint);
              _extendStroke(canvasPoint);
            } else if (details.pointerCount > 1) {
              final translationDelta =
                  details.localFocalPoint - _startFocalPoint;

              final scaleMatrix = Matrix4.identity()
                ..translate(_startFocalPoint.dx, _startFocalPoint.dy)
                ..scale(details.scale)
                ..translate(-_startFocalPoint.dx, -_startFocalPoint.dy);

              final translationMatrix = Matrix4.identity()
                ..translate(translationDelta.dx, translationDelta.dy);

              setState(() {
                _transformationController.value =
                    translationMatrix * scaleMatrix * _startMatrix;
              });
            }
          },
          onScaleEnd: (_) {
            if (_isDrawing) {
              _endStroke();
            }
          },
          child: AnimatedBuilder(
            animation: _transformationController,
            builder: (context, child) {
              return Transform(
                transform: _transformationController.value,
                child: child,
              );
            },
            child: CustomPaint(
              painter: SketchPainter(strokes: _strokes, liveStroke: _live),
              size: Size.infinite,
            ),
          ),
        ),
      ),
    );
  }
}

/// Renders a small static preview of a sketch.
class SketchThumbnail extends StatelessWidget {
  final List<DrawStroke> strokes;
  const SketchThumbnail({super.key, required this.strokes});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: SketchPainter(strokes: strokes));
  }
}
