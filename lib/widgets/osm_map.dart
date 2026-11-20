// lib/widgets/osm_map.dart
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Default view copied from:
/// https://www.openstreetmap.org/#map=8/11.426/123.008
const LatLng kDefaultCenter = LatLng(11.426, 123.008);
const double kDefaultZoom = 8;

class OsmMap extends StatelessWidget {
  const OsmMap({
    super.key,
    this.center = kDefaultCenter,
    this.zoom = kDefaultZoom,
    this.markers = const <Marker>[],
  });

  final LatLng center;
  final double zoom;
  final List<Marker> markers;

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      options: MapOptions(
        initialCenter: center,
        initialZoom: zoom,
        minZoom: 3,
        maxZoom: 18,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.hris_biometrics',
          // Don't crash the UI if a tile fails (e.g. offline).
          errorTileCallback: (tile, error, stackTrace) {
            debugPrint('Tile load failed: $error');
          },
        ),
        MarkerLayer(markers: markers),
        const RichAttributionWidget(
          attributions: [
            TextSourceAttribution('© OpenStreetMap contributors'),
          ],
        ),
      ],
    );
  }
}