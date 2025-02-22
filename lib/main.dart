import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:ndisend/ndi_ffi_bindings.dart';

import 'package:ndisend/ndisend.dart';
import 'package:ndisend/off_screen_renderer.dart';

void main() {
  runApp(const Main());
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
  late ffi.Pointer<ffi.Uint8> pData;

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

  late NDISend ndiSend;
  late NDISend ndiSend2;

  late NDIFrame offScreenFrame;
  late ffi.Pointer<ffi.Uint8> offScreenData;

  OffScreenRenderer? offScreenRenderer;

  @override
  void initState() {
    super.initState();
    ndiSend = NDISend('Flutter NDI SEND');

    // allocate space for the pixel buffer
    pData = malloc.call<ffi.Uint8>(maxLen);
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
            milliseconds: 1000 ~/ (frame.frameRateN / frame.frameRateD),
          ), (t) {
        update();
      });
    });

    ndiSend2 = NDISend('Flutter NDI SEND OffScreen');

    offScreenData = malloc.call<ffi.Uint8>(maxLen);

    offScreenFrame = NDIFrame(
      width: 1920,
      height: 1080,
      fourCC: NDIlib_FourCC_video_type_e.NDIlib_FourCC_type_RGBA,
      pDataA: offScreenData.address,
      format: NDIlib_frame_format_type_e.NDIlib_frame_format_type_progressive,
      bytesPerPixel: 4,
      frameRateN: 30000,
    );

    ndiSend2.sendFrames(offScreenFrame);

    WidgetsFlutterBinding.ensureInitialized().addPostFrameCallback((_) {
      offScreenRenderer = OffScreenRenderer(
        context,
        imageSize: const Size(1920, 1080),
        logicalSize: const Size(1920, 1080),
      );
    });
  }

  @override
  void dispose() {
    super.dispose();
    timer?.cancel();
    ndiSend.stopSendFrames();
    frame.destroy();

    ndiSend2.stopSendFrames();
    offScreenFrame.destroy();
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
            milliseconds: 1000 ~/ (frame.frameRateN / frame.frameRateD),
          ), (t) {
        update();
      });
    });

    ndiSend2
      ..stopSendFrames()
      ..sendFrames(offScreenFrame);
  }

  void update() {
    capture().then((_) {
      ndiSend.updateFrame(frame);
    });
  }

  Offset pos = Offset.zero;

  int i = 0;

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
        floatingActionButton: FloatingActionButton(
          onPressed: () async {
            i++;
            final sw = Stopwatch()..start();
            final buf = await offScreenRenderer?.renderWidget(
              Container(
                width: 1920,
                height: 1080,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      HSVColor.fromAHSV(1, (i % 360).toDouble(), 1, 1)
                          .toColor(),
                      HSVColor.fromAHSV(1, ((i + 180) % 360).toDouble(), 1, 1)
                          .toColor(),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Center(
                  child: Text(
                    'OffScreen Widget',
                    style: TextTheme.of(context)
                        .displayLarge
                        ?.copyWith(color: Colors.white),
                  ),
                ),
              ),
            );

            if (buf == null) {
              print('Failed to create image from widget');
              return;
            }

            offScreenData.asTypedList(maxLen).setRange(0, buf.length, buf);

            ndiSend2.updateFrame(offScreenFrame);
            sw.stop();
            print(
              'Took ${sw.elapsedMilliseconds}ms to send image from widget',
            );
          },
          child: const Icon(Icons.camera),
        ),
      ),
    );
  }
}
