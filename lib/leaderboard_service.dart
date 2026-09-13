import 'dart:async';
import 'dart:math';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LeaderboardEntry {
  final String playerName;
  final int score;
  final int rank;
  final DateTime submittedAt;
  final bool isCurrentPlayer;

  LeaderboardEntry({
    required this.playerName,
    required this.score,
    required this.rank,
    required this.submittedAt,
    this.isCurrentPlayer = false,
  });

  factory LeaderboardEntry.fromMap(Map<dynamic, dynamic> map, int rank, {bool isCurrentPlayer = false}) {
    return LeaderboardEntry(
      playerName: map['playerName'] ?? 'Anonymous',
      score: map['score'] ?? 0,
      rank: rank,
      submittedAt: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] ?? 0),
      isCurrentPlayer: isCurrentPlayer,
    );
  }
}

class LeaderboardService {
  static final LeaderboardService _instance = LeaderboardService._internal();
  static const String _playerNameKey = 'leaderboardPlayerName';
  static const String _leaderboardPath = 'leaderboard';
  static const int _topScoresLimit = 50;

  late FirebaseDatabase _db;
  late SharedPreferences _prefs;
  String? _playerName;

  factory LeaderboardService() {
    return _instance;
  }

  LeaderboardService._internal();

  Future<void> init(SharedPreferences prefs) async {
    _prefs = prefs;
    _db = FirebaseDatabase.instance;
    _playerName = _prefs.getString(_playerNameKey);
    if (_playerName == null) {
      _playerName = _generateAnonymousName();
      _prefs.setString(_playerNameKey, _playerName!);
    }
  }

  String get playerName => _playerName ?? 'Anonymous';

  void setPlayerName(String name) {
    _playerName = name.isEmpty ? _generateAnonymousName() : name;
    _prefs.setString(_playerNameKey, _playerName!);
  }

  Future<void> submitScore(int score) async {
    try {
      final now = DateTime.now();
      final entryId = '${now.millisecondsSinceEpoch}_${_playerName!.hashCode}';

      await _db.ref(_leaderboardPath).child(entryId).set({
        'playerName': _playerName,
        'score': score,
        'timestamp': now.millisecondsSinceEpoch,
      });
    } catch (e) {
      // Silently fail - leaderboard not critical to gameplay
    }
  }

  Future<List<LeaderboardEntry>> fetchTopScores() async {
    try {
      final snapshot = await _db
          .ref(_leaderboardPath)
          .orderByChild('score')
          .limitToLast(_topScoresLimit)
          .get();

      if (!snapshot.exists) return [];

      final scores = <LeaderboardEntry>[];
      final entries = snapshot.value as Map<dynamic, dynamic>;

      // Sort by score descending
      final sortedEntries = entries.entries.toList();
      sortedEntries.sort((a, b) => (b.value['score'] ?? 0).compareTo(a.value['score'] ?? 0));

      for (int i = 0; i < sortedEntries.length; i++) {
        final entry = sortedEntries[i].value as Map<dynamic, dynamic>;
        scores.add(LeaderboardEntry.fromMap(
          entry,
          i + 1,
          isCurrentPlayer: entry['playerName'] == _playerName,
        ));
      }

      return scores;
    } catch (e) {
      return [];
    }
  }

  Future<LeaderboardEntry?> getPlayerRank(int score) async {
    try {
      final allScores = await fetchTopScores();
      final playerEntry = allScores.firstWhere(
        (entry) => entry.isCurrentPlayer,
        orElse: () => LeaderboardEntry(
          playerName: _playerName!,
          score: score,
          rank: allScores.length + 1,
          submittedAt: DateTime.now(),
          isCurrentPlayer: true,
        ),
      );
      return playerEntry;
    } catch (e) {
      return null;
    }
  }

  String _generateAnonymousName() {
    const adjectives = ['Cyber', 'Neon', 'Pixel', 'Volt', 'Sync', 'Glitch'];
    const nouns = ['Ghost', 'Runner', 'Hacker', 'Echo', 'Pulse', 'Nova'];
    final random = Random();
    final adj = adjectives[random.nextInt(adjectives.length)];
    final noun = nouns[random.nextInt(nouns.length)];
    final num = random.nextInt(999);
    return '$adj$noun$num';
  }
}
