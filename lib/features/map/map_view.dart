import 'dart:async';
import 'dart:convert';

import 'package:rms/core/constants/api_constants.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'reservation_service.dart';
import 'package:intl/intl.dart';
import 'package:rms/shared/themes/feed_palette.dart';

class MapView extends StatefulWidget {
  const MapView({super.key});

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> {
  final ReservationService _reservationService = ReservationService();
  static const int _maxResults = 4000;
  static const String _destinationPrefsKey = 'map_filter_destination';
  static const String _centerFilterPrefsKey = 'map_filter_center_type';

  static const MapArea _spainArea = MapArea(
    label: 'Espana',
    center: LatLng(40.4168, -3.7038),
    zoom: 5.8,
    queryNames: ['Espa\u00f1a'],
    kind: MapAreaKind.spain,
  );

  static final Map<String, MapArea> _autonomousCommunities = {
    'Andalucia': const MapArea(
      label: 'Andalucia',
      center: LatLng(37.5443, -4.7278),
      zoom: 7,
      queryNames: ['Andaluc\u00eda'],
    ),
    'Aragon': const MapArea(
      label: 'Aragon',
      center: LatLng(41.5976, -0.9057),
      zoom: 7,
      queryNames: ['Arag\u00f3n'],
    ),
    'Asturias': const MapArea(
      label: 'Asturias',
      center: LatLng(43.3614, -5.8593),
      zoom: 8,
      queryNames: ['Asturias', 'Principado de Asturias'],
    ),
    'Illes Balears': const MapArea(
      label: 'Illes Balears',
      center: LatLng(39.5342, 2.8577),
      zoom: 8,
      queryNames: ['Illes Balears', 'Islas Baleares'],
    ),
    'Canarias': const MapArea(
      label: 'Canarias',
      center: LatLng(28.2916, -16.6291),
      zoom: 7,
      queryNames: ['Canarias'],
    ),
    'Cantabria': const MapArea(
      label: 'Cantabria',
      center: LatLng(43.1828, -3.9878),
      zoom: 8,
      queryNames: ['Cantabria'],
    ),
    'Castilla y Leon': const MapArea(
      label: 'Castilla y Leon',
      center: LatLng(41.8357, -4.3976),
      zoom: 7,
      queryNames: ['Castilla y Le\u00f3n'],
    ),
    'Castilla-La Mancha': const MapArea(
      label: 'Castilla-La Mancha',
      center: LatLng(39.2796, -3.0977),
      zoom: 7,
      queryNames: ['Castilla-La Mancha'],
    ),
    'Catalunya': const MapArea(
      label: 'Catalunya',
      center: LatLng(41.5912, 1.5209),
      zoom: 7,
      queryNames: ['Catalunya', 'Catalu\u00f1a'],
    ),
    'Comunitat Valenciana': const MapArea(
      label: 'Comunitat Valenciana',
      center: LatLng(39.4840, -0.7533),
      zoom: 7,
      queryNames: ['Comunitat Valenciana', 'Comunidad Valenciana'],
    ),
    'Extremadura': const MapArea(
      label: 'Extremadura',
      center: LatLng(39.4937, -6.0679),
      zoom: 7,
      queryNames: ['Extremadura'],
    ),
    'Galicia': const MapArea(
      label: 'Galicia',
      center: LatLng(42.5751, -8.1339),
      zoom: 7,
      queryNames: ['Galicia'],
    ),
    'La Rioja': const MapArea(
      label: 'La Rioja',
      center: LatLng(42.2871, -2.5396),
      zoom: 8,
      queryNames: ['La Rioja'],
    ),
    'Comunidad de Madrid': const MapArea(
      label: 'Comunidad de Madrid',
      center: LatLng(40.4168, -3.7038),
      zoom: 8,
      queryNames: ['Comunidad de Madrid'],
    ),
    'Region de Murcia': const MapArea(
      label: 'Region de Murcia',
      center: LatLng(37.9834, -1.1299),
      zoom: 8,
      queryNames: ['Regi\u00f3n de Murcia', 'Murcia'],
    ),
    'Navarra': const MapArea(
      label: 'Navarra',
      center: LatLng(42.6954, -1.6761),
      zoom: 8,
      queryNames: ['Navarra', 'Comunidad Foral de Navarra'],
    ),
    'Pais Vasco': const MapArea(
      label: 'Pais Vasco',
      center: LatLng(42.9896, -2.6189),
      zoom: 8,
      queryNames: ['Euskadi', 'Pa\u00eds Vasco'],
    ),
    'Ceuta': const MapArea(
      label: 'Ceuta',
      center: LatLng(35.8894, -5.3213),
      zoom: 12,
      queryNames: ['Ceuta'],
    ),
    'Melilla': const MapArea(
      label: 'Melilla',
      center: LatLng(35.2923, -2.9381),
      zoom: 12,
      queryNames: ['Melilla'],
    ),
  };

  static final Map<String, LatLng> _cityCenters = {
    'Madrid': const LatLng(40.4168, -3.7038),
    'Barcelona': const LatLng(41.3851, 2.1734),
    'Valencia': const LatLng(39.4699, -0.3763),
    'Sevilla': const LatLng(37.3891, -5.9845),
    'Zaragoza': const LatLng(41.6488, -0.8891),
    'Malaga': const LatLng(36.7213, -4.4214),
    'Murcia': const LatLng(37.9834, -1.1299),
    'Palma': const LatLng(39.5696, 2.6502),
    'Las Palmas': const LatLng(28.1248, -15.4300),
    'Bilbao': const LatLng(43.2630, -2.9350),
    'Alicante': const LatLng(38.3452, -0.4810),
    'Cordoba': const LatLng(37.8882, -4.7794),
    'Valladolid': const LatLng(41.6523, -4.7245),
    'Vigo': const LatLng(42.2406, -8.7207),
    'Gijon': const LatLng(43.5322, -5.6611),
    'A Coruna': const LatLng(43.3623, -8.4115),
    'Granada': const LatLng(37.1773, -3.5986),
    'Vitoria': const LatLng(42.8467, -2.6727),
    'Oviedo': const LatLng(43.3619, -5.8494),
    'Pamplona': const LatLng(42.8125, -1.6458),
    'Santander': const LatLng(43.4623, -3.8099),
    'San Sebastian': const LatLng(43.3183, -1.9812),
    'Logrono': const LatLng(42.4627, -2.4449),
    'Toledo': const LatLng(39.8628, -4.0273),
    'Badajoz': const LatLng(38.8794, -6.9707),
    'Caceres': const LatLng(39.4753, -6.3724),
    'Salamanca': const LatLng(40.9701, -5.6635),
    'Burgos': const LatLng(42.3439, -3.6969),
    'Leon': const LatLng(42.5987, -5.5671),
    'Cadiz': const LatLng(36.5271, -6.2886),
    'Almeria': const LatLng(36.8340, -2.4637),
    'Huelva': const LatLng(37.2614, -6.9447),
    'Jaen': const LatLng(37.7796, -3.7849),
    'Lleida': const LatLng(41.6176, 0.6200),
    'Tarragona': const LatLng(41.1189, 1.2445),
    'Girona': const LatLng(41.9794, 2.8214),
    'Castellon': const LatLng(39.9864, -0.0513),
    'Cartagena': const LatLng(37.6257, -0.9966),
    'Lorca': const LatLng(37.6712, -1.7017),
    'Albacete': const LatLng(38.9943, -1.8585),
    'Ciudad Real': const LatLng(38.9848, -3.9274),
    'Cuenca': const LatLng(40.0704, -2.1374),
    'Guadalajara': const LatLng(40.6325, -3.1602),
    'Huesca': const LatLng(42.1401, -0.4089),
    'Teruel': const LatLng(40.3457, -1.1065),
    'Avila': const LatLng(40.6565, -4.6818),
    'Palencia': const LatLng(42.0097, -4.5288),
    'Segovia': const LatLng(40.9429, -4.1088),
    'Soria': const LatLng(41.7666, -2.4790),
    'Zamora': const LatLng(41.5035, -5.7446),
    'Lugo': const LatLng(43.0097, -7.5568),
    'Ourense': const LatLng(42.3358, -7.8639),
    'Pontevedra': const LatLng(42.4310, -8.6444),
    'Santiago de Compostela': const LatLng(42.8782, -8.5448),
    'Merida': const LatLng(38.9170, -6.3443),
    'Santa Cruz de Tenerife': const LatLng(28.4636, -16.2518),
  };

  static const List<CenterFilter> _centerFilters = [
    CenterFilter(
      id: 'all',
      label: 'Todos',
      description: 'Centros deportivos, gimnasios y espacios de entrenamiento',
      icon: Icons.sports_score,
    ),
    CenterFilter(
      id: 'gym',
      label: 'Gym',
      description: 'Gimnasios, fitness, musculacion y entrenamiento general',
      icon: Icons.fitness_center,
    ),
    CenterFilter(
      id: 'sports_center',
      label: 'Polideportivos',
      description: 'Centros deportivos y pabellones',
      icon: Icons.sports_handball,
    ),
    CenterFilter(
      id: 'boxing',
      label: 'Boxeo',
      description: 'Boxeo y clubes de boxeo',
      icon: Icons.sports_mma,
    ),
    CenterFilter(
      id: 'kickboxing',
      label: 'Kickboxing',
      description: 'Kickboxing, muay thai y striking',
      icon: Icons.sports_martial_arts,
    ),
    CenterFilter(
      id: 'crossfit',
      label: 'CrossFit',
      description: 'Boxes y entrenamiento funcional',
      icon: Icons.timer,
    ),
    CenterFilter(
      id: 'martial_arts',
      label: 'Artes marciales',
      description: 'Dojo, judo, karate, taekwondo y similares',
      icon: Icons.sports_martial_arts,
    ),
    CenterFilter(
      id: 'swimming',
      label: 'Piscina',
      description: 'Piscinas y centros de natacion',
      icon: Icons.pool,
    ),
    CenterFilter(
      id: 'padel',
      label: 'Padel',
      description: 'Pistas y clubes de padel',
      icon: Icons.sports_tennis,
    ),
    CenterFilter(
      id: 'tennis',
      label: 'Tenis',
      description: 'Clubes y pistas de tenis',
      icon: Icons.sports_tennis,
    ),
    CenterFilter(
      id: 'football',
      label: 'Futbol',
      description: 'Campos y clubes de futbol',
      icon: Icons.sports_soccer,
    ),
    CenterFilter(
      id: 'basketball',
      label: 'Baloncesto',
      description: 'Pistas y pabellones de baloncesto',
      icon: Icons.sports_basketball,
    ),
    CenterFilter(
      id: 'yoga_pilates',
      label: 'Yoga/Pilates',
      description: 'Estudios de yoga, pilates y bienestar',
      icon: Icons.self_improvement,
    ),
    CenterFilter(
      id: 'calisthenics',
      label: 'Calistenia',
      description: 'Parques y zonas de entrenamiento exterior',
      icon: Icons.accessibility_new,
    ),
  ];

  final MapController _mapController = MapController();

  List<SportsCenter> _centers = const [];
  bool _isLoading = false;
  bool _mapReady = false;
  bool _prefsLoaded = false;
  bool _didInitialLoad = false;
  MapArea _selectedDestination = _spainArea;
  CenterFilter _selectedCenterFilter = _centerFilters.first;
  String? _errorMessage;
  int _requestVersion = 0;
  String? _activeRequestKey;
  final Map<String, List<SportsCenter>> _centersCache = {};

  @override
  void initState() {
    super.initState();
    unawaited(_loadSavedFilters());
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  List<Marker> get _markers => _centers
      .map(
        (center) => Marker(
          width: 64,
          height: 64,
          point: center.location,
          child: _CustomMarker(
            icon: _getIcon(center.type),
            color: _getColor(center.type),
            onTap: () => _showCenterInfo(center),
          ),
        ),
      )
      .toList();

  String get _activePlace => _selectedDestination.label;

  List<MapArea> get _destinationOptions => [
        _spainArea,
        ..._autonomousCommunities.values,
        ..._cityCenters.entries.map(
          (entry) => MapArea(
            label: entry.key,
            center: entry.value,
            zoom: 12,
            queryNames: [entry.key],
            kind: MapAreaKind.city,
          ),
        ),
      ];

  Future<void> _loadSavedFilters() async {
    final prefs = await SharedPreferences.getInstance();
    final savedDestination = prefs.getString(_destinationPrefsKey);
    final savedCenterFilter = prefs.getString(_centerFilterPrefsKey);

    if (!mounted) return;

    setState(() {
      _selectedDestination =
          _resolveDestinationByLabel(savedDestination) ?? _spainArea;
      _selectedCenterFilter =
          _resolveCenterFilter(savedCenterFilter) ?? _centerFilters.first;
      _prefsLoaded = true;
    });

    _tryInitialLoad();
  }

  void _tryInitialLoad() {
    if (!_mapReady || !_prefsLoaded || _didInitialLoad) return;
    _didInitialLoad = true;
    unawaited(_loadSelectedFilters(moveToDestination: true));
  }

  MapArea? _resolveDestinationByLabel(String? label) {
    if (label == null || label.isEmpty) return null;
    final normalized = _normalizeForSearch(label);
    for (final destination in _destinationOptions) {
      if (_normalizeForSearch(destination.label) == normalized) {
        return destination;
      }
      for (final queryName in destination.queryNames) {
        if (_normalizeForSearch(queryName) == normalized) {
          return destination;
        }
      }
    }
    return null;
  }

  CenterFilter? _resolveCenterFilter(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final filter in _centerFilters) {
      if (filter.id == id) return filter;
    }
    return null;
  }

  Future<void> _setDestination(MapArea destination) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_destinationPrefsKey, destination.label);

    if (!mounted) return;
    setState(() => _selectedDestination = destination);
    await _loadSelectedFilters(moveToDestination: true);
  }

  Future<void> _setCenterFilter(CenterFilter filter) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_centerFilterPrefsKey, filter.id);

    if (!mounted) return;
    setState(() => _selectedCenterFilter = filter);
    await _loadSelectedFilters(moveToDestination: false);
  }

  Future<void> _loadSelectedFilters({required bool moveToDestination}) async {
    if (_mapReady && moveToDestination) {
      _mapController.move(
        _selectedDestination.center,
        _selectedDestination.zoom,
      );
    }

    await _loadSportsCenters(
      destination: _selectedDestination,
      filter: _selectedCenterFilter,
      cacheKey: _cacheKeyFor(_selectedDestination, _selectedCenterFilter),
      moveToResults: moveToDestination,
    );
  }

  Future<void> _loadSportsCenters({
    required MapArea destination,
    required CenterFilter filter,
    required String cacheKey,
    required bool moveToResults,
  }) async {
    if (_activeRequestKey == cacheKey && _isLoading) return;

    final cachedCenters = _centersCache[cacheKey];
    if (cachedCenters != null) {
      setState(() {
        _centers = cachedCenters;
        _isLoading = false;
        _errorMessage = cachedCenters.isEmpty
            ? 'No se han encontrado centros deportivos en esta zona.'
            : null;
      });

      if (moveToResults && cachedCenters.isNotEmpty && _mapReady) {
        _fitToCenters(cachedCenters);
      }
      return;
    }

    final requestVersion = ++_requestVersion;
    _activeRequestKey = cacheKey;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final centers = await _fetchSportsCenters(
        destination: destination,
        filter: filter,
      );
      if (!mounted || requestVersion != _requestVersion) return;

      _centersCache[cacheKey] = centers;
      setState(() {
        _centers = centers;
        _isLoading = false;
        _errorMessage = centers.isEmpty
            ? 'No se han encontrado centros deportivos en esta zona.'
            : null;
      });

      if (moveToResults && centers.isNotEmpty && _mapReady) {
        _fitToCenters(centers);
      }
    } catch (e) {
      if (!mounted || requestVersion != _requestVersion) return;
      setState(() {
        _isLoading = false;
        _errorMessage =
            'No se han podido cargar los centros guardados en la base de datos ahora mismo.';
      });
    } finally {
      if (_activeRequestKey == cacheKey) {
        _activeRequestKey = null;
      }
    }
  }

  String _cacheKeyFor(MapArea destination, CenterFilter filter) {
    return '${destination.kind.name}:${_normalizeForSearch(destination.label)}:${filter.id}';
  }

  Future<List<SportsCenter>> _fetchSportsCenters({
    required MapArea destination,
    required CenterFilter filter,
  }) async {
    final uri = Uri.parse('${ApiConstants.apiHost}/sports-centers').replace(
      queryParameters: {
        'destination': destination.label,
        'kind': destination.kind.name,
        'category': filter.id,
        'limit': _maxResults.toString(),
      },
    );

    final response = await http.get(uri).timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw Exception('Sports centers API error: ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    final rows = decoded is List ? decoded : const [];
    final centersByKey = <String, SportsCenter>{};

    for (final row in rows) {
      if (row is! Map<String, dynamic>) continue;
      final center = SportsCenter.fromJson(row);
      centersByKey[center.dedupeKey] = center;
    }

    final centers = centersByKey.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return centers;
  }

  void _fitToCenters(List<SportsCenter> centers) {
    if (centers.length == 1) {
      _mapController.move(centers.first.location, 14);
      return;
    }

    _mapController.fitCamera(
      CameraFit.coordinates(
        coordinates: centers.map((center) => center.location).toList(),
        padding: const EdgeInsets.all(72),
        maxZoom: 13,
      ),
    );
  }

  String _normalizeForSearch(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll('\u00e1', 'a')
        .replaceAll('\u00e9', 'e')
        .replaceAll('\u00ed', 'i')
        .replaceAll('\u00f3', 'o')
        .replaceAll('\u00fa', 'u')
        .replaceAll('\u00fc', 'u')
        .replaceAll('\u00f1', 'n')
        .replaceAll('-', ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  Future<void> _launchMaps(SportsCenter center) async {
    final query = Uri.encodeComponent(
      '${center.name} ${center.location.latitude},${center.location.longitude}',
    );
    final url = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$query',
    );
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _launchWebsite(String website) async {
    final normalized =
        website.startsWith('http://') || website.startsWith('https://')
            ? website
            : 'https://$website';
    final url = Uri.parse(normalized);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  IconData _getIcon(String type) {
    if (type.contains('Gimnasio') || type.contains('Fitness')) {
      return Icons.fitness_center;
    }
    if (type.contains('Piscina')) return Icons.pool;
    if (type.contains('Estadio')) return Icons.stadium;
    if (type.contains('Dojo')) return Icons.sports_martial_arts;
    return Icons.sports_score;
  }

  Color _getColor(String type) {
    if (type.contains('Gimnasio') || type.contains('Fitness')) {
      return Colors.blue;
    }
    if (type.contains('Piscina')) return Colors.teal;
    if (type.contains('Estadio')) return Colors.deepPurple;
    if (type.contains('Dojo')) return Colors.redAccent;
    return FeedPalette.accent;
  }

  void _showCenterInfo(SportsCenter center) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        constraints: const BoxConstraints(maxHeight: 520),
        decoration: BoxDecoration(
          color: FeedPalette.surfaceSoft,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 48,
                    height: 5,
                    decoration: BoxDecoration(
                      color: FeedPalette.surface,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          color: _getColor(center.type).withAlpha(31),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: center.image.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: center.image,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => Center(
                                  child: Icon(
                                    _getIcon(center.type),
                                    color: _getColor(center.type),
                                    size: 30,
                                  ),
                                ),
                                errorWidget: (context, url, error) => Icon(
                                  _getIcon(center.type),
                                  color: _getColor(center.type),
                                  size: 30,
                                ),
                              )
                            : Icon(
                                _getIcon(center.type),
                                color: _getColor(center.type),
                                size: 30,
                              ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            center.name,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              height: 1.12,
                              color: FeedPalette.text,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${center.city} · ${center.type}',
                            style: TextStyle(
                              color: FeedPalette.muted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                _CenterDetailRow(
                  icon: Icons.place_outlined,
                  label: center.address.isEmpty
                      ? 'Ubicacion disponible en el mapa'
                      : center.address,
                ),
                if (center.openingHours.isNotEmpty)
                  _CenterDetailRow(
                    icon: Icons.schedule,
                    label: center.openingHours,
                  ),
                if (center.phone.isNotEmpty)
                  _CenterDetailRow(
                    icon: Icons.phone_outlined,
                    label: center.phone,
                  ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _launchMaps(center),
                        icon: const Icon(Icons.directions, size: 18),
                        label: const Text(
                          'Ruta',
                          style: TextStyle(fontSize: 13),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue.shade600,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _showBookingDialog(center),
                        icon: const Icon(Icons.calendar_today, size: 18),
                        label: const Text(
                          'Reservar',
                          style: TextStyle(fontSize: 13),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: FeedPalette.accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
                    if (center.website.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _launchWebsite(center.website),
                          icon: const Icon(Icons.language, size: 18),
                          label: const Text(
                            'Web',
                            style: TextStyle(fontSize: 13),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: FeedPalette.text,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            side: BorderSide(color: FeedPalette.surface),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Datos guardados en la base de datos de FitConnect.',
                  style: TextStyle(color: FeedPalette.muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showBookingDialog(SportsCenter center) async {
    DateTime selectedDate = DateTime.now().add(const Duration(days: 1));
    TimeOfDay selectedTime = const TimeOfDay(hour: 10, minute: 0);

    // Determinar tipos de reserva lógicos según el centro
    List<String> types = ['Entrenamiento Libre'];
    String centerType = center.type.toLowerCase();
    if (centerType.contains('gym') || centerType.contains('fitness')) {
      types.addAll(['Clase de Musculación', 'Entrenamiento Personal']);
    } else if (centerType.contains('box') || centerType.contains('kick')) {
      types.addAll(['Clase de Kickboxing', 'Sparring Guiado']);
    } else if (centerType.contains('padel')) {
      types.addAll(['Pista de Padel', 'Clase de Padel']);
    } else if (centerType.contains('piscina') || centerType.contains('swim')) {
      types.addAll(['Calle de Natación', 'Aquagym']);
    } else {
      types.add('Clase Colectiva');
    }

    String selectedType = types.first;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Reservar en ${center.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('Fecha'),
                subtitle: Text(DateFormat('dd/MM/yyyy').format(selectedDate)),
                leading: const Icon(Icons.calendar_today),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: selectedDate,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 30)),
                  );
                  if (picked != null) {
                    setDialogState(() => selectedDate = picked);
                  }
                },
              ),
              ListTile(
                title: const Text('Hora'),
                subtitle: Text(selectedTime.format(context)),
                leading: const Icon(Icons.access_time),
                onTap: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: selectedTime,
                  );
                  if (picked != null) {
                    setDialogState(() => selectedTime = picked);
                  }
                },
              ),
              // ignore: deprecated_member_use
              DropdownButtonFormField<String>(
                initialValue: selectedType,
                decoration: const InputDecoration(labelText: 'Tipo de Reserva'),
                items: types
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (val) => setDialogState(() => selectedType = val!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: FeedPalette.accent,
                foregroundColor: Colors.white,
              ),
              child: const Text('Confirmar Reserva'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && center.id != null) {
      if (!mounted) return;

      // Mostrar loading snackbar
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Procesando reserva...'),
          duration: Duration(seconds: 1),
        ),
      );

      final success = await _reservationService.createReservation(
        sportsCenterId: center.id!,
        date: DateFormat('yyyy-MM-dd').format(selectedDate),
        time:
            '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}:00',
        type: selectedType,
      );

      if (mounted) {
        if (success) {
          Navigator.pop(context); // Cerrar info modal
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('¡Reserva confirmada con éxito!'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error al crear la reserva. Inténtalo de nuevo.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _showDestinationPicker() async {
    final destination = await showModalBottomSheet<MapArea>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _DestinationPickerSheet(
        destinations: _destinationOptions,
        selectedDestination: _selectedDestination,
      ),
    );

    if (destination == null) return;
    await _setDestination(destination);
  }

  Future<void> _showCenterFilterPicker() async {
    final filter = await showModalBottomSheet<CenterFilter>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _CenterFilterPickerSheet(
        filters: _centerFilters,
        selectedFilter: _selectedCenterFilter,
      ),
    );

    if (filter == null) return;
    await _setCenterFilter(filter);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ColoredBox(
          color: FeedPalette.background,
          child: const SizedBox.expand(),
        ),
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _spainArea.center,
            initialZoom: _spainArea.zoom,
            maxZoom: 18,
            onMapReady: () {
              _mapReady = true;
              _tryInitialLoad();
            },
          ),
          children: [
            TileLayer(
              urlTemplate: FeedPalette.isDark
                  ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
                  : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              subdomains: FeedPalette.isDark
                  ? const ['a', 'b', 'c', 'd']
                  : const ['a', 'b', 'c'],
              userAgentPackageName: 'com.fitconnect.app',
            ),
            MarkerClusterLayerWidget(
              options: MarkerClusterLayerOptions(
                maxClusterRadius: 45,
                size: const Size(40, 40),
                markers: _markers,
                spiderfyCluster: true,
                builder: (context, markers) {
                  return Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: FeedPalette.accent,
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 10,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        markers.length.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: _MapFilterPanel(
            destination: _selectedDestination,
            centerFilter: _selectedCenterFilter,
            isLoading: _isLoading,
            onDestinationTap: _showDestinationPicker,
            onCenterFilterTap: _showCenterFilterPicker,
          ),
        ),
        Positioned(
          top: 130,
          left: 16,
          right: 16,
          child: _StatusPill(
            isLoading: _isLoading,
            errorMessage: _errorMessage,
            count: _centers.length,
            activePlace: _activePlace,
            centerFilterLabel: _selectedCenterFilter.label,
            onRetry: () => _loadSelectedFilters(moveToDestination: false),
          ),
        ),
      ],
    );
  }
}

class MapArea {
  final String label;
  final LatLng center;
  final double zoom;
  final List<String> queryNames;
  final MapAreaKind kind;

  const MapArea({
    required this.label,
    required this.center,
    required this.zoom,
    required this.queryNames,
    this.kind = MapAreaKind.community,
  });
}

enum MapAreaKind { spain, community, city }

class CenterFilter {
  final String id;
  final String label;
  final String description;
  final IconData icon;

  const CenterFilter({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
  });
}

class SportsCenter {
  final int? id;
  final String sourceId;
  final String name;
  final String type;
  final String city;
  final String address;
  final String website;
  final String phone;
  final String openingHours;
  final String image;
  final LatLng location;

  const SportsCenter({
    this.id,
    required this.sourceId,
    required this.name,
    required this.type,
    required this.city,
    required this.address,
    required this.website,
    required this.phone,
    required this.openingHours,
    required this.image,
    required this.location,
  });

  String get dedupeKey {
    final lat = location.latitude.toStringAsFixed(5);
    final lng = location.longitude.toStringAsFixed(5);
    return '$sourceId|${name.toLowerCase()}|$lat|$lng';
  }

  factory SportsCenter.fromJson(Map<String, dynamic> json) {
    return SportsCenter(
      id: json['id'],
      sourceId: _readString(json['sourceId'], fallback: json['id']),
      name: _readString(json['name']),
      type: _readString(json['type'], fallback: 'Centro deportivo'),
      city: _readString(json['city']),
      address: _readString(json['address']),
      website: _readString(json['website']),
      phone: _readString(json['phone']),
      openingHours: _readString(json['openingHours']),
      image: _readString(json['image']),
      location: LatLng(
        _readDouble(json['latitude']) ?? 0,
        _readDouble(json['longitude']) ?? 0,
      ),
    );
  }

  static double? _readDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static String _readString(dynamic value, {dynamic fallback = ''}) {
    final raw = value ?? fallback;
    if (raw == null) return '';
    return raw.toString().trim();
  }
}

class _StatusPill extends StatelessWidget {
  final bool isLoading;
  final String? errorMessage;
  final int count;
  final String activePlace;
  final String centerFilterLabel;
  final VoidCallback onRetry;

  const _StatusPill({
    required this.isLoading,
    required this.errorMessage,
    required this.count,
    required this.activePlace,
    required this.centerFilterLabel,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final hasError = errorMessage != null;

    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: hasError
            ? (FeedPalette.isDark
                ? const Color(0xFF3A1F1F)
                : Colors.red.shade50)
            : FeedPalette.surface,
        borderRadius: BorderRadius.circular(12),
        elevation: 8,
        shadowColor: FeedPalette.accent.withValues(alpha: 0.15),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: hasError ? onRetry : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isLoading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(
                    hasError ? Icons.error_outline : Icons.place,
                    color: hasError ? Colors.red : FeedPalette.accent,
                    size: 18,
                  ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    isLoading
                        ? 'Buscando centros deportivos...'
                        : hasError
                            ? '$errorMessage Toca para reintentar.'
                            : '$count resultados de $centerFilterLabel en $activePlace',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: hasError
                          ? (FeedPalette.isDark
                              ? Colors.red.shade200
                              : Colors.red.shade800)
                          : FeedPalette.text,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MapFilterPanel extends StatelessWidget {
  final MapArea destination;
  final CenterFilter centerFilter;
  final bool isLoading;
  final VoidCallback onDestinationTap;
  final VoidCallback onCenterFilterTap;

  const _MapFilterPanel({
    required this.destination,
    required this.centerFilter,
    required this.isLoading,
    required this.onDestinationTap,
    required this.onCenterFilterTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: FeedPalette.surface,
      elevation: 12,
      shadowColor: FeedPalette.accent.withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: _FilterTile(
                    overline: '1. Destino',
                    title: destination.label,
                    icon: Icons.place_outlined,
                    onTap: isLoading ? null : onDestinationTap,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _FilterTile(
                    overline: '2. Centro',
                    title: centerFilter.label,
                    icon: centerFilter.icon,
                    onTap: isLoading ? null : onCenterFilterTap,
                  ),
                ),
              ],
            ),
            if (isLoading) ...[
              const SizedBox(height: 10),
              const SizedBox(height: 3, child: LinearProgressIndicator()),
            ],
          ],
        ),
      ),
    );
  }
}

class _FilterTile extends StatelessWidget {
  final String overline;
  final String title;
  final IconData icon;
  final VoidCallback? onTap;

  const _FilterTile({
    required this.overline,
    required this.title,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 74),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: FeedPalette.surfaceSoft,
          border: Border.all(color: FeedPalette.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: FeedPalette.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    overline,
                    style: TextStyle(
                      color: FeedPalette.muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: FeedPalette.text,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.keyboard_arrow_down, color: FeedPalette.muted),
          ],
        ),
      ),
    );
  }
}

class _DestinationPickerSheet extends StatefulWidget {
  final List<MapArea> destinations;
  final MapArea selectedDestination;

  const _DestinationPickerSheet({
    required this.destinations,
    required this.selectedDestination,
  });

  @override
  State<_DestinationPickerSheet> createState() =>
      _DestinationPickerSheetState();
}

class _DestinationPickerSheetState extends State<_DestinationPickerSheet> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.destinations.where((destination) {
      final q = _normalize(_query);
      if (q.isEmpty) return true;
      final label = _normalize(destination.label);
      final names = destination.queryNames.map(_normalize).join(' ');
      return label.contains(q) || names.contains(q);
    }).toList();

    return _PickerShell(
      title: 'Elige destino',
      subtitle: 'Primero selecciona la localidad, ciudad o comunidad.',
      child: Column(
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: FeedPalette.inputDecoration(
              hint: 'Busca Murcia, Madrid, Galicia...',
              icon: Icons.search,
            ).copyWith(
              isDense: true,
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.separated(
              itemCount: filtered.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final destination = filtered[index];
                final selected =
                    destination.label == widget.selectedDestination.label;
                return ListTile(
                  leading: Icon(_destinationIcon(destination.kind)),
                  title: Text(destination.label),
                  subtitle: Text(_destinationKindLabel(destination.kind)),
                  trailing: selected
                      ? Icon(Icons.check, color: FeedPalette.accent)
                      : null,
                  onTap: () => Navigator.pop(context, destination),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static IconData _destinationIcon(MapAreaKind kind) {
    return switch (kind) {
      MapAreaKind.spain => Icons.public,
      MapAreaKind.community => Icons.map_outlined,
      MapAreaKind.city => Icons.location_city,
    };
  }

  static String _destinationKindLabel(MapAreaKind kind) {
    return switch (kind) {
      MapAreaKind.spain => 'Todo el pais',
      MapAreaKind.community => 'Comunidad autonoma',
      MapAreaKind.city => 'Ciudad o localidad',
    };
  }

  static String _normalize(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll('\u00e1', 'a')
        .replaceAll('\u00e9', 'e')
        .replaceAll('\u00ed', 'i')
        .replaceAll('\u00f3', 'o')
        .replaceAll('\u00fa', 'u')
        .replaceAll('\u00fc', 'u')
        .replaceAll('\u00f1', 'n')
        .replaceAll('-', ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
  }
}

class _CenterFilterPickerSheet extends StatelessWidget {
  final List<CenterFilter> filters;
  final CenterFilter selectedFilter;

  const _CenterFilterPickerSheet({
    required this.filters,
    required this.selectedFilter,
  });

  @override
  Widget build(BuildContext context) {
    return _PickerShell(
      title: 'Elige tipo de centro',
      subtitle: 'Despues del destino, filtra por el deporte que buscas.',
      child: ListView.separated(
        itemCount: filters.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final filter = filters[index];
          final selected = filter.id == selectedFilter.id;
          return ListTile(
            leading: Icon(filter.icon, color: FeedPalette.accent),
            title: Text(filter.label),
            subtitle: Text(filter.description),
            trailing:
                selected ? Icon(Icons.check, color: FeedPalette.accent) : null,
            onTap: () => Navigator.pop(context, filter),
          );
        },
      ),
    );
  }
}

class _PickerShell extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _PickerShell({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.82,
      minChildSize: 0.45,
      maxChildSize: 0.94,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: FeedPalette.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: FeedPalette.border,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: FeedPalette.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style: TextStyle(
                          color: FeedPalette.muted,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 16),
                  Expanded(
                    child: PrimaryScrollController(
                      controller: scrollController,
                      child: child,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CustomMarker extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _CustomMarker({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: FeedPalette.surface,
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: FeedPalette.isDark ? 0.45 : 0.26,
                  ),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          Container(width: 2, height: 8, color: color),
        ],
      ),
    );
  }
}

class _CenterDetailRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _CenterDetailRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: FeedPalette.muted, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                height: 1.3,
                color: FeedPalette.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
