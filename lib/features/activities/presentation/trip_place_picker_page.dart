import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:planerz/app/theme/app_icons.dart';
import 'package:planerz/app/theme/app_tokens.dart';
import 'package:planerz/core/geocoding/place_geocoding_client.dart';
import 'package:planerz/core/presentation/osm_map.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// Full-screen place picker: search a place by name, or tap the map to drop
/// a pin (its address is then looked up). Pops the [GeocodedPlace] chosen,
/// whose address is empty when none was found for the point.
class TripPlacePickerPage extends ConsumerStatefulWidget {
  const TripPlacePickerPage({
    super.key,
    this.initialPoint,
    this.initialCenter,
    this.initialAddress = '',
  });

  /// The point already set, if any.
  final LatLng? initialPoint;

  /// Where the map opens when no point is set (e.g. another place of the
  /// trip).
  final LatLng? initialCenter;

  /// Shown for [initialPoint]; searched on open when no point is set.
  final String initialAddress;

  static Future<GeocodedPlace?> open(
    BuildContext context, {
    LatLng? initialPoint,
    LatLng? initialCenter,
    String initialAddress = '',
  }) {
    return Navigator.of(context).push<GeocodedPlace>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => TripPlacePickerPage(
          initialPoint: initialPoint,
          initialCenter: initialCenter,
          initialAddress: initialAddress,
        ),
      ),
    );
  }

  @override
  ConsumerState<TripPlacePickerPage> createState() =>
      _TripPlacePickerPageState();
}

class _TripPlacePickerPageState extends ConsumerState<TripPlacePickerPage> {
  final _mapController = MapController();
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _searchDebounce;

  /// Bumped on each request so that only the latest answer is applied.
  int _searchSeq = 0;
  int _reverseSeq = 0;

  bool _mapReady = false;
  bool _searching = false;

  /// A search finished for the text currently typed.
  bool _searched = false;
  List<GeocodedPlace> _results = const [];

  LatLng? _point;
  String _address = '';
  bool _resolvingAddress = false;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    _point = widget.initialPoint;
    final initialAddress = widget.initialAddress.trim();
    if (_point != null) {
      _address = initialAddress;
    } else if (initialAddress.isNotEmpty) {
      _searchController.text = initialAddress;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _search(initialAddress));
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    _mapController.dispose();
    super.dispose();
  }

  String get _languageCode => Localizations.localeOf(context).languageCode;

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    if (value.trim().length < 3) {
      _searchSeq++;
      setState(() {
        _results = const [];
        _searching = false;
        _searched = false;
      });
      return;
    }
    setState(() => _searched = false);
    _searchDebounce = Timer(
      const Duration(milliseconds: 400),
      () => _search(value),
    );
  }

  Future<void> _search(String query) async {
    if (query.trim().length < 3) return;
    final seq = ++_searchSeq;
    setState(() => _searching = true);
    // Favour places near what the map shows once zoomed on a region.
    final near = _mapReady && _mapController.camera.zoom >= 8
        ? _mapController.camera.center
        : _point ?? widget.initialCenter;
    final results = await ref.read(placeGeocodingClientProvider).search(
          query,
          languageCode: _languageCode,
          nearLat: near?.latitude,
          nearLng: near?.longitude,
        );
    if (!mounted || seq != _searchSeq) return;
    setState(() {
      _results = results;
      _searching = false;
      _searched = true;
    });
  }

  void _selectResult(GeocodedPlace place) {
    final point = LatLng(place.lat, place.lng);
    _searchFocus.unfocus();
    _reverseSeq++;
    setState(() {
      _point = point;
      _address = place.address;
      _resolvingAddress = false;
      _results = const [];
      _searched = false;
    });
    _moveTo(point, 16);
  }

  void _moveTo(LatLng point, double zoom) {
    if (_mapReady) _mapController.move(point, zoom);
  }

  Future<void> _dropPin(LatLng point) async {
    _searchFocus.unfocus();
    final seq = ++_reverseSeq;
    setState(() {
      _point = point;
      _address = '';
      _resolvingAddress = true;
      _results = const [];
      _searched = false;
    });
    final place = await ref.read(placeGeocodingClientProvider).reverse(
          lat: point.latitude,
          lng: point.longitude,
          languageCode: _languageCode,
        );
    if (!mounted || seq != _reverseSeq) return;
    setState(() {
      _address = place?.address ?? '';
      _resolvingAddress = false;
    });
  }

  Future<void> _locateMe() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      if (!kIsWeb && !await Geolocator.isLocationServiceEnabled()) {
        throw StateError('Location service disabled');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw StateError('Location permission denied');
      }
      final position = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      final point = LatLng(position.latitude, position.longitude);
      _moveTo(point, 16);
      await _dropPin(point);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.activitiesPlaceMyLocationUnavailable,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _confirm() {
    final point = _point;
    if (point == null) return;
    Navigator.of(context).pop(
      GeocodedPlace(
        address: _address,
        lat: point.latitude,
        lng: point.longitude,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final point = _point;
    final showNoResult = _searched &&
        !_searching &&
        _results.isEmpty &&
        _searchController.text.trim().length >= 3;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.activitiesPlacePickerTitle),
        actions: [
          IconButton(
            tooltip: l10n.commonConfirm,
            onPressed: point == null || _resolvingAddress ? null : _confirm,
            icon: const Icon(PhosphorIconsRegular.check),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter:
                  widget.initialPoint ?? widget.initialCenter ?? osmFranceCenter,
              initialZoom: widget.initialPoint != null
                  ? 15
                  : widget.initialCenter != null
                      ? 12
                      : 5,
              onMapReady: () => _mapReady = true,
              onTap: (_, latLng) => _dropPin(latLng),
            ),
            children: [
              osmTileLayer(),
              if (point != null)
                MarkerLayer(markers: [osmPinMarker(point, scheme.primary)]),
              const OsmMapAttribution(),
            ],
          ),
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Material(
              elevation: 3,
              color: scheme.surface,
              borderRadius: BorderRadius.circular(AppTokens.radiusMd),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _searchController,
                    focusNode: _searchFocus,
                    textInputAction: TextInputAction.search,
                    onChanged: _onSearchChanged,
                    onSubmitted: (value) {
                      _searchDebounce?.cancel();
                      _search(value);
                    },
                    decoration: InputDecoration(
                      hintText: l10n.activitiesPlaceSearchHint,
                      prefixIcon:
                          const Icon(PhosphorIconsRegular.magnifyingGlass),
                      suffixIcon: _searching
                          ? const Padding(
                              padding: EdgeInsets.all(14),
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                  if (_results.isNotEmpty) ...[
                    const Divider(height: 1),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 280),
                      child: ListView(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        children: [
                          for (final place in _results)
                            ListTile(
                              dense: true,
                              leading: const Icon(PhosphorIconsRegular.mapPin),
                              title: Text(place.address),
                              onTap: () => _selectResult(place),
                            ),
                        ],
                      ),
                    ),
                  ] else if (showNoResult) ...[
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        l10n.activitiesPlaceNoResult,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            // Leaves the OpenStreetMap credit visible.
            bottom: 36,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FloatingActionButton.small(
                  heroTag: 'trip_place_picker_locate',
                  tooltip: l10n.activitiesPlaceMyLocation,
                  onPressed: _locating ? null : _locateMe,
                  child: _locating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(PhosphorIconsRegular.crosshair),
                ),
                if (point != null) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(PhosphorIconsFill.mapPin, color: scheme.primary),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _resolvingAddress
                                  ? const LinearProgressIndicator()
                                  : Text(
                                      _address.isNotEmpty
                                          ? _address
                                          : '${point.latitude.toStringAsFixed(5)}, '
                                              '${point.longitude.toStringAsFixed(5)}',
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
