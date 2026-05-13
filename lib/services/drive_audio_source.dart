// ignore_for_file: experimental_member_use

import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';

class DriveAudioSource extends StreamAudioSource {
  final String fileId;
  final String token;

  DriveAudioSource(this.fileId, this.token);

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final client = http.Client();
    final uri = Uri.parse('https://www.googleapis.com/drive/v3/files/$fileId?alt=media');

    final headers = {
      'Authorization': 'Bearer $token',
      'User-Agent': 'InfameApp/1.0',
    };

    if (start != null || end != null) {
      headers['Range'] = 'bytes=${start ?? 0}-${end ?? ''}';
    }

    final request = http.Request('GET', uri)
      ..headers.addAll(headers)
      ..followRedirects = false;

    final response = await client.send(request);

    if (response.isRedirect && response.headers.containsKey('location')) {
      final redirectUri = Uri.parse(response.headers['location']!);
      final secondRequest = http.Request('GET', redirectUri);

      if (start != null || end != null) {
        secondRequest.headers['Range'] = 'bytes=${start ?? 0}-${end ?? ''}';
      }

      final finalResponse = await client.send(secondRequest);
      return _handleResponse(finalResponse, start);
    }

    return _handleResponse(response, start);
  }

  Future<StreamAudioResponse> _handleResponse(http.StreamedResponse res, int? start) async {
    if (res.statusCode != 200 && res.statusCode != 206) {
      final body = await res.stream.bytesToString();
      throw Exception('Drive API Error: ${res.statusCode} - $body');
    }

    int? totalSize;
    final contentRange = res.headers['content-range'];

    if (contentRange != null) {
      final match = RegExp(r'bytes (\d+)-\d+/(\d+)').firstMatch(contentRange);
      if (match != null) totalSize = int.parse(match.group(2)!);
    }

    totalSize ??= res.contentLength;

    // Important: when Google Drive ignores Range and returns 200, the stream is
    // the whole file from byte 0. Returning offset=start in that case makes
    // seeking/skip-forward behave like the song restarted or jumped wrong.
    final responseOffset = res.statusCode == 206 ? (start ?? 0) : 0;

    return StreamAudioResponse(
      sourceLength: totalSize,
      contentLength: res.contentLength,
      offset: responseOffset,
      stream: res.stream,
      contentType: res.headers['content-type'] ?? 'audio/mpeg',
    );
  }
}
