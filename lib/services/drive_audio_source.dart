import 'dart:async';

// ignore_for_file: experimental_member_use

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';

class DriveAudioSource extends StreamAudioSource {
  final String fileId;
  final String token;
  final int? knownSourceLength;
  static Future<void> Function(String fileId)? onEndReached;

  DriveAudioSource(
    this.fileId,
    this.token, {
    this.knownSourceLength,
    super.tag,
  });

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final client = http.Client();
    final uri = Uri.parse(
        'https://www.googleapis.com/drive/v3/files/$fileId?alt=media');

    final headers = {
      'Authorization': 'Bearer $token',
      'User-Agent': 'InfameApp/1.0',
    };

    String? rangeHeader;
    if (start != null || end != null) {
      final safeStart = start ?? 0;
      if (end != null) {
        final endExclusive = end;
        final endInclusive =
            endExclusive <= safeStart ? safeStart : endExclusive - 1;
        rangeHeader = 'bytes=$safeStart-$endInclusive';
      } else {
        rangeHeader = 'bytes=$safeStart-';
      }
      headers['Range'] = rangeHeader;
    }
    debugPrint(
      'DriveAudioSource request file=$fileId start=$start end=$end range=$rangeHeader',
    );

    final request = http.Request('GET', uri)
      ..headers.addAll(headers)
      ..followRedirects = false;

    final response = await client.send(request);

    if (response.isRedirect && response.headers.containsKey('location')) {
      final redirectUri = Uri.parse(response.headers['location']!);
      final secondRequest = http.Request('GET', redirectUri);

      if (rangeHeader != null) {
        secondRequest.headers['Range'] = rangeHeader;
      }

      final finalResponse = await client.send(secondRequest);
      return _handleResponse(
        finalResponse,
        start,
        end,
        client,
      );
    }

    return _handleResponse(
      response,
      start,
      end,
      client,
    );
  }

  Future<StreamAudioResponse> _handleResponse(
    http.StreamedResponse res,
    int? start,
    int? end,
    http.Client client,
  ) async {
    final safeStart = start ?? 0;
    final requestedRange = start != null || end != null;

    if (res.statusCode == 416) {
      final body = await res.stream.bytesToString();
      final contentRange = res.headers['content-range'] ?? body;
      final match = RegExp(r'bytes \*/(\d+)').firstMatch(contentRange);
      final totalSize = match != null ? int.tryParse(match.group(1)!) : null;
      debugPrint(
        'DriveAudioSource response status=416 offset=$safeStart contentLength=0 sourceLength=$totalSize',
      );
      debugPrint(
        'DriveAudioSource 416 file=$fileId requestedStart=$safeStart requestedEnd=$end knownSourceLength=$totalSize',
      );
      client.close();
      throw Exception(
        'Drive API Error: 416 requested range not satisfiable '
        '(start=$safeStart end=$end sourceLength=$totalSize)',
      );
    }

    if (res.statusCode != 200 && res.statusCode != 206) {
      final body = await res.stream.bytesToString();
      client.close();
      throw Exception('Drive API Error: ${res.statusCode} - $body');
    }

    // Non-zero seeks must be partial responses; a full 200 body would replay
    // from byte 0 and desync UI position from heard audio.
    if (requestedRange && safeStart > 0 && res.statusCode != 206) {
      final body = await res.stream.bytesToString();
      debugPrint(
        'DriveAudioSource response status=${res.statusCode} offset=$safeStart contentLength=${res.contentLength} sourceLength=unknown',
      );
      client.close();
      throw Exception(
        'Drive ignored range for seek (status=${res.statusCode}, start=$safeStart). '
        'Body: $body',
      );
    }

    int? totalSize;
    int? contentLength;
    int responseOffset = safeStart;
    final contentRange = res.headers['content-range'];

    if (contentRange != null) {
      final match =
          RegExp(r'bytes\s+(\d+)-(\d+)/(\d+|\*)').firstMatch(contentRange);
      if (match != null) {
        final startHeader = int.tryParse(match.group(1)!);
        final endHeader = int.tryParse(match.group(2)!);
        final totalHeader = match.group(3);
        if (startHeader != null) responseOffset = startHeader;
        if (startHeader != null &&
            endHeader != null &&
            endHeader >= startHeader) {
          contentLength = (endHeader - startHeader) + 1;
        }
        if (totalHeader != null && totalHeader != '*') {
          totalSize = int.tryParse(totalHeader);
        }
      }
    }

    totalSize ??= knownSourceLength;
    totalSize ??= res.contentLength;
    contentLength ??= res.contentLength;
    if (contentLength == null && totalSize != null) {
      final remaining = totalSize - responseOffset;
      contentLength = remaining > 0 ? remaining : 0;
    }
    final responseContentType =
        res.headers['content-type'] ?? 'application/octet-stream';

    debugPrint(
      'DriveAudioSource response status=${res.statusCode} offset=$responseOffset contentLength=$contentLength sourceLength=$totalSize',
    );

    final wrappedStream = res.stream.transform(
      StreamTransformer<List<int>, List<int>>.fromHandlers(
        handleData: (data, sink) => sink.add(data),
        handleError: (error, stackTrace, sink) {
          client.close();
          sink.addError(error, stackTrace);
        },
        handleDone: (sink) {
          client.close();
          sink.close();
        },
      ),
    );

    return StreamAudioResponse(
      sourceLength: totalSize,
      contentLength: contentLength,
      offset: responseOffset,
      stream: wrappedStream,
      contentType: responseContentType,
    );
  }
}
