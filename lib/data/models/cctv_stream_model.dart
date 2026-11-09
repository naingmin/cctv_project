/// Playback URLs returned by the authenticated CCTV stream endpoint.
class CctvStreamEndpoints {
  final String streamPath;
  final String whepUrl;
  final String hlsUrl;

  const CctvStreamEndpoints({
    required this.streamPath,
    required this.whepUrl,
    required this.hlsUrl,
  });

  factory CctvStreamEndpoints.fromJson(Map<String, dynamic> json) {
    return CctvStreamEndpoints(
      streamPath: json['stream_path'] as String,
      whepUrl: json['whep_url'] as String,
      hlsUrl: json['hls_url'] as String,
    );
  }
}
