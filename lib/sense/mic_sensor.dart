import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:record/record.dart';

import '../sim/stimuli.dart';
import '../sim/util.dart';

/// 麥克風 → 音量、突然的大聲、持續的人聲。聲音只在記憶體裡算完就丟，不錄檔、不上傳。
class MicSensor {
  MicSensor(this.stim);

  final Stimuli stim;
  final AudioRecorder _rec = AudioRecorder();
  StreamSubscription<Uint8List>? _sub;
  double _floorDb = -50;
  double _lastDb = -90;
  bool running = false;

  Future<bool> start() async {
    try {
      if (!await _rec.hasPermission()) {
        petLog('mic permission denied');
        return false;
      }
      final stream = await _rec.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ));
      _sub = stream.listen(_onData, onError: (Object e) => petLog('mic error $e'));
      running = true;
      stim.micOn = true;
      petLog('mic on');
      return true;
    } catch (e) {
      petLog('mic unavailable: $e');
      return false;
    }
  }

  void _onData(Uint8List bytes) {
    final n = bytes.length ~/ 2;
    if (n == 0) return;
    final bd = ByteData.sublistView(bytes);
    var sum = 0.0;
    var zc = 0;
    var prev = 0;
    for (var i = 0; i < n; i++) {
      final v = bd.getInt16(i * 2, Endian.little);
      final dv = v.toDouble();
      sum += dv * dv;
      if ((v >= 0) != (prev >= 0)) zc++;
      prev = v;
    }
    final rms = math.sqrt(sum / n) / 32768;
    final db = 20 * math.log(rms + 1e-9) / math.ln10;
    final chunkSec = n / 16000;
    // 環境底噪：往下很快跟、往上很慢跟
    _floorDb = db < _floorDb ? lerpD(_floorDb, db, 0.3) : _floorDb + chunkSec * 0.6;
    final rel = db - _floorDb;
    stim.soundLevel = clampD(rel / 40, 0, 1);
    // 只有拍手、東西掉落這種「比環境大很多、又很突然」的聲音才算巨響；一般說話不會嚇到牠〔估〕
    if (db - _lastDb > 20 && rel > 38) {
      stim.loudOnset = true;
      petLog('sound onset ${rel.toStringAsFixed(0)}dB');
    }
    final zcr = zc / n;
    final voiceLike = rel > 10 && zcr > 0.02 && zcr < 0.25;
    stim.voiceSeconds = voiceLike ? stim.voiceSeconds + chunkSec : math.max(0.0, stim.voiceSeconds - chunkSec * 2);
    _lastDb = db;
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    if (running) {
      try {
        await _rec.stop();
      } catch (_) {}
    }
    running = false;
    stim.micOn = false;
  }

  void dispose() {
    _rec.dispose();
  }
}
