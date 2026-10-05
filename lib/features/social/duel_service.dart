import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../auth/auth_service.dart';
import '../../core/constants/api_constants.dart';
import '../../core/utils/profile_avatar.dart';
import '../entrenamiento/training_service.dart';

class DuelService {
  static const _storageKeyPrefix = 'fitconnect_duels_v1_';
  static const _dailySyncKeyPrefix = 'fitconnect_duel_points_synced_';

  Future<Map<String, String>> _getHeaders() async {
    final token = AuthService().token;
    return {
      'Content-Type': 'application/json; charset=UTF-8',
      'Authorization': 'Bearer $token',
    };
  }

  String _storageKey() {
    final username = AuthService().username?.trim().toLowerCase();
    return '$_storageKeyPrefix${username ?? 'guest'}';
  }

  String _dailySyncKey() {
    final username = AuthService().username?.trim().toLowerCase();
    return '$_dailySyncKeyPrefix${username ?? 'guest'}';
  }

  Map<String, dynamic> _mergeStates(
    Map<String, dynamic> local,
    Map<String, dynamic> remote,
  ) {
    final merged = Map<String, dynamic>.from(remote);
    final remoteActive = List<Map<String, dynamic>>.from(
      (remote['activeDuels'] as List?)?.cast<Map<String, dynamic>>() ?? [],
    );
    final localActive = List<Map<String, dynamic>>.from(
      (local['activeDuels'] as List?)?.cast<Map<String, dynamic>>() ?? [],
    );

    final byId = <int, Map<String, dynamic>>{};
    for (final duel in localActive) {
      final id = int.tryParse('${duel['id']}');
      if (id != null && id > 0) byId[id] = duel;
    }
    for (final duel in remoteActive) {
      final id = int.tryParse('${duel['id']}');
      if (id != null && id > 0) byId[id] = duel;
    }
    merged['activeDuels'] = byId.values.toList()
      ..sort((a, b) {
        final idB = int.tryParse('${b['id']}') ?? 0;
        final idA = int.tryParse('${a['id']}') ?? 0;
        return idB.compareTo(idA);
      });

    final remoteInvites = List<Map<String, dynamic>>.from(
      (remote['invitations'] as List?)?.cast<Map<String, dynamic>>() ?? [],
    );
    final localInvites = List<Map<String, dynamic>>.from(
      (local['invitations'] as List?)?.cast<Map<String, dynamic>>() ?? [],
    );
    final inviteIds = <int>{};
    final mergedInvites = <Map<String, dynamic>>[];
    for (final inv in [...remoteInvites, ...localInvites]) {
      final id = int.tryParse('${inv['id']}');
      if (id == null || id <= 0 || inviteIds.contains(id)) continue;
      inviteIds.add(id);
      mergedInvites.add(inv);
    }
    merged['invitations'] = mergedInvites;
    return merged;
  }

  Map<String, dynamic> _normalizeDuel(Map<String, dynamic> duel) {
    final normalized = Map<String, dynamic>.from(duel);

    if (normalized['isMulti'] == true) {
      final participants = List<String>.from(normalized['participants'] ?? []);
      final images = (normalized['participantImages'] as List?) ?? [];
      normalized['participantImages'] = [
        for (var i = 0; i < images.length; i++)
          ProfileAvatar.forPath(
            images[i]?.toString(),
            i < participants.length ? participants[i] : 'Usuario',
          ),
      ];
      return normalized;
    }

    normalized['opponentImage'] = ProfileAvatar.forPath(
      normalized['opponentImage'],
      normalized['name']?.toString() ??
          normalized['opponentUsername']?.toString() ??
          'Amigo',
    );
    return normalized;
  }

  Map<String, dynamic> normalizeDuelState(Map<String, dynamic> state) {
    final active = List<Map<String, dynamic>>.from(
      (state['activeDuels'] as List?)?.cast<Map<String, dynamic>>() ?? [],
    );
    state['activeDuels'] = active.map(_normalizeDuel).toList();
    return state;
  }

  Future<Map<String, dynamic>> loadState() async {
    final local = normalizeDuelState(await _loadLocal());
    try {
      final remote = await _fetchFromApi();
      if (remote != null) {
        final merged = normalizeDuelState(_mergeStates(local, remote));
        await _saveLocal(merged);
        try {
          await http.put(
            Uri.parse('${ApiConstants.socialBaseUrl}/duels/state'),
            headers: await _getHeaders(),
            body: json.encode(merged),
          );
        } catch (e) {
          debugPrint('DuelService.loadState sync merged: $e');
        }
        return merged;
      }
    } catch (e) {
      debugPrint('DuelService.loadState remote: $e');
    }
    return local;
  }

  Future<void> saveState(Map<String, dynamic> state) async {
    await _saveLocal(state);
    try {
      await http.put(
        Uri.parse('${ApiConstants.socialBaseUrl}/duels/state'),
        headers: await _getHeaders(),
        body: json.encode(state),
      );
    } catch (e) {
      debugPrint('DuelService.saveState remote: $e');
    }
  }

  Future<Map<String, dynamic>> _loadLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey());
    if (raw == null) {
      return _defaultState();
    }
    try {
      return Map<String, dynamic>.from(json.decode(raw) as Map);
    } catch (_) {
      return _defaultState();
    }
  }

  Future<void> _saveLocal(Map<String, dynamic> state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey(), json.encode(state));
  }

  Map<String, dynamic> _defaultState() {
    return {
      'invitations': <Map<String, dynamic>>[],
      'activeDuels': <Map<String, dynamic>>[],
      'stats': {'wins': 0, 'points': 0, 'activeCount': 0, 'rankPosition': 0},
    };
  }

  Future<Map<String, dynamic>?> _fetchFromApi() async {
    final token = AuthService().token;
    if (token == null) return null;
    final response = await http.get(
      Uri.parse('${ApiConstants.socialBaseUrl}/duels/state'),
      headers: await _getHeaders(),
    );
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(json.decode(response.body) as Map);
    }
    return null;
  }

  Future<Map<String, dynamic>> checkAndCalculateDuelPoints() async {
    try {
      final trainingService = TrainingService();
      final workout = await trainingService.getTodayWorkout();

      final now = DateTime.now();
      final todayStr =
          "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

      bool completedToday = false;
      int points = 0;

      if (workout != null && workout.isCompleted) {
        final workoutDateStr = workout.date.toIso8601String().split('T')[0];
        if (workoutDateStr == todayStr) {
          completedToday = true;
          points = 100;
        }
      }

      return {
        'points': points,
        'isCompletedToday': completedToday,
        'lastUpdate': todayStr,
      };
    } catch (e) {
      debugPrint('Error en DuelService.checkAndCalculateDuelPoints: $e');
      return {'points': 0, 'isCompletedToday': false, 'lastUpdate': null};
    }
  }

  Future<void> syncDuelPointsWithApi(int points) async {
    if (points <= 0) return;
    try {
      await http.post(
        Uri.parse('${ApiConstants.socialBaseUrl}/duels/sync-points'),
        headers: await _getHeaders(),
        body: json.encode({'points': points}),
      );
    } catch (e) {
      debugPrint('Error en syncDuelPointsWithApi: $e');
    }
    await applyTrainingPointsToDuels(points);
  }

  Future<Map<String, dynamic>> applyDailyTrainingPointsOnce() async {
    final stats = await checkAndCalculateDuelPoints();
    final isCompleted = stats['isCompletedToday'] == true;
    final points = (stats['points'] as int?) ?? 0;
    final dayKey = stats['lastUpdate']?.toString();

    if (!isCompleted || points <= 0 || dayKey == null || dayKey.isEmpty) {
      return {
        ...stats,
        'appliedNow': false,
      };
    }

    final prefs = await SharedPreferences.getInstance();
    final alreadySyncedDay = prefs.getString(_dailySyncKey());
    if (alreadySyncedDay == dayKey) {
      return {
        ...stats,
        'appliedNow': false,
      };
    }

    await syncDuelPointsWithApi(points);
    await prefs.setString(_dailySyncKey(), dayKey);
    return {
      ...stats,
      'appliedNow': true,
    };
  }

  Future<void> applyTrainingPointsToDuels(int points) async {
    if (points <= 0) return;
    final state = await loadState();
    final active = List<Map<String, dynamic>>.from(
      (state['activeDuels'] as List?)?.cast<Map<String, dynamic>>() ?? [],
    );

    var changed = false;
    for (var i = 0; i < active.length; i++) {
      final duel = Map<String, dynamic>.from(active[i]);
      if (duel['status'] != 'active') continue;

      if (duel['isMulti'] == true) {
        final scores = List<int>.from(
          (duel['scores'] as List?)?.map((e) => int.tryParse('$e') ?? 0) ?? [0],
        );
        if (scores.isNotEmpty) {
          scores[0] = points;
          duel['scores'] = scores;
          duel['myScore'] = scores[0];
          changed = true;
        }
      } else {
        duel['myScore'] = points;
        changed = true;
      }
      active[i] = duel;
    }

    if (changed) {
      final stats = Map<String, dynamic>.from(
        state['stats'] as Map? ?? {},
      );
      stats['points'] = points;
      state['activeDuels'] = active;
      state['stats'] = stats;
      await saveState(state);
    }
  }

  Future<bool> createDuel({
    required List<Map<String, dynamic>> opponents,
    required bool isMulti,
    String? title,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConstants.socialBaseUrl}/duels'),
        headers: await _getHeaders(),
        body: json.encode({
          'opponents': opponents,
          'isMulti': isMulti,
          'title': title,
        }),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return false;
      }

      final body = json.decode(response.body) as Map<String, dynamic>;
      final duelId = int.tryParse('${body['id']}');
      if (duelId != null && duelId > 0) {
        final state = await _loadLocal();
        final active = List<Map<String, dynamic>>.from(
          (state['activeDuels'] as List?)?.cast<Map<String, dynamic>>() ?? [],
        );
        active.removeWhere((d) => int.tryParse('${d['id']}') == duelId);

        if (isMulti && opponents.isNotEmpty) {
          active.insert(0, {
            'id': duelId,
            'title': title ?? 'Duelo grupal',
            'isMulti': true,
            'participants': [
              'Tú',
              ...opponents.map(
                (o) =>
                    o['displayName']?.toString() ?? o['username']?.toString(),
              ),
            ],
            'participantImages': [
              null,
              ...opponents.map(
                (o) => ProfileAvatar.forPath(
                  o['userImage'] ?? o['imagePath'] ?? o['avatar'],
                  o['displayName']?.toString() ??
                      o['username']?.toString() ??
                      'Amigo',
                ),
              ),
            ],
            'opponentUsernames': opponents
                .map((o) => o['username']?.toString())
                .where((u) => u != null && u.trim().isNotEmpty)
                .toList(),
            'scores': List.filled(opponents.length + 1, 0),
            'winningIndex': 0,
            'progress': 0.1,
            'status': 'active',
          });
        } else if (opponents.isNotEmpty) {
          final opp = opponents.first;
          active.insert(0, {
            'id': duelId,
            'name': opp['displayName']?.toString() ??
                opp['username']?.toString() ??
                'Amigo',
            'opponentUsername': opp['username']?.toString(),
            'opponentImage': ProfileAvatar.forPath(
              opp['userImage'] ?? opp['imagePath'] ?? opp['avatar'],
              opp['displayName']?.toString() ??
                  opp['username']?.toString() ??
                  'Amigo',
            ),
            'myScore': 0,
            'opponentScore': 0,
            'winning': true,
            'isMulti': false,
            'status': 'active',
          });
        }
        state['activeDuels'] = active;
        await saveState(state);
      }

      final refreshed = await _fetchFromApi();
      if (refreshed != null) {
        final local = await _loadLocal();
        final merged = _mergeStates(local, refreshed);
        await saveState(merged);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteDuel(int duelId) async {
    if (duelId <= 0) return false;
    try {
      final response = await http.delete(
        Uri.parse('${ApiConstants.socialBaseUrl}/duels/$duelId'),
        headers: await _getHeaders(),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return false;
      }

      final state = await _loadLocal();
      final active = List<Map<String, dynamic>>.from(
        (state['activeDuels'] as List?)?.cast<Map<String, dynamic>>() ?? [],
      );
      active.removeWhere((d) => int.tryParse('${d['id']}') == duelId);
      final invitations = List<Map<String, dynamic>>.from(
        (state['invitations'] as List?)?.cast<Map<String, dynamic>>() ?? [],
      );
      invitations.removeWhere((inv) => int.tryParse('${inv['id']}') == duelId);
      state['activeDuels'] = active;
      state['invitations'] = invitations;
      await saveState(state);

      final refreshed = await _fetchFromApi();
      if (refreshed != null) {
        await _saveLocal(refreshed);
      }
      return true;
    } catch (e) {
      debugPrint('DuelService.deleteDuel: $e');
      return false;
    }
  }

  Future<void> resetState() async {
    await _saveLocal(_defaultState());
    try {
      await http.delete(
        Uri.parse('${ApiConstants.socialBaseUrl}/duels/state'),
        headers: await _getHeaders(),
      );
    } catch (e) {
      debugPrint('Error reseteando estado de duelos: $e');
    }
  }

  Future<void> acceptInvitation(int invitationId) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConstants.socialBaseUrl}/duels/$invitationId/accept'),
        headers: await _getHeaders(),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final refreshed = await _fetchFromApi();
        if (refreshed != null) {
          await _saveLocal(refreshed);
        }
      }
    } catch (e) {
      debugPrint('Error accepting invitation: $e');
    }
  }

  Future<void> activateDuel(int duelId) async {
    final state = await loadState();
    final active = List<Map<String, dynamic>>.from(
      (state['activeDuels'] as List?)?.cast<Map<String, dynamic>>() ?? [],
    );
    for (var i = 0; i < active.length; i++) {
      if (active[i]['id'] == duelId) {
        active[i] = Map<String, dynamic>.from(active[i])..['status'] = 'active';
      }
    }
    state['activeDuels'] = active;
    await saveState(state);
  }
}
