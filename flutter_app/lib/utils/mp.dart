import 'package:flutter_dotenv/flutter_dotenv.dart';

class MP {
  /// Returns the Mapbox token from the environment, a compile-time
  /// `--dart-define=MAPBOX_TOKEN=...`, or an empty string.
  ///
  /// Resolution order:
  /// 1. `flutter_dotenv` loaded `.env` (`dotenv.env['MAPBOX_TOKEN']`).
  /// 2. Compile-time define via `--dart-define=MAPBOX_TOKEN=...`.
  /// 3. Empty string when no token is available.
  static String get mapboxToken {
    String? envToken;
    try {
      envToken = dotenv.env['MAPBOX_TOKEN'];
    } catch (_) {
      envToken = null;
    }
    if (envToken != null && envToken.trim().isNotEmpty) return envToken.trim();

    const dartDefine = String.fromEnvironment('MAPBOX_TOKEN', defaultValue: '');
    if (dartDefine.isNotEmpty) return dartDefine;

    return '';
  }

  static String get googleMapsApiKey {
    String? envToken;
    try {
      envToken =
          dotenv.env['GOOGLE_MAPS_API_KEY'] ?? dotenv.env['MAPS_API_KEY'];
    } catch (_) {
      envToken = null;
    }
    if (envToken != null && envToken.trim().isNotEmpty) return envToken.trim();

    const dartDefine = String.fromEnvironment(
      'GOOGLE_MAPS_API_KEY',
      defaultValue: '',
    );
    if (dartDefine.isNotEmpty) return dartDefine;

    const mapsDefine = String.fromEnvironment('MAPS_API_KEY', defaultValue: '');
    if (mapsDefine.isNotEmpty) return mapsDefine;

    return '';
  }

  /// Returns a generic Leaflet-compatible tile provider token (e.g. MapTiler).
  /// Use `LEAFLET_TOKEN` in `.env` or `--dart-define=LEAFLET_TOKEN=...`.
  static String get leafletToken {
    String? envToken;
    try {
      envToken = dotenv.env['LEAFLET_TOKEN'];
    } catch (_) {
      envToken = null;
    }
    if (envToken != null && envToken.trim().isNotEmpty) return envToken.trim();

    const dartDefine = String.fromEnvironment(
      'LEAFLET_TOKEN',
      defaultValue: '',
    );
    if (dartDefine.isNotEmpty) return dartDefine;

    return '';
  }
}
