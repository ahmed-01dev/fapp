import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../services/wasel_service.dart';
import '../widgets/glass_ui.dart';

class CallScreen extends StatefulWidget {
  const CallScreen({
    super.key,
    required this.service,
    required this.callId,
    required this.conversationId,
    required this.otherUserId,
    required this.callType,
    required this.isCaller,
  });

  final WaselService service;
  final String callId;
  final String conversationId;
  final String otherUserId;
  final String callType;
  final bool isCaller;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  final Set<String> _seenSignals = {};
  final List<RTCIceCandidate> _pendingCandidates = [];
  StreamSubscription<List<Map<String, dynamic>>>? _signalSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _sessionSubscription;
  RTCPeerConnection? _peer;
  MediaStream? _localStream;
  Future<void> _signalQueue = Future<void>.value();
  bool _ready = false;
  bool _muted = false;
  bool _cameraOff = false;
  bool _ending = false;
  bool _allowPop = false;
  bool _remoteDescriptionSet = false;
  String _status = 'جارٍ تجهيز الاتصال...';
  String? _error;

  bool get _isVideo => widget.callType == 'video';

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      await _localRenderer.initialize();
      await _remoteRenderer.initialize();
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': _isVideo
            ? {
                'facingMode': 'user',
                'width': {'ideal': 720},
                'height': {'ideal': 1280},
                'frameRate': {'ideal': 24},
              }
            : false,
      });
      if (_isVideo) {
        _localRenderer.srcObject = _localStream;
      }

      final configuration = <String, dynamic>{
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
          {'urls': 'stun:stun1.l.google.com:19302'},
        ],
        'sdpSemantics': 'unified-plan',
      };
      _peer = await createPeerConnection(configuration);
      for (final track in _localStream!.getTracks()) {
        await _peer!.addTrack(track, _localStream!);
      }

      _peer!.onTrack = (event) {
        if (event.streams.isNotEmpty && mounted) {
          setState(() => _remoteRenderer.srcObject = event.streams.first);
        }
      };
      _peer!.onIceCandidate = (candidate) {
        if (candidate.candidate == null || _ending) return;
        unawaited(widget.service.sendCallSignal(
          callId: widget.callId,
          signalType: 'ice',
          payload: {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          },
        ).catchError((Object error) {
          if (mounted) setState(() => _error = 'تعذر إرسال بيانات الاتصال: $error');
        }));
      };
      _peer!.onConnectionState = (state) {
        if (!mounted) return;
        final value = state.toString().toLowerCase();
        if (value.contains('connected')) {
          setState(() => _status = 'متصل');
        } else if (value.contains('failed')) {
          setState(() => _status = 'الاتصال فشل؛ قد نحتاج خادم TURN لهذه الشبكة.');
        } else if (value.contains('disconnected')) {
          setState(() => _status = 'الاتصال انقطع، بنحاول نرجعه...');
        }
      };

      _signalSubscription = widget.service.watchCallSignals(widget.callId).listen(
        (rows) {
          for (final row in rows) {
            final id = row['id'].toString();
            if (!_seenSignals.add(id) || row['sender_id'] == widget.service.userId) continue;
            _signalQueue = _signalQueue.then((_) => _handleSignal(row)).catchError((Object error) {
              if (mounted) setState(() => _error = 'تعذر معالجة إشارة المكالمة: $error');
            });
          }
        },
        onError: (Object error) {
          if (mounted) setState(() => _error = 'انقطع اتصال الإشارات: $error');
        },
      );

      _sessionSubscription = widget.service.watchCallSession(widget.callId).listen((rows) {
        if (rows.isEmpty || !mounted) return;
        final status = rows.first['status']?.toString() ?? '';
        if (status == 'rejected') {
          setState(() => _status = 'المكالمة اترفضت');
        } else if (status == 'missed') {
          setState(() => _status = 'المكالمة فائتة');
        } else if (status == 'ended' && !_ending) {
          setState(() => _status = 'المكالمة انتهت');
        }
      });

      if (widget.isCaller) {
        final offer = await _peer!.createOffer({
          'offerToReceiveAudio': true,
          'offerToReceiveVideo': _isVideo,
        });
        await _peer!.setLocalDescription(offer);
        await widget.service.sendCallSignal(
          callId: widget.callId,
          signalType: 'offer',
          payload: {'sdp': offer.sdp, 'type': offer.type},
        );
        if (mounted) setState(() => _status = 'جارٍ الاتصال...');
      } else {
        if (mounted) setState(() => _status = 'تم قبول المكالمة، في انتظار الطرف الآخر...');
      }
      if (mounted) setState(() => _ready = true);
    } catch (error) {
      if (mounted) setState(() {
        _error = error.toString();
        _status = 'تعذر بدء المكالمة';
      });
    }
  }

  Future<void> _handleSignal(Map<String, dynamic> row) async {
    final peer = _peer;
    if (peer == null || _ending) return;
    final type = row['signal_type']?.toString();
    final payload = Map<String, dynamic>.from(row['payload'] as Map? ?? {});
    if (type == 'offer' && !widget.isCaller) {
      final description = RTCSessionDescription(
        payload['sdp']?.toString(),
        payload['type']?.toString(),
      );
      await peer.setRemoteDescription(description);
      _remoteDescriptionSet = true;
      await _flushCandidates();
      final answer = await peer.createAnswer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': _isVideo,
      });
      await peer.setLocalDescription(answer);
      await widget.service.sendCallSignal(
        callId: widget.callId,
        signalType: 'answer',
        payload: {'sdp': answer.sdp, 'type': answer.type},
      );
      if (mounted) setState(() => _status = 'جارٍ توصيل الصوت والصورة...');
    } else if (type == 'answer' && widget.isCaller) {
      await peer.setRemoteDescription(RTCSessionDescription(
        payload['sdp']?.toString(),
        payload['type']?.toString(),
      ));
      _remoteDescriptionSet = true;
      await _flushCandidates();
      if (mounted) setState(() => _status = 'جارٍ توصيل الصوت والصورة...');
    } else if (type == 'ice') {
      final candidate = RTCIceCandidate(
        payload['candidate']?.toString(),
        payload['sdpMid']?.toString(),
        (payload['sdpMLineIndex'] as num?)?.toInt(),
      );
      if (_remoteDescriptionSet) {
        await peer.addCandidate(candidate);
      } else {
        _pendingCandidates.add(candidate);
      }
    } else if (type == 'hangup' && mounted) {
      setState(() => _status = 'الطرف الآخر أنهى المكالمة');
    }
  }

  Future<void> _flushCandidates() async {
    final peer = _peer;
    if (peer == null) return;
    for (final candidate in _pendingCandidates) {
      await peer.addCandidate(candidate);
    }
    _pendingCandidates.clear();
  }

  Future<void> _toggleMicrophone() async {
    final tracks = _localStream?.getAudioTracks() ?? [];
    if (tracks.isEmpty) return;
    final next = !_muted;
    for (final track in tracks) {
      track.enabled = !next;
    }
    if (mounted) setState(() => _muted = next);
  }

  Future<void> _toggleCamera() async {
    final tracks = _localStream?.getVideoTracks() ?? [];
    if (tracks.isEmpty) return;
    final next = !_cameraOff;
    for (final track in tracks) {
      track.enabled = !next;
    }
    if (mounted) setState(() => _cameraOff = next);
  }

  Future<void> _switchCamera() async {
    final tracks = _localStream?.getVideoTracks() ?? [];
    if (tracks.isNotEmpty) await Helper.switchCamera(tracks.first);
  }

  Future<void> _endCall() async {
    if (_ending) return;
    _ending = true;
    try {
      await widget.service.sendCallSignal(
        callId: widget.callId,
        signalType: 'hangup',
        payload: const {},
      );
    } catch (_) {}
    try {
      await widget.service.updateCallStatus(widget.callId, 'ended');
    } catch (_) {}
    await _disposeMedia();
    if (mounted) {
      setState(() => _allowPop = true);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _disposeMedia() async {
    await _signalSubscription?.cancel();
    await _sessionSubscription?.cancel();
    try {
      await _peer?.close();
      await _peer?.dispose();
    } catch (_) {}
    for (final track in _localStream?.getTracks() ?? []) {
      await track.stop();
    }
    await _localStream?.dispose();
    _localRenderer.srcObject = null;
    _remoteRenderer.srcObject = null;
    await _localRenderer.dispose();
    await _remoteRenderer.dispose();
  }

  @override
  void dispose() {
    if (!_ending) unawaited(_disposeMedia());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_endCall());
      },
      child: Scaffold(
      backgroundColor: const Color(0xFF090A12),
      body: SafeArea(
        child: Stack(
          children: [
            if (_isVideo && _remoteRenderer.srcObject != null)
              Positioned.fill(child: RTCVideoView(_remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover))
            else
              Positioned.fill(
                child: GlassBackground(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 112,
                          height: 112,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(colors: [Color(0xFF7058C9), Color(0xFF32BBD0)]),
                            boxShadow: [BoxShadow(color: const Color(0xFF7058C9).withValues(alpha: .35), blurRadius: 35)],
                          ),
                          child: const Icon(Icons.person_rounded, color: Colors.white, size: 58),
                        ),
                        const SizedBox(height: 22),
                        Text(widget.isCaller ? 'جارٍ الاتصال...' : 'مكالمة واردة', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 8),
                        Text(_status, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
                      ],
                    ),
                  ),
                ),
              ),
            if (_isVideo && _localRenderer.srcObject != null)
              Positioned(
                top: 16,
                right: 16,
                width: 112,
                height: 164,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: RTCVideoView(_localRenderer, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
                ),
              ),
            Positioned(
              top: 8,
              left: 12,
              child: IconButton(
                onPressed: _endCall,
                icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 32),
              ),
            ),
            if (_error != null)
              Positioned(
                left: 18,
                right: 18,
                bottom: 120,
                child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFFF8794), fontSize: 12)),
              ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 24,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_ready ? _status : 'جارٍ تهيئة الميكروفون والكاميرا...', style: const TextStyle(color: Colors.white70)),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _controlButton(_muted ? Icons.mic_off_rounded : Icons.mic_rounded, _toggleMicrophone, active: _muted),
                      if (_isVideo) ...[
                        const SizedBox(width: 16),
                        _controlButton(_cameraOff ? Icons.videocam_off_rounded : Icons.videocam_rounded, _toggleCamera, active: _cameraOff),
                        const SizedBox(width: 16),
                        _controlButton(Icons.cameraswitch_rounded, _switchCamera),
                      ],
                      const SizedBox(width: 16),
                      _controlButton(Icons.call_end_rounded, _endCall, danger: true),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ));
  }

  Widget _controlButton(
    IconData icon,
    VoidCallback onPressed, {
    bool active = false,
    bool danger = false,
  }) {
    return Material(
      color: danger
          ? const Color(0xFFE34D65)
          : active
              ? Colors.white24
              : Colors.white.withValues(alpha: .12),
      shape: const CircleBorder(),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white, size: 23),
        padding: const EdgeInsets.all(17),
      ),
    );
  }
}
