import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class OffScreenRenderer {
  OffScreenRenderer(this._context, {Size? logicalSize, Size? imageSize}) {
    final sw = Stopwatch()..start();
    _view = View.of(_context);
    _logicalSize = logicalSize ?? _view.physicalSize / _view.devicePixelRatio;
    _imageSize = imageSize ?? _view.physicalSize;

    assert(
      _logicalSize.aspectRatio == _imageSize.aspectRatio,
      'The logical size and the image size must have the same aspect ratio.',
    );

    _renderView = RenderView(
      child: RenderPositionedBox(
        child: _repaintBoundary,
      ),
      configuration: ViewConfiguration(
        logicalConstraints: BoxConstraints.tight(_logicalSize),
      ),
      view: _view,
    );

    _pipelineOwner.rootNode = _renderView;
    _renderView.prepareInitialFrame();

    sw.stop();
    print('OffScreenRenderer(): Elapsed time: ${sw.elapsedMilliseconds}ms');
  }

  final BuildContext _context;
  late final ui.FlutterView _view;
  late final Size _logicalSize;
  late final Size _imageSize;

  final RenderRepaintBoundary _repaintBoundary = RenderRepaintBoundary();
  late final RenderView _renderView;
  final PipelineOwner _pipelineOwner = PipelineOwner();
  final BuildOwner _buildOwner = BuildOwner(focusManager: FocusManager());

  RenderObjectToWidgetElement<RenderBox>? _rootElement;

  Future<Uint8List?> renderWidget(Widget widget) async {
    final sw = Stopwatch()..start();
    _rootElement = RenderObjectToWidgetAdapter(
      container: _repaintBoundary,
      child: Directionality(textDirection: TextDirection.ltr, child: widget),
    ).attachToRenderTree(_buildOwner, _rootElement);

    _buildOwner.buildScope(_rootElement!);

    await Future<void>.delayed(Duration.zero);

    _buildOwner
      ..buildScope(_rootElement!)
      ..finalizeTree();

    _pipelineOwner
      ..flushLayout()
      ..flushCompositingBits()
      ..flushPaint();

    final image = await _repaintBoundary.toImage(
      pixelRatio: _imageSize.width / _logicalSize.width,
    );

    final byteData = await image.toByteData();
    sw.stop();
    print('renderWidget(): Elapsed time: ${sw.elapsedMilliseconds}ms');
    return byteData?.buffer.asUint8List();
  }
}
