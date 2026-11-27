import 'dart:convert';

import 'package:http/http.dart' as http;

/// A backup file in the app's hidden folder in Google Drive.
class DriveFile {
  const DriveFile({required this.id, required this.name, required this.createdAt, this.size});

  factory DriveFile.fromJson(Map<String, Object?> json) => DriveFile(
    id: json['id']! as String,
    name: json['name']! as String,
    createdAt: DateTime.tryParse('${json['createdTime']}')?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0),
    size: int.tryParse('${json['size']}'),
  );

  final String id;
  final String name;
  final DateTime createdAt;

  /// Size in bytes, when Drive gives it.
  final int? size;
}

/// Drive refused the access token: it expired or was taken back.
class DriveAuthExpired implements Exception {
  const DriveAuthExpired();
}

/// A Drive request that failed for another reason.
class DriveRequestException implements Exception {
  const DriveRequestException(this.status, this.body);

  final int status;
  final String body;

  @override
  String toString() => 'Drive request failed ($status): $body';
}

/// The few Drive calls the backup needs, all inside the app's own hidden
/// folder (appDataFolder). That folder can only be reached with the
/// drive.appdata scope, which sees nothing else in the user's Drive.
class DriveClient {
  DriveClient(this._http);

  final http.Client _http;

  static const scope = 'https://www.googleapis.com/auth/drive.appdata';
  static const _api = 'https://www.googleapis.com/drive/v3';
  static const _upload = 'https://www.googleapis.com/upload/drive/v3/files';
  static const _fields = 'id,name,createdTime,size';

  Map<String, String> _auth(String token) => {'Authorization': 'Bearer $token'};

  /// Uploads [text] as a JSON file named [name].
  Future<DriveFile> upload(String token, String name, String text) async {
    const boundary = 'finance_tracker_backup_boundary';
    final metadata = jsonEncode({
      'name': name,
      'parents': ['appDataFolder'],
      'mimeType': 'application/json',
    });
    final body = StringBuffer()
      ..write('--$boundary\r\n')
      ..write('Content-Type: application/json; charset=UTF-8\r\n\r\n')
      ..write('$metadata\r\n')
      ..write('--$boundary\r\n')
      ..write('Content-Type: application/json\r\n\r\n')
      ..write(text)
      ..write('\r\n--$boundary--\r\n');
    final response = await _http.post(
      Uri.parse('$_upload?uploadType=multipart&fields=$_fields'),
      headers: {..._auth(token), 'Content-Type': 'multipart/related; boundary=$boundary'},
      body: utf8.encode(body.toString()),
    );
    return DriveFile.fromJson(_json(response));
  }

  /// This app's backups in Drive, newest first.
  Future<List<DriveFile>> list(String token) async {
    final files = <DriveFile>[];
    String? page;
    do {
      final uri = Uri.parse('$_api/files').replace(
        queryParameters: {
          'spaces': 'appDataFolder',
          'fields': 'nextPageToken,files($_fields)',
          'orderBy': 'createdTime desc',
          'pageSize': '100',
          'pageToken': ?page,
        },
      );
      final json = _json(await _http.get(uri, headers: _auth(token)));
      for (final f in (json['files'] as List?) ?? const []) {
        files.add(DriveFile.fromJson(Map<String, Object?>.from(f as Map)));
      }
      page = json['nextPageToken'] as String?;
    } while (page != null);
    files.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return files;
  }

  /// The text of one backup.
  Future<String> download(String token, String id) async {
    final response = await _http.get(Uri.parse('$_api/files/$id?alt=media'), headers: _auth(token));
    _check(response);
    return utf8.decode(response.bodyBytes);
  }

  Future<void> delete(String token, String id) async {
    final response = await _http.delete(Uri.parse('$_api/files/$id'), headers: _auth(token));
    if (response.statusCode == 404) return;
    _check(response);
  }

  /// Takes back the access the user gave the app. Drive keeps the files.
  Future<void> revoke(String token) async {
    final response = await _http.post(
      Uri.parse('https://oauth2.googleapis.com/revoke'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {'token': token},
    );
    // 400 means the token was already gone.
    if (response.statusCode >= 300 && response.statusCode != 400) {
      throw DriveRequestException(response.statusCode, response.body);
    }
  }

  /// The Google account's email, to show which account backups go to.
  /// Null when Drive doesn't say.
  Future<String?> accountEmail(String token) async {
    try {
      final json = _json(await _http.get(Uri.parse('$_api/about?fields=user(emailAddress)'), headers: _auth(token)));
      final user = json['user'];
      return user is Map ? user['emailAddress'] as String? : null;
    } on DriveRequestException {
      return null;
    }
  }

  void _check(http.Response response) {
    if (response.statusCode == 401) throw const DriveAuthExpired();
    if (response.statusCode >= 300) throw DriveRequestException(response.statusCode, response.body);
  }

  Map<String, Object?> _json(http.Response response) {
    _check(response);
    final json = jsonDecode(utf8.decode(response.bodyBytes));
    if (json is! Map<String, Object?>) throw DriveRequestException(response.statusCode, response.body);
    return json;
  }
}
