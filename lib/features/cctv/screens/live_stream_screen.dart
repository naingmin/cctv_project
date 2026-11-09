import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/services/cctv_service.dart';

/// WHEP viewer backed by the authenticated MediaMTX stream endpoint.
class LiveStreamScreen extends ConsumerStatefulWidget {
  final String cctvId;

  const LiveStreamScreen({super.key, required this.cctvId});

  @override
  ConsumerState<LiveStreamScreen> createState() => _LiveStreamScreenState();
}

class _LiveStreamScreenState extends ConsumerState<LiveStreamScreen> {
  final RTCVideoRenderer _renderer = RTCVideoRenderer();
  RTCPeerConnection? _peerConnection;
  String? _sessionUrl;
  String? _error;
  bool _isConnecting = true;
  bool _rendererReady = false;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    if (mounted) {
      setState(() {
        _isConnecting = true;
        _error = null;
      });
    }

    try {
      await _closePeerConnection();
      if (!mounted) return;
      if (!_rendererReady) {
        await _renderer.initialize();
        if (!mounted) {
          await _renderer.dispose();
          return;
        }
        _rendererReady = true;
      }

      final endpoints =
          await ref.read(cctvServiceProvider).getStreamEndpoints(widget.cctvId);
      if (!mounted) return;
      final peerConnection = await createPeerConnection({
        'sdpSemantics': 'unified-plan',
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
        ],
      });
      if (!mounted) {
        await peerConnection.close();
        return;
      }
      _peerConnection = peerConnection;
      peerConnection.onConnectionState = (state) {
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          unawaited(
            _showConnectionError(
              'The WebRTC connection failed. Check MediaMTX network settings.',
            ),
          );
        }
      };
      peerConnection.onTrack = (event) {
        if (mounted && event.streams.isNotEmpty) {
          _renderer.srcObject = event.streams.first;
        }
      };

      await peerConnection.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
        init: RTCRtpTransceiverInit(
          direction: TransceiverDirection.RecvOnly,
        ),
      );
      await peerConnection.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
        init: RTCRtpTransceiverInit(
          direction: TransceiverDirection.RecvOnly,
        ),
      );

      final offer = await peerConnection.createOffer();
      await peerConnection.setLocalDescription(offer);
      await _waitForIceGathering(peerConnection);
      final localDescription = await peerConnection.getLocalDescription();
      if (localDescription?.sdp == null || localDescription!.sdp!.isEmpty) {
        throw StateError('The device did not produce a WebRTC offer.');
      }

      final response = await Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 20),
          responseType: ResponseType.plain,
          validateStatus: (status) =>
              status != null && status >= 200 && status < 300,
        ),
      ).post<String>(
        endpoints.whepUrl,
        data: localDescription.sdp,
        options: Options(
          contentType: 'application/sdp',
          headers: const {'Accept': 'application/sdp'},
        ),
      );
      final answer = response.data;
      if (answer == null || answer.trim().isEmpty) {
        throw StateError('MediaMTX returned an empty WebRTC answer.');
      }
      final location = response.headers.value('location');
      if (location != null) {
        _sessionUrl = Uri.parse(endpoints.whepUrl).resolve(location).toString();
      }
      if (!mounted) {
        await _closePeerConnection();
        return;
      }
      await peerConnection.setRemoteDescription(
        RTCSessionDescription(answer, 'answer'),
      );

      if (mounted) setState(() => _isConnecting = false);
    } on DioException catch (error) {
      await _showConnectionError(
        error.response == null
            ? 'Could not reach the live stream. Check the network and try again.'
            : 'MediaMTX rejected the stream request '
                '(HTTP ${error.response?.statusCode ?? 'unknown'}).',
      );
    } catch (error) {
      await _showConnectionError(error.toString());
    }
  }

  Future<void> _waitForIceGathering(RTCPeerConnection peerConnection) async {
    if (peerConnection.iceGatheringState ==
        RTCIceGatheringState.RTCIceGatheringStateComplete) {
      return;
    }
    final gathered = Completer<void>();
    peerConnection.onIceGatheringState = (state) {
      if (state == RTCIceGatheringState.RTCIceGatheringStateComplete &&
          !gathered.isCompleted) {
        gathered.complete();
      }
    };
    await gathered.future.timeout(const Duration(seconds: 15));
  }

  Future<void> _showConnectionError(String message) async {
    await _closePeerConnection();
    if (!mounted) return;
    setState(() {
      _isConnecting = false;
      _error = message;
    });
  }

  Future<void> _closePeerConnection() async {
    final sessionUrl = _sessionUrl;
    _sessionUrl = null;
    if (sessionUrl != null) {
      try {
        await Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 2),
            receiveTimeout: const Duration(seconds: 2),
          ),
        ).delete<void>(sessionUrl);
      } on DioException catch (error) {
        debugPrint('Could not close the MediaMTX session: ${error.message}');
      }
    }
    final peerConnection = _peerConnection;
    _peerConnection = null;
    _renderer.srcObject = null;
    await peerConnection?.close();
  }

  @override
  void dispose() {
    unawaited(_disposeResources());
    super.dispose();
  }

  Future<void> _disposeResources() async {
    await _closePeerConnection();
    if (_rendererReady) await _renderer.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Live View')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            widget.cctvId,
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: ColoredBox(
                color: Colors.black,
                child: _rendererReady
                    ? RTCVideoView(
                        _renderer,
                        objectFit:
                            RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                      )
                    : const Center(child: CircularProgressIndicator()),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_isConnecting)
            const Column(
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 12),
                Text('Connecting to camera...'),
              ],
            ),
          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.danger.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.danger.withOpacity(0.4)),
              ),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.danger),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: FilledButton.icon(
                onPressed: _isConnecting ? null : _connect,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
