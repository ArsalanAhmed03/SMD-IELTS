import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class SpeakingRecorder extends StatefulWidget {
  final ValueChanged<SpeakingRecordingResult> onRecorded;
  final String? prompt;

  const SpeakingRecorder({
    super.key,
    required this.onRecorded,
    this.prompt,
  });

  @override
  State<SpeakingRecorder> createState() => _SpeakingRecorderState();
}

class SpeakingRecordingResult {
  final String path;
  final int durationSeconds;

  const SpeakingRecordingResult({
    required this.path,
    required this.durationSeconds,
  });
}

class _SpeakingRecorderState extends State<SpeakingRecorder> {
  final AudioRecorder _record = AudioRecorder();
  bool _recording = false;
  Duration _elapsed = Duration.zero;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _record.dispose();
    super.dispose();
  }

  Future<String> _generateTempPath() async {
    final dir = await getTemporaryDirectory();
    final filename = "recording_${DateTime.now().millisecondsSinceEpoch}.m4a";
    return "${dir.path}/$filename";
  }

  Future<void> _start() async {
    if (_recording) return;

    final hasPerm = await _record.hasPermission();
    if (!hasPerm) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Microphone permission is required.')),
      );
      return;
    }

    final path = await _generateTempPath();

    await _record.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 16000,
      ),
      path: path, // REQUIRED on mobile
    );

    setState(() {
      _recording = true;
      _elapsed = Duration.zero;
    });

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _elapsed += const Duration(seconds: 1);
      });
    });
  }

  Future<void> _stop() async {
    if (!_recording) return;

    final path = await _record.stop();
    _timer?.cancel();
    _timer = null;

    setState(() {
      _recording = false;
    });

    if (path != null && path.isNotEmpty) {
      widget.onRecorded(
        SpeakingRecordingResult(
          path: path,
          durationSeconds: _elapsed.inSeconds == 0 ? 1 : _elapsed.inSeconds,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final minutes = _elapsed.inMinutes.toString().padLeft(2, '0');
    final seconds = (_elapsed.inSeconds % 60).toString().padLeft(2, '0');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.prompt != null) ...[
              Text(widget.prompt!, style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 8),
            ],
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _recording ? _stop : _start,
                  icon: Icon(_recording ? Icons.stop : Icons.mic),
                  label: Text(_recording ? 'Stop' : 'Record'),
                ),
                const SizedBox(width: 12),
                Text('${_recording ? "Recording..." : "Tap to record"}  $minutes:$seconds'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
