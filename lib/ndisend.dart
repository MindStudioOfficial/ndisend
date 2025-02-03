import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'package:ffi/ffi.dart' as ffi;
import 'package:ndisend/ndi_ffi_bindings.dart';

LibNDIFFI _ndi =
    LibNDIFFI(DynamicLibrary.open('bin/Processing.NDI.Lib.x64.dll'));

class NDISend {
  NDISend() {
    _ndi.NDIlib_v5_load();
    if (!_ndi.NDIlib_initialize()) {
      throw Exception('Could not initialize NDI');
    }
  }

  ReceivePort? _sendReceivePort;
  Isolate? _sendIsolate;
  SendPort? _sendSendPort;

  NDIlib_send_instance_t? _pSendInstance;

  Pointer? _pSendName;

  Future<void> sendFrames(NDIFrame frame) async {
    final completer = Completer<void>();
    _sendReceivePort = ReceivePort();
    _sendReceivePort!.listen(
      (data) {
        if (data is SendPort) {
          _sendSendPort = data;
        }
        if (data is Map<String, int>) {
          if (data['pSendInstance'] != null && data['pSendName'] != null) {
            _pSendInstance = Pointer.fromAddress(data['pSendInstance']!);
            _pSendName = Pointer.fromAddress(data['pSendName']!);
          }
        }
      },
      onDone: () {
        print('done sending');
        completer.complete();
      },
    );

    _sendIsolate = await Isolate.spawn(
      _sendFrames,
      SendObject(frame: frame, sendPort: _sendReceivePort!.sendPort),
    );
    return completer.future;
  }

  void stopSendFrames() {
    print('stopping');
    if (_sendIsolate != null && _sendReceivePort != null) {
      _sendReceivePort!.close();
      _sendIsolate!.kill(priority: Isolate.immediate);
      _sendIsolate = null;
      _sendReceivePort = null;
    }
    if (_pSendInstance != null) {
      _ndi.NDIlib_send_destroy(_pSendInstance!);
      print('destroying send instance');
    }

    if (_pSendName != null) ffi.calloc.free(_pSendName!);
    print('stopped');
  }

  void updateFrame(NDIFrame frame) {
    if (_sendSendPort != null) {
      _sendSendPort!.send(frame);
    }
  }

  static Future<void> _sendFrames(SendObject object) async {
    final receivePort = ReceivePort();
    object.sendPort.send(receivePort.sendPort);

    receivePort.listen((data) {
      if (data is NDIFrame) {
        //print("gotFrame");
        if (!object.frame.destroyed &&
            data.pFrame.address != object.frame.pFrame.address) {
          object.frame.destroy();
          object.frame = data;
        }
      }
    });

    final pCreateSettings = ffi.calloc.call<NDIlib_send_create_t>();

    final pNDIName = 'NDISend by MindStudio'.toNativeUtf8().cast<Char>();
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

    while (true) {
      _ndi.NDIlib_send_send_video_async_v2(pSend, object.frame.pFrame);
      await Future<void>.delayed(
        Duration(
          milliseconds:
              1000 ~/ (object.frame.frameRateN / object.frame.frameRateD),
        ),
      );
    }
  }
}

class SendObject {
  SendObject({required this.frame, required this.sendPort});

  NDIFrame frame;
  SendPort sendPort;
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
    ffi.calloc.free(Pointer.fromAddress(pDataA));
    ffi.calloc.free(Pointer.fromAddress(_pFrameA));
  }
}
