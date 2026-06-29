import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';

abstract class AssetLoader {
  Future<Map<String, dynamic>> loadJson(String path);
}

/// Used at runtime — reads from Flutter's asset bundle.
class FlutterAssetLoader implements AssetLoader {
  @override
  Future<Map<String, dynamic>> loadJson(String path) async {
    final raw = await rootBundle.loadString(path);
    return json.decode(raw) as Map<String, dynamic>;
  }
}

/// Used in tests — reads directly from the filesystem.
/// Allows tests to run without a Flutter engine.
class FileAssetLoader implements AssetLoader {
  final String rootDir;

  const FileAssetLoader(this.rootDir);

  @override
  Future<Map<String, dynamic>> loadJson(String path) async {
    final file = File('$rootDir/$path');
    final raw = await file.readAsString();
    return json.decode(raw) as Map<String, dynamic>;
  }
}
