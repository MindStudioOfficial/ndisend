import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'package:ffi/ffi.dart' as ffi;
import 'package:ndisend/ndi_ffi_bindings.dart';

LibNDIFFI _ndi =
    LibNDIFFI(DynamicLibrary.open('bin/Processing.NDI.Lib.x64.dll'));

class NDISend {
  NDISend(this.name) {
    _ndi.NDIlib_v5_load();
    if (!_ndi.NDIlib_initialize()) {
      throw Exception('Could not initialize NDI');
    }
  }

  final String name;

  ReceivePort? _sendReceivePort;
  Isolate? _sendIsolate;
  SendPort? _sendSendPort;

  NDIlib_send_instance_t? _pSend;

  Future<void> sendFrames(NDIFrame frame) async {
    final completer = Completer<void>();
    _sendReceivePort = ReceivePort();

    _sendIsolate = await Isolate.spawn(
      _sendFrames,
      SendObject(
        frame: frame,
        sendPort: _sendReceivePort!.sendPort,
        sendName: name,
      ),
      paused: true,
      debugName: 'NDISend Isolate $name',
    );

    _sendIsolate?.addOnExitListener(
      _sendReceivePort!.sendPort,
      response: 'onExit',
    );

    _sendIsolate?.addErrorListener(_sendReceivePort!.sendPort);

    _sendReceivePort!.listen(
      (data) {
        switch (data) {
          case 'onExit':
            _killSendIsolate();
          case 'error':
            print('error: $data');
          case final SendPort sendPort:
            _sendSendPort = sendPort;
          case {
              'pSendInstance': final int aSendInstance,
              'pSendName': _,
            }:
            _pSend = Pointer.fromAddress(aSendInstance).cast();
        }
      },
      onDone: () {
        print('done sending');
        completer.complete();
      },
    );

    _sendIsolate?.resume(_sendIsolate!.pauseCapability!);

    print('started sending');

    return completer.future;
  }

  Future<void> stopSendFrames() async {
    print('stopping');

    _sendSendPort?.send('end');

    if (_sendIsolate != null) {
      var counter = 0;

      await Future.doWhile(() async {
        print('waiting for isolate to exit');

        if (counter++ > 20) {
          _killSendIsolate();
          print('killed unresponsive isolate');
          return false;
        }

        return Future<bool>.delayed(const Duration(milliseconds: 250), () {
          return _sendIsolate != null;
        });
      });
    } else {
      _killSendIsolate();
    }
  }

  void _killSendIsolate() {
    _sendReceivePort?.close();
    _sendIsolate?.kill(priority: Isolate.immediate);
    _sendIsolate = null;
    _sendReceivePort = null;
    _sendSendPort = null;

    if (_pSend != null) _ndi.NDIlib_send_destroy(_pSend!);
  }

  void updateFrame(NDIFrame frame) {
    if (_sendSendPort != null) {
      _sendSendPort!.send(frame);
    }
  }

  static Future<void> _sendFrames(SendObject object) async {
    var end = false;

    final receivePort = ReceivePort();
    object.sendPort.send(receivePort.sendPort);

    receivePort.listen((data) {
      switch (data) {
        case final NDIFrame frame:
          if (!object.frame.destroyed &&
              frame.pFrame.address != object.frame.pFrame.address) {
            object.frame.destroy();
            object.frame = frame;
          }
        case 'end':
          end = true;
      }
    });

    final pCreateSettings = ffi.malloc.call<NDIlib_send_create_t>();

    final pNDIName = object.sendName.toNativeUtf8().cast<Char>();
    pCreateSettings.ref.p_ndi_name = pNDIName;
    pCreateSettings.ref.clock_audio = false;
    pCreateSettings.ref.clock_video = false;

    final pSend = _ndi.NDIlib_send_create(pCreateSettings);

    if (pSend == nullptr) {
      print('error creating sender');
    }

    object.sendPort.send(<String, int>{
      'pSendInstance': pSend.address,
      'pSendName': pNDIName.address,
    });

    while (!end) {
      _ndi.NDIlib_send_send_video_async_v2(pSend, object.frame.pFrame);
      await Future<void>.delayed(
        Duration(
          milliseconds:
              1000 ~/ (object.frame.frameRateN / object.frame.frameRateD),
        ),
      );
    }

    _ndi.NDIlib_send_destroy(pSend);

    ffi.malloc.free(pCreateSettings);
    ffi.malloc.free(pNDIName);

    Isolate.exit();
  }
}

class SendObject {
  SendObject({
    required this.frame,
    required this.sendPort,
    required this.sendName,
  });

  NDIFrame frame;
  SendPort sendPort;
  final String sendName;
}

class NDIFrame {
  NDIFrame({
    required this.width,
    required this.height,
    required this.fourCC,
    required this.pDataA,
    required this.format,
    required this.bytesPerPixel,
    this.timecode = 0,
    this.frameRateN = 25000,
    this.frameRateD = 1000,
  }) {
    // create the NDIlib struct
    final pFrame = ffi.calloc.call<NDIlib_video_frame_v2_t>();
    pFrame.ref.FourCCAsInt = fourCC.value;
    pFrame.ref.xres = width;
    pFrame.ref.yres = height;
    pFrame.ref.frame_rate_D = frameRateD;
    pFrame.ref.frame_rate_N = frameRateN;
    pFrame.ref.p_data = Pointer.fromAddress(pDataA).cast<Uint8>();
    pFrame.ref.timecode = timecode;
    pFrame.ref.picture_aspect_ratio = width / height;
    pFrame.ref.frame_format_typeAsInt = format.value;

    _pFrameA = pFrame.address;
  }
  int width;
  int height;
  int timecode;
  int frameRateN;
  int frameRateD;
  int bytesPerPixel;
  int pDataA;
  NDIlib_FourCC_video_type_e fourCC;
  NDIlib_frame_format_type_e format;
  bool _destroyed = false;
  late int _pFrameA;

  Pointer<NDIlib_video_frame_v2_t> get pFrame => Pointer.fromAddress(_pFrameA);
  bool get destroyed => _destroyed;

  void destroy() {
    _destroyed = true;
    ffi.malloc.free(Pointer.fromAddress(pDataA));
    ffi.malloc.free(Pointer.fromAddress(_pFrameA));
  }
}
