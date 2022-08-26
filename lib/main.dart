import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:ndisend/ndi_ffi_bindigs.dart';
import 'dart:ui' as ui;

import 'package:ndisend/ndisend.dart';

late NDISend ndiSend;

void main() {
  ndiSend = NDISend();
  runApp(const Main());
  ndiSend.stopSendFrames();
}

class Main extends StatefulWidget {
  const Main({Key? key}) : super(key: key);

  @override
  State<Main> createState() => _MainState();
}

class _MainState extends State<Main> {
  final bKey = GlobalKey();
  ui.Image? img;
  late NDIFrame frame;
  late Pointer<Uint8> pData;
  int maxLen = 1920 * 1080 * 4;
  Timer? timer;

  Future<void> capture() async {
    final boundary = bKey.currentContext?.findRenderObject() as RenderRepaintBoundary;
    img = await boundary.toImage();
    final bytes = await img!.toByteData(format: ui.ImageByteFormat.rawRgba);
    pData.asTypedList(maxLen).setRange(
          0,
          bytes!.lengthInBytes < maxLen ? bytes.lengthInBytes : maxLen,
          bytes.buffer.asUint8List(),
        );
  }

  @override
  void initState() {
    super.initState();
    pData = calloc.call<Uint8>(maxLen);
    frame = NDIFrame(
      width: 1920,
      height: 1080,
      fourCC: NDIlib_FourCC_video_type_e.NDIlib_FourCC_type_RGBA,
      pDataA: pData.address,
      format: NDIlib_frame_format_type_e.NDIlib_frame_format_type_progressive,
      bytesPerPixel: 4,
      frameRateN: 30000,
      frameRateD: 1000,
    );
    ndiSend.sendFrames(frame);
    Future.delayed(const Duration(milliseconds: 10), () {
      timer = Timer.periodic(
          Duration(
            milliseconds: 500 ~/ (frame.frameRateN / frame.frameRateD),
          ), (t) {
        update();
      });
    });
  }

  @override
  void dispose() {
    super.dispose();
    timer?.cancel();
    ndiSend.stopSendFrames();
    calloc.free(pData);
  }

  @override
  void reassemble() {
    super.reassemble();
    timer?.cancel();
    ndiSend.stopSendFrames();
    ndiSend.sendFrames(frame);
    Future.delayed(const Duration(milliseconds: 10), () {
      timer = Timer.periodic(
          Duration(
            milliseconds: 500 ~/ (frame.frameRateN / frame.frameRateD),
          ), (t) {
        update();
      });
    });
  }

  void update() {
    capture().then((_) {
      ndiSend.updateFrame(frame);
    });
  }

  Offset pos = Offset.zero;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: LayoutBuilder(builder: (context, constraints) {
          return SizedBox(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            child: FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: 1920,
                height: 1080,
                child: Stack(
                  children: [
                    Container(
                      width: 1920,
                      height: 1080,
                      color: Colors.black,
                    ),
                    RepaintBoundary(
                      key: bKey,
                      child: Container(
                        width: 1920,
                        height: 1080,
                        color: Colors.transparent,
                        child: Stack(children: [
                          Align(
                            alignment: Alignment.topLeft,
                            child: Image.network("http://www.w3.org/Graphics/PNG/text2.png"),
                          ),
                          Positioned(
                            top: pos.dy,
                            left: pos.dx,
                            child: Listener(
                              onPointerMove: (event) {
                                pos += event.localDelta;
                                setState(() {});
                              },
                              child: const Card(
                                elevation: 6,
                                child: Padding(
                                  padding: EdgeInsets.all(8.0),
                                  child: Text("Hello World!"),
                                ),
                              ),
                            ),
                          ),
                        ]),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
