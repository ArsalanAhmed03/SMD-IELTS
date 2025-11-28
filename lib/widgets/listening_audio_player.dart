import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../core/supabase_client.dart';

class ListeningAudioPlayer extends StatefulWidget {
  final String audioPath; // relative path or full URL
  final String bucket;

  // Show speed dropdown (0.75x, 1x, 1.25x, 1.5x)
  final bool showSpeedControl;

  // Enforce a total listening time budget
  // If true and totalAllowedTime is null, we use 2 × audio duration
  final bool enforcePlayLimit;
  final Duration? totalAllowedTime;

  const ListeningAudioPlayer({
    super.key,
    required this.audioPath,
    this.bucket = 'listening-audio',
    this.showSpeedControl = false,
    this.enforcePlayLimit = false,
    this.totalAllowedTime,
  });

  @override
  State<ListeningAudioPlayer> createState() => _ListeningAudioPlayerState();
}

class _ListeningAudioPlayerState extends State<ListeningAudioPlayer> {
  late final AudioPlayer _player;
  bool _loading = true;

  Duration _duration = Duration.zero;

  // total wall-clock listening time while actually playing
  Duration _playedAccumulated = Duration.zero;
  Duration? _maxPlayTime;

  bool _isPlaying = false;
  bool _limitReached = false;

  double _speed = 1.0;
  Timer? _budgetTimer;
  DateTime? _lastTick;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();

    // Track play / pause to start/stop budget timer
    _player.playerStateStream.listen((state) {
      final playing = state.playing;
      if (playing && !_isPlaying) {
        _isPlaying = true;
        _startBudgetTracking();
      } else if (!playing && _isPlaying) {
        _isPlaying = false;
        _stopBudgetTracking();
      }
    });

    // Track duration so we can set 2× budget
    _player.durationStream.listen((d) {
      if (d == null) return;
      setState(() {
        _duration = d;
        if (widget.enforcePlayLimit &&
            _maxPlayTime == null &&
            d > Duration.zero) {
          _maxPlayTime = widget.totalAllowedTime ?? d * 2;
        }
      });
    });

    _init();
  }

  Future<void> _init() async {
    String url = widget.audioPath;
    if (!url.startsWith('http')) {
      // original Supabase logic; do not change
      url = Supa.client.storage.from(widget.bucket).getPublicUrl(widget.audioPath);
    }
    try {
      await _player.setUrl(url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Audio unavailable: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _stopBudgetTracking();
    _player.dispose();
    super.dispose();
  }

  // -------- budget tracking (for exam) --------

  void _startBudgetTracking() {
    if (!widget.enforcePlayLimit) return;
    _lastTick = DateTime.now();
    _budgetTimer ??= Timer.periodic(const Duration(milliseconds: 250), (_) {
      _updateAccumulatedBudget();
    });
  }

  void _stopBudgetTracking() {
    if (widget.enforcePlayLimit) {
      _updateAccumulatedBudget();
    }
    _budgetTimer?.cancel();
    _budgetTimer = null;
    _lastTick = null;
  }

  void _updateAccumulatedBudget() {
    if (!widget.enforcePlayLimit) return;
    if (!_isPlaying || _lastTick == null) return;

    final now = DateTime.now();
    final delta = now.difference(_lastTick!);
    _lastTick = now;
    _playedAccumulated += delta;

    final max = _maxPlayTime;
    if (max != null && _playedAccumulated >= max) {
      _player.pause();
      _stopBudgetTracking();
      if (!_limitReached) {
        _limitReached = true;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You have reached the maximum listening time for this recording.'),
            ),
          );
        }
      }
    }
  }

  // -------- controls --------

  Future<void> _togglePlayPause() async {
    if (_limitReached) return;

    final state = await _player.playerStateStream.first;
    final playing = state.playing;

    if (playing) {
      await _player.pause();
      return;
    }

    // Not playing -> start or resume
    if (widget.enforcePlayLimit) {
      final max = _maxPlayTime;
      if (max != null && _playedAccumulated >= max) {
        _limitReached = true;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You have already used your listening allowance for this recording.'),
            ),
          );
        }
        return;
      }
    }

    try {
      await _player.setSpeed(_speed);
    } catch (e) {
      // just_audio usually handles this, but we ignore any errors here
      debugPrint('setSpeed error (ignored): $e');
    }

    await _player.play();
  }

  Future<void> _seekTo(double value) async {
    final dur = _player.duration;
    if (dur == null || dur == Duration.zero) return;
    final target = dur * value;
    await _player.seek(target);
  }

  Future<void> _changeSpeed(double newSpeed) async {
    setState(() => _speed = newSpeed);
    try {
      await _player.setSpeed(newSpeed);
    } catch (e) {
      debugPrint('setSpeed failed (ignored): $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return Container(
      decoration: BoxDecoration(
        color: Colors.black12,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          Row(
            children: [
              StreamBuilder<PlayerState>(
                stream: _player.playerStateStream,
                builder: (context, snapshot) {
                  final playing = snapshot.data?.playing ?? false;
                  return IconButton(
                    icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                    onPressed: _limitReached ? null : _togglePlayPause,
                  );
                },
              ),
              Expanded(
                child: StreamBuilder<Duration>(
                  stream: _player.positionStream,
                  builder: (context, snapshot) {
                    final pos = snapshot.data ?? Duration.zero;
                    final dur = _player.duration ?? Duration.zero;
                    final v = dur.inMilliseconds == 0
                        ? 0.0
                        : pos.inMilliseconds / dur.inMilliseconds;
                    return Slider(
                      value: v.clamp(0.0, 1.0),
                      onChanged: (nv) => _seekTo(nv),
                    );
                  },
                ),
              ),
            ],
          ),
          if (widget.showSpeedControl)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Text('Speed:'),
                const SizedBox(width: 8),
                DropdownButton<double>(
                  value: _speed,
                  onChanged: (v) {
                    if (v != null) {
                      _changeSpeed(v);
                    }
                  },
                  items: const [
                    DropdownMenuItem(value: 0.75, child: Text('0.75x')),
                    DropdownMenuItem(value: 1.0, child: Text('1.0x')),
                    DropdownMenuItem(value: 1.25, child: Text('1.25x')),
                    DropdownMenuItem(value: 1.5, child: Text('1.5x')),
                  ],
                ),
              ],
            ),
        ],
      ),
    );
  }
}
