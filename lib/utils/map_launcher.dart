// lib/utils/map_launcher.dart
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:url_launcher/url_launcher.dart';

/// Opens a coordinate in OsmAnd (or any installed `geo:` app) on Android.
/// Falls back to openstreetmap.org on web, iOS, or if no app handles `geo:`.
Future<bool> openInMapApp(double lat, double lng, {int zoom = 18}) async {
  final web = Uri.parse(
    'https://www.openstreetmap.org/?mlat=$lat&mlon=$lng#map=$zoom/$lat/$lng',
  );

  if (!kIsWeb) {
    final geo = Uri.parse('geo:$lat,$lng?z=$zoom');
    try {
      if (await canLaunchUrl(geo)) {
        return await launchUrl(geo, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('geo: launch failed: $e');
    }
  }

  try {
    return await launchUrl(web, mode: LaunchMode.externalApplication);
  } catch (e) {
    debugPrint('OSM web launch failed: $e');
    return false;
  }
}