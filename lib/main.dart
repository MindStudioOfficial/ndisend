import 'dart:async';
import 'dart:ffi';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:ndisend/ndi_ffi_bindings.dart';

import 'package:ndisend/ndisend.dart';

late NDISend ndiSend;

void main() {
  ndiSend = NDISend();
  runApp(const Main());
  ndiSend.stopSendFrames();
}

class Main extends StatefulWidget {
  const Main({super.key});

  @override
  State<Main> createState() => _MainState();
}

class _MainState extends State<Main> {
  // the key used by the Repaint Boundary
  final bKey = GlobalKey();

  // the Image overridden by the capture function
  ui.Image? img;

  // the frame class creating the struct for sending
  late NDIFrame frame;

  // where the pixels are stored
  late Pointer<Uint8> pData;

  // the size of the pixel buffer in bytes
  int maxLen = 1920 * 1080 * 4;

  // used to periodically call the capture function
  Timer? timer;

  Future<void> capture() async {
    // get the RepaintBoundary Widget
    final boundary =
        bKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    // get the ui.Image of that widget
    img = await boundary?.toImage();
    // get the pixels as RGBA bytes
    final bytes = await img!.toByteData();
    // view the pointer as a Uint8List and copy the image bytes to that list effectively copying to the pointer array
    pData.asTypedList(maxLen).setRange(
          0,
          bytes!.lengthInBytes < maxLen ? bytes.lengthInBytes : maxLen,
          bytes.buffer.asUint8List(),
        );
  }

  @override
  void initState() {
    super.initState();
    // allocate space for the pixel buffer
    pData = calloc.call<Uint8>(maxLen);
    // create a new frame internally creating the NDIlib struct
    frame = NDIFrame(
      width: 1920,
      height: 1080,
      fourCC: NDIlib_FourCC_video_type_e.NDIlib_FourCC_type_RGBA,
      pDataA: pData.address,
      format: NDIlib_frame_format_type_e.NDIlib_frame_format_type_progressive,
      bytesPerPixel: 4,
      frameRateN: 30000,
    );

    // start the sending process
    ndiSend.sendFrames(frame);
    // wait for a bit and then update the frame that needs to be sended
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
    frame.destroy();
    //calloc.free(pData);
  }

  // restart the sending process on hot reload
  @override
  void reassemble() {
    super.reassemble();
    timer?.cancel();
    ndiSend
      ..stopSendFrames()
      ..sendFrames(frame);
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
        body: LayoutBuilder(
          builder: (context, constraints) {
            return SizedBox(
              width: constraints.maxWidth,
              height: constraints.maxHeight,
              child: FittedBox(
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
                      // The widget that gets captured
                      RepaintBoundary(
                        key: bKey,
                        child: Container(
                          width: 1920,
                          height: 1080,
                          color: Colors.transparent,
                          child: Stack(
                            children: [
                              Align(
                                alignment: Alignment.topLeft,
                                child: Image.network(
                                  'http://www.w3.org/Graphics/PNG/text2.png',
                                ),
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
                                      padding: EdgeInsets.all(8),
                                      child: Text('Hello World!'),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
