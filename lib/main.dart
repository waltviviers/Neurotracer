import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:audioplayers/audioplayers.dart';

// ---------------------------------------------------------------------------
// Sound effects
// ---------------------------------------------------------------------------
class _Sfx {
  static bool muted = false;
  static final _pool = <String, AudioPlayer>{};

  static Future<void> play(String asset) async {
    if (muted) return;
    _pool[asset]?.dispose();
    final p = AudioPlayer();
    _pool[asset] = p;
    await p.play(AssetSource(asset));
  }

  static void tap()     => play('sounds/tap_correct.wav');
  static void wrong()   => play('sounds/tap_wrong.wav');
  static void clear()   => play('sounds/round_clear.wav');
  static void bonus()   => play('sounds/bonus_tap.wav');
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const NeuroTraceApp());
}

class NeuroTraceApp extends StatelessWidget {
  const NeuroTraceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NeuroTrace',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: Colors.cyan,
          secondary: Colors.amber,
        ),
        fontFamily: 'Roboto',
        useMaterial3: true,
      ),
      home: const VideoIntroScene(),
    );
  }
}

/// =============================
/// VIDEO INTRO SCENE
/// =============================

class VideoIntroScene extends StatefulWidget {
  const VideoIntroScene({super.key});
  @override
  State<VideoIntroScene> createState() => _VideoIntroSceneState();
}

class _VideoIntroSceneState extends State<VideoIntroScene> {
  VideoPlayerController? _controller;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    try {
      final ctrl = VideoPlayerController.asset('assets/videos/intro.mp4');
      await ctrl.initialize();
      if (!mounted) {
        ctrl.dispose();
        return;
      }
      setState(() => _controller = ctrl);
      ctrl.addListener(_onVideoUpdate);
      await ctrl.play();
    } catch (_) {
      _navigate();
    }
  }

  void _onVideoUpdate() {
    final ctrl = _controller;
    if (ctrl == null || _navigated) return;
    final val = ctrl.value;
    if (val.duration > Duration.zero && val.position >= val.duration) {
      _navigate();
    }
  }

  void _navigate() {
    if (_navigated) return;
    _navigated = true;
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (_, __, ___) => const CinematicScene(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _controller?.removeListener(_onVideoUpdate);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _controller;
    final ready = ctrl != null && ctrl.value.isInitialized;
    return GestureDetector(
      onTap: _navigate,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: ready
            ? Stack(
                fit: StackFit.expand,
                children: [
                  FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: ctrl.value.size.width,
                      height: ctrl.value.size.height,
                      child: VideoPlayer(ctrl),
                    ),
                  ),
                  Positioned(
                    bottom: 36,
                    right: 28,
                    child: Text(
                      'TAP TO SKIP',
                      style: TextStyle(
                        fontFamily: 'PressStart2P',
                        fontSize: 7,
                        color: Colors.white.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                ],
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}

/// =============================
/// CINEMATIC INTRO SCENE
/// =============================

class CinematicScene extends StatefulWidget {
  const CinematicScene({super.key});
  @override
  State<CinematicScene> createState() => _CinematicSceneState();
}

class _CinematicSceneState extends State<CinematicScene>
    with TickerProviderStateMixin {
  static const _lines = [
    (text: 'NEURAL LINK INITIALIZING...', color: _kCyan,   pause: 900),
    (text: 'CONNECTION ESTABLISHED',      color: _kCyan,   pause: 700),
    (text: 'MEMORY BANKS: ONLINE',        color: _kCyan,   pause: 700),
    (text: '> SCANNING NETWORK...',       color: _kCyan,   pause: 1100),
    (text: 'WARNING:',                    color: _kAmber,  pause: 300),
    (text: '1,000,000 MINDS TRAPPED IN',   color: _kAmber,  pause: 300),
    (text: 'THE GRID',                    color: _kAmber,  pause: 1000),
    (text: 'YOUR MISSION:',               color: _kAmber,  pause: 400),
    (text: 'SET THEM FREE',               color: _kAmber,  pause: 1200),
    (text: '> NEUROTRACE v1.0',           color: _kCyan,   pause: 500),
    (text: '  LOADING...',                color: _kCyan,   pause: 800),
  ];

  static const _kCyan  = Colors.cyan;
  static const _kAmber = Colors.amber;

  // chars revealed so far per line
  final List<int> _revealed = [];
  int _currentLine = 0;
  bool _skipped = false;
  Timer? _charTimer;
  Timer? _lineTimer;

  @override
  void initState() {
    super.initState();
    _revealLine(0);
  }

  void _revealLine(int lineIndex) {
    if (!mounted || lineIndex >= _lines.length) {
      _finish();
      return;
    }
    setState(() {
      _currentLine = lineIndex;
      if (_revealed.length <= lineIndex) _revealed.add(0);
    });

    final text = _lines[lineIndex].text;
    _charTimer = Timer.periodic(const Duration(milliseconds: 38), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _revealed[lineIndex]++);
      if (_revealed[lineIndex] >= text.length) {
        t.cancel();
        _lineTimer = Timer(
          Duration(milliseconds: _lines[lineIndex].pause),
          () => _revealLine(lineIndex + 1),
        );
      }
    });
  }

  void _finish() {
    if (_skipped) return;
    _skipped = true;
    _charTimer?.cancel();
    _lineTimer?.cancel();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: kSceneFade,
        pageBuilder: (_, __, ___) => const LogoScene(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _charTimer?.cancel();
    _lineTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _finish,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Subtle circuit background
            Image.asset('assets/bg_circuit.png',
                fit: BoxFit.cover,
                color: Colors.black.withValues(alpha: 0.82),
                colorBlendMode: BlendMode.darken),
            // Scanline overlay
            CustomPaint(painter: _ScanlinePainter()),
            // Text content
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 80),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (int i = 0; i < _revealed.length; i++)
                    _buildLine(i),
                  // Blinking cursor on active line
                  if (_currentLine < _lines.length)
                    _BlinkingCursor(color: _lines[_currentLine].color),
                ],
              ),
            ),
            // Skip hint
            Positioned(
              bottom: 36,
              right: 28,
              child: Text('TAP TO SKIP',
                  style: _pixel(7, color: Colors.white.withValues(alpha: 0.3))),
            ),
            const Positioned(
              bottom: 0, left: 0, right: 0,
              child: Center(child: _CreatorTag()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLine(int i) {
    final line = _lines[i];
    final chars = _revealed[i].clamp(0, line.text.length);
    final isBlank = line.text.trim().isEmpty;
    if (isBlank) return const SizedBox(height: 14);

    final isDone = chars >= line.text.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        line.text.substring(0, chars),
        style: _pixel(
          line.text.startsWith('>') ? 9 : 10,
          color: isDone
              ? line.color
              : line.color.withValues(alpha: 0.85),
        ),
      ),
    );
  }
}

class _BlinkingCursor extends StatefulWidget {
  final Color color;
  const _BlinkingCursor({required this.color});
  @override
  State<_BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<_BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _ctrl,
        child: Text('█', style: _pixel(12, color: widget.color)),
      );
}

class _ScanlinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.18)
      ..strokeWidth = 1;
    for (double y = 0; y < size.height; y += 4) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_ScanlinePainter old) => false;
}

/// =============================
/// CONFIG
/// =============================
const Color kLogoOffBlack = Color(0xFF0B0B0B);
const int kStartLives = 3;
const int kCols = 4;
const int kMaxRows = 7;
const Duration kFlashOn = Duration(milliseconds: 420);
const Duration kFlashOff = Duration(milliseconds: 180);
const Duration kInterStepPause = Duration(milliseconds: 220);
const Duration kBetweenRoundsPause = Duration(milliseconds: 600);
const Duration kSceneFade = Duration(milliseconds: 500);
const double kBonusChance = 0.30;

/// =============================
/// LOGO SCENE (Glitch → Fade Into Game)
/// =============================
class LogoScene extends StatefulWidget {
  const LogoScene({super.key});

  @override
  State<LogoScene> createState() => _LogoSceneState();
}

class _LogoSceneState extends State<LogoScene>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glitchCtrl;
  late final Animation<double> _jitter;
  late final Animation<double> _flicker;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _glitchCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _jitter = Tween<double>(begin: 6.0, end: 0.0)
        .chain(CurveTween(curve: Curves.easeOutCubic))
        .animate(_glitchCtrl);

    _flicker = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween<double>(0.0), weight: 5),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.0).chain(
          CurveTween(curve: const _SteppyFlickerCurve(repeats: 8)),
        ),
        weight: 95,
      ),
    ]).animate(_glitchCtrl);

    _glitchCtrl.forward();
    Future.delayed(const Duration(milliseconds: 1550), () async {
      if (mounted) {
        setState(() => _done = true);
        await Future.delayed(kSceneFade);
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            transitionDuration: kSceneFade,
            pageBuilder: (_, __, ___) => const GameScene(),
            transitionsBuilder: (_, anim, __, child) =>
                FadeTransition(opacity: anim, child: child),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _glitchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kLogoOffBlack,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/bg_circuit.png',
              fit: BoxFit.cover,
              color: Colors.black.withValues(alpha: 0.55),
              colorBlendMode: BlendMode.darken),
          const Positioned(
            bottom: 0, left: 0, right: 0,
            child: Center(child: _CreatorTag()),
          ),
          Center(
            child: AnimatedBuilder(
          animation: _glitchCtrl,
          builder: (context, _) {
            final j = _jitter.value;
            final r = Random(7);
            final dx = (r.nextDouble() * 2 - 1) * j;
            final dy = (r.nextDouble() * 2 - 1) * j;
            final opacity = 0.85 + 0.15 * _flicker.value;

            return AnimatedOpacity(
              opacity: _done ? 0.0 : opacity,
              duration: kSceneFade,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Transform.translate(
                    offset: Offset(dx, dy),
                    child: ColorFiltered(
                      colorFilter: const ColorFilter.mode(
                          Colors.cyan, BlendMode.modulate),
                      child: _Logo(),
                    ),
                  ),
                  Transform.translate(
                    offset: Offset(-dx, -dy),
                    child: ColorFiltered(
                      colorFilter: const ColorFilter.mode(
                          Colors.amber, BlendMode.modulate),
                      child: _Logo(),
                    ),
                  ),
                  _Logo(),
                ],
              ),
            );
          },
        ),
          ),
        ],
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final shortest = size.shortestSide;
    return Image.asset(
      'assets/logo.png',
      width: shortest * 0.7,
      fit: BoxFit.contain,
    );
  }
}

class _SteppyFlickerCurve extends Curve {
  final int repeats;
  const _SteppyFlickerCurve({this.repeats = 6});
  @override
  double transform(double t) {
    final step = (t * repeats).floor();
    return step.isEven ? 0.2 + t * 0.8 : 1.0;
  }
}

/// =============================
/// GAME SCENE
/// =============================
class GameScene extends StatefulWidget {
  const GameScene({super.key});

  @override
  State<GameScene> createState() => _GameSceneState();
}

enum Phase { idle, revealing, input, roundEnd, gameOver, win }

class _GameState {
  int lives = kStartLives;
  int score = 0;
  int rows = 1;
  int roundsCleared = 0;
  int replayTokens = 1;

  final List<int> sequence = [];
  int? bonusTileIndex;
  int inputProgress = 0;

  bool gaveSecondRowLife = false;

  void resetForNewRound() {
    sequence.clear();
    bonusTileIndex = null;
    inputProgress = 0;
    // replayTokens intentionally not reset — they accumulate across rounds
  }
}

class _GameSceneState extends State<GameScene> {
  final _rng = Random();
  final _state = _GameState();
  Phase _phase = Phase.idle;

  int? _flashingIndex;
  bool _showLoseVideo = false;
  bool _showWinVideo  = false;

  int _highScore = 0;
  SharedPreferences? _prefs;
  bool _showTutorial = false;
  bool _muted = false;
  bool _showGameOverUi = false;

  @override
  void initState() {
    super.initState();
    _loadHighScore();
    _startNewRound(initial: true);
  }

  Future<void> _loadHighScore() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _prefs = prefs;
      _highScore = prefs.getInt('highScore') ?? 0;
      _showTutorial = !(prefs.getBool('tutorialSeen') ?? false);
      _muted = prefs.getBool('muted') ?? false;
      _Sfx.muted = _muted;
    });
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    _Sfx.muted = _muted;
    _prefs?.setBool('muted', _muted);
  }

  void _dismissTutorial() {
    _prefs?.setBool('tutorialSeen', true);
    setState(() => _showTutorial = false);
  }

  void _updateHighScore() {
    if (_state.score > _highScore) {
      setState(() => _highScore = _state.score);
      _prefs?.setInt('highScore', _state.score);
    }
  }

  int get totalTiles => _state.rows * kCols;

  Future<void> _startNewRound({bool initial = false}) async {
    setState(() {
      _phase = Phase.idle;
      _state.resetForNewRound();
      _flashingIndex = null;
    });

    final seqLen = max(3, _state.rows + 2);
    for (int i = 0; i < seqLen; i++) {
      _state.sequence.add(_rng.nextInt(totalTiles));
    }

    if (_rng.nextDouble() < kBonusChance) {
      _state.bonusTileIndex = _rng.nextInt(totalTiles);
    }

    await Future.delayed(const Duration(milliseconds: 350));
    await _revealSequence();
    if (!mounted) return;
    setState(() => _phase = Phase.input);
  }

  Future<void> _revealSequence() async {
    setState(() => _phase = Phase.revealing);

    for (int i = 0; i < _state.sequence.length; i++) {
      setState(() => _flashingIndex = _state.sequence[i]);
      await Future.delayed(kFlashOn);

      setState(() => _flashingIndex = null);
      await Future.delayed(kFlashOff + kInterStepPause);
    }
  }

  void _onTilePressed(int index) {
    if (_phase != Phase.input) return;

    // Bonus tile: tapping gives +1 life
    if (_state.bonusTileIndex != null && index == _state.bonusTileIndex) {
      _Sfx.bonus();
      HapticFeedback.mediumImpact();
      setState(() {
        _state.lives += 1;
        _state.bonusTileIndex = null;
      });
    }

    final expected = _state.sequence[_state.inputProgress];
    if (index == expected) {
      HapticFeedback.selectionClick();
      _Sfx.tap();
      setState(() => _state.inputProgress++);
      _pulseTile(index);
      if (_state.inputProgress == _state.sequence.length) {
        _handleRoundCleared();
      }
    } else {
      _Sfx.wrong();
      _loseLife(because: 'Wrong tile');
    }
  }

  Future<void> _pulseTile(int index) async {
    setState(() => _flashingIndex = index);
    await Future.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;
    setState(() => _flashingIndex = null);
  }

  Future<void> _loseLife({required String because}) async {
    if (_phase == Phase.gameOver) return;
    setState(() {
      _state.lives -= 1;
    });
    await _shakeScreen();

    if (_state.lives <= 0) {
      setState(() {
        _phase = Phase.gameOver;
        _showLoseVideo = true;
      });
      _updateHighScore();
      return;
    }

    setState(() {
      _state.inputProgress = 0;
      _phase = Phase.idle;
    });
    await Future.delayed(kBetweenRoundsPause);
    if (!mounted) return;
    await _revealSequence();
    if (!mounted) return;
    setState(() => _phase = Phase.input);
  }

  Future<void> _shakeScreen() async {
    HapticFeedback.heavyImpact();
    await Future.delayed(const Duration(milliseconds: 150));
    HapticFeedback.mediumImpact();
  }

  Future<void> _handleRoundCleared() async {
    _Sfx.clear();
    setState(() {
      _phase = Phase.roundEnd;
      _state.roundsCleared += 1;
      _state.score += _state.roundsCleared == 27 ? 37038 : 37037;
      _state.replayTokens += 1;
      _state.bonusTileIndex = null;
    });
    _updateHighScore();

    await Future.delayed(kBetweenRoundsPause);

    // Win condition — all 27 rounds cleared
    if (_state.roundsCleared == 27) {
      setState(() {
        _phase = Phase.win;
        _showWinVideo = true;
      });
      return;
    }

    if (_state.roundsCleared % 3 == 0 && _state.rows < kMaxRows) {
      setState(() => _state.rows += 1);

      if (_state.rows >= 2 && !_state.gaveSecondRowLife) {
        setState(() {
          _state.lives += 1;
          _state.gaveSecondRowLife = true;
        });
      }
    }

    await _startNewRound();
  }

  void _restartGame() {
    setState(() {
      _phase = Phase.idle;
      _state.lives = kStartLives;
      _state.score = 0;
      _state.rows = 1;
      _state.roundsCleared = 0;
      _state.gaveSecondRowLife = false;
      _state.replayTokens = 1;
      _state.resetForNewRound();
      _flashingIndex = null;
      _showGameOverUi = false;
    });
    _startNewRound();
  }

  void _replaySequence() {
    if (_state.replayTokens <= 0) return;
    setState(() => _state.replayTokens--);
    _revealSequence().then((_) {
      if (mounted) setState(() => _phase = Phase.input);
    });
  }

  void _continueGame() {
    setState(() {
      _state.lives = kStartLives;
      _state.replayTokens -= 13;
      _state.inputProgress = 0;
      _phase = Phase.idle;
      _showGameOverUi = false;
    });
    _revealSequence().then((_) {
      if (mounted) setState(() => _phase = Phase.input);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0C0D),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/bg_circuit.png',
              fit: BoxFit.cover,
              color: Colors.black.withValues(alpha: 0.72),
              colorBlendMode: BlendMode.darken),
          SafeArea(
            child: Column(
          children: [
            _HeaderBar(
              lives: _state.lives,
              score: _state.score,
              rows: _state.rows,
              roundsCleared: _state.roundsCleared,
              phase: _phase,
              highScore: _highScore,
              muted: _muted,
              onMuteToggle: _toggleMute,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final gridW = constraints.maxWidth;
                  final gridH = constraints.maxHeight;
                  final tileSize = _tileSizeFor(
                    gridW: gridW,
                    gridH: gridH,
                    rows: _state.rows,
                    cols: kCols,
                  );

                  return Center(
                    child: SizedBox(
                      width: tileSize * kCols,
                      height: tileSize * _state.rows,
                      child: GridView.builder(
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: kCols,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          childAspectRatio: 1,
                        ),
                        itemCount: totalTiles,
                        itemBuilder: (context, index) {
                          return _TileButton(
                            index: index,
                            size: tileSize,
                            disabled: _phase != Phase.input,
                            flashing: _flashingIndex == index,
                            bonusTile: _state.bonusTileIndex == index,
                            onPressed: () => _onTilePressed(index),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            _BottomBar(
              onRestart: _restartGame,
              onReplaySequence: _replaySequence,
              phase: _phase,
              replayTokens: _state.replayTokens,
              score: _state.score,
            ),
            const SizedBox(height: 4),
            const _CreatorTag(),
            ],
          ),
          ),
          if (_showLoseVideo)
            _LoseVideoOverlay(
              onDone: () => setState(() {
                _showLoseVideo = false;
                _showGameOverUi = true;
              }),
            ),
          if (_showGameOverUi)
            _GameOverPanel(
              replayTokens: _state.replayTokens,
              onContinue: _continueGame,
              onQuit: _restartGame,
            ),
          if (_showWinVideo)
            _GameVideoOverlay(
              assetPath: 'assets/win.mp4',
              onDone: () => setState(() => _showWinVideo = false),
            ),
          if (_showTutorial)
            _TutorialOverlay(onDismiss: _dismissTutorial),
        ],
      ),
    );
  }

  double _tileSizeFor({
    required double gridW,
    required double gridH,
    required int rows,
    required int cols,
  }) {
    final gapsW = (cols - 1) * 8.0;
    final gapsH = (rows - 1) * 8.0;
    final maxTileW = (gridW - gapsW) / cols;
    final maxTileH = (gridH - gapsH) / rows;
    return min(maxTileW, maxTileH).clamp(32.0, 120.0);
  }
}

/// =============================
/// GAME VIDEO OVERLAY (lose / win)
/// =============================

class _LoseVideoOverlay extends _GameVideoOverlay {
  const _LoseVideoOverlay({required super.onDone})
      : super(assetPath: 'assets/lose.mp4');
}

class _GameVideoOverlay extends StatefulWidget {
  final String assetPath;
  final VoidCallback onDone;
  const _GameVideoOverlay({required this.assetPath, required this.onDone});
  @override
  State<_GameVideoOverlay> createState() => _GameVideoOverlayState();
}

class _GameVideoOverlayState extends State<_GameVideoOverlay> {
  VideoPlayerController? _ctrl;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    try {
      final ctrl = VideoPlayerController.asset(widget.assetPath);
      await ctrl.initialize();
      if (!mounted) { ctrl.dispose(); return; }
      setState(() => _ctrl = ctrl);
      ctrl.addListener(_onUpdate);
      await ctrl.play();
    } catch (_) {
      _finish();
    }
  }

  void _onUpdate() {
    final ctrl = _ctrl;
    if (ctrl == null || _done) return;
    final v = ctrl.value;
    if (v.duration > Duration.zero && v.position >= v.duration) _finish();
  }

  void _finish() {
    if (_done) return;
    _done = true;
    if (mounted) widget.onDone();
  }

  @override
  void dispose() {
    _ctrl?.removeListener(_onUpdate);
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _ctrl;
    final ready = ctrl != null && ctrl.value.isInitialized;
    return GestureDetector(
      onTap: _finish,
      child: Container(
        color: Colors.black,
        child: ready
            ? Stack(
                fit: StackFit.expand,
                children: [
                  FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: ctrl.value.size.width,
                      height: ctrl.value.size.height,
                      child: VideoPlayer(ctrl),
                    ),
                  ),
                  Positioned(
                    bottom: 36,
                    right: 28,
                    child: Text('TAP TO SKIP',
                        style: _pixel(7,
                            color: Colors.white.withValues(alpha: 0.3))),
                  ),
                ],
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}

/// =============================
/// UI COMPONENTS
/// =============================

TextStyle _pixel(double size, {Color? color, FontWeight weight = FontWeight.normal}) =>
    TextStyle(fontFamily: 'PressStart2P', fontSize: size, color: color, fontWeight: weight);

const _kGlyphs = [
  'Ω', 'Σ', 'Φ', 'Δ', 'Λ', 'Ψ', 'Θ', 'Π',
  '0x', 'FF', '4A', 'C3', 'B7', 'E9', '1F', '8D',
  '#!', '@0', '%F', '&A', '??', '!!', '/*', '//',
];

class _PixelHeartPainter extends CustomPainter {
  final Color color;
  const _PixelHeartPainter({required this.color});

  static const _grid = [
    [0, 1, 1, 0, 1, 1, 0],
    [1, 1, 1, 1, 1, 1, 1],
    [1, 1, 1, 1, 1, 1, 1],
    [0, 1, 1, 1, 1, 1, 0],
    [0, 0, 1, 1, 1, 0, 0],
    [0, 0, 0, 1, 0, 0, 0],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final pw = size.width / _grid[0].length;
    final ph = size.height / _grid.length;
    for (int r = 0; r < _grid.length; r++) {
      for (int c = 0; c < _grid[r].length; c++) {
        if (_grid[r][c] == 1) {
          canvas.drawRect(Rect.fromLTWH(c * pw, r * ph, pw, ph), paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_PixelHeartPainter old) => old.color != color;
}
class _HeaderBar extends StatelessWidget {
  final int lives;
  final int score;
  final int rows;
  final int roundsCleared;
  final Phase phase;
  final int highScore;
  final bool muted;
  final VoidCallback onMuteToggle;

  const _HeaderBar({
    required this.lives,
    required this.score,
    required this.rows,
    required this.roundsCleared,
    required this.phase,
    required this.highScore,
    required this.muted,
    required this.onMuteToggle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Pixel hearts + mute toggle
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: List.generate(
                  max(0, lives),
                  (_) => Padding(
                    padding: const EdgeInsets.only(right: 6.0),
                    child: SizedBox(
                      width: 16,
                      height: 14,
                      child: CustomPaint(
                        painter: _PixelHeartPainter(color: Colors.yellow),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: onMuteToggle,
                child: Icon(
                  muted ? Icons.volume_off : Icons.volume_up,
                  color: Colors.cyan.withValues(alpha: 0.55),
                  size: 18,
                ),
              ),
            ],
          ),
          const Spacer(),
          // Right-side stats block
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('SERVERS: $rows', style: _pixel(7, color: Colors.cyan)),
                const SizedBox(height: 4),
                Text('MINDS RELEASED: $roundsCleared',
                    style: _pixel(7, color: Colors.cyan)),
                const SizedBox(height: 6),
                Text('MOST SOULS SET FREE:', style: _pixel(6, color: cs.primary)),
                const SizedBox(height: 2),
                TweenAnimationBuilder<int>(
                  tween: IntTween(begin: 0, end: score),
                  duration: const Duration(milliseconds: 450),
                  builder: (_, v, __) => Text('$v', style: _pixel(11, color: Colors.white)),
                ),
                if (highScore > 0) ...[
                  const SizedBox(height: 3),
                  Text('BEST: $highScore',
                      style: _pixel(7, color: Colors.amber)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TileButton extends StatelessWidget {
  final int index;
  final double size;
  final bool disabled;
  final bool flashing;
  final bool bonusTile;
  final VoidCallback onPressed;

  const _TileButton({
    required this.index,
    required this.size,
    required this.disabled,
    required this.flashing,
    required this.bonusTile,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final glyph = bonusTile ? '' : _kGlyphs[index % _kGlyphs.length];

    Color bgColor;
    Color borderColor;
    Color glowColor;
    Color glyphColor;

    if (bonusTile && !flashing) {
      bgColor     = const Color(0xFF1A0A00);
      borderColor = Colors.orange.withValues(alpha: 0.7);
      glowColor   = Colors.orange.withValues(alpha: 0.25);
      glyphColor  = Colors.orange;
    } else if (flashing) {
      bgColor     = Colors.cyan;
      borderColor = Colors.cyan.withValues(alpha: 0.85);
      glowColor   = Colors.cyan.withValues(alpha: 0.6);
      glyphColor  = Colors.white;
    } else {
      bgColor     = const Color(0xFF121416);
      borderColor = cs.primary.withValues(alpha: 0.25);
      glowColor   = Colors.transparent;
      glyphColor  = Colors.cyan.withValues(alpha: 0.5);
    }

    return SizedBox(
      width: size,
      height: size,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: disabled ? null : onPressed,
          child: Container(
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: borderColor,
                width: (flashing || bonusTile) ? 2 : 1,
              ),
              boxShadow: [
                if (flashing || bonusTile)
                  BoxShadow(
                    color: glowColor,
                    blurRadius: 14,
                    spreadRadius: 2,
                  ),
              ],
            ),
            child: Center(
              child: bonusTile && !flashing
                  ? SizedBox(
                      width: size * 0.42,
                      height: size * 0.36,
                      child: const CustomPaint(
                        painter: _PixelHeartPainter(color: Colors.yellow),
                      ),
                    )
                  : AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 160),
                      style: TextStyle(
                        fontSize: size * 0.34,
                        fontWeight: FontWeight.bold,
                        color: glyphColor,
                      ),
                      child: Text(glyph),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final VoidCallback onRestart;
  final VoidCallback onReplaySequence;
  final Phase phase;
  final int replayTokens;
  final int score;

  const _BottomBar({
    required this.onRestart,
    required this.onReplaySequence,
    required this.phase,
    required this.replayTokens,
    required this.score,
  });

  @override
  Widget build(BuildContext context) {
    final isWin = phase == Phase.win;
    final canReplay = phase != Phase.gameOver && phase != Phase.win && replayTokens > 0;

    if (isWin) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.refresh),
                onPressed: onRestart,
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('PLAY AGAIN'),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.copy),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(
                    text: 'I freed $score souls in Neurotracer! Can you beat me? 🤖⚡',
                  ));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Score copied to clipboard!', style: _pixel(7)),
                        duration: const Duration(seconds: 2),
                        backgroundColor: const Color(0xFF1A1C1E),
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber.withValues(alpha: 0.12),
                  side: const BorderSide(color: Colors.amber),
                ),
                label: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text('COPY SCORE', style: _pixel(9, color: Colors.amber)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text('MORE CONTENT COMING SOON', style: _pixel(7, color: Colors.amber)),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          icon: const Icon(Icons.play_arrow),
          onPressed: canReplay
              ? () {
                  HapticFeedback.selectionClick();
                  onReplaySequence();
                }
              : null,
          label: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              canReplay ? 'REPLAY  [$replayTokens]' : 'NO REPLAYS LEFT',
              style: _pixel(9),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Game over panel — shown after lose video finishes
// ---------------------------------------------------------------------------
class _GameOverPanel extends StatefulWidget {
  final int replayTokens;
  final VoidCallback onContinue;
  final VoidCallback onQuit;

  const _GameOverPanel({
    required this.replayTokens,
    required this.onContinue,
    required this.onQuit,
  });

  @override
  State<_GameOverPanel> createState() => _GameOverPanelState();
}

class _GameOverPanelState extends State<_GameOverPanel> {
  bool _showError = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.88),
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('GAME OVER', style: _pixel(18, color: Colors.cyan)),
            const SizedBox(height: 12),
            Text(
              '${widget.replayTokens} / 13 TOKENS',
              style: _pixel(9, color: Colors.amber),
            ),
            const SizedBox(height: 48),
            if (_showError) ...[
              Text(
                '13 REPLAY TOKENS\nREQUIRED',
                textAlign: TextAlign.center,
                style: _pixel(10, color: Colors.redAccent),
              ),
            ] else ...[
              _panelButton(
                label: 'CONTINUE',
                color: Colors.amber,
                onTap: () async {
                  HapticFeedback.heavyImpact();
                  if (widget.replayTokens >= 13) {
                    widget.onContinue();
                  } else {
                    setState(() => _showError = true);
                    await Future.delayed(const Duration(milliseconds: 1800));
                    if (mounted) widget.onQuit();
                  }
                },
              ),
              const SizedBox(height: 16),
              _panelButton(
                label: 'QUIT',
                color: Colors.cyan,
                onTap: () {
                  HapticFeedback.selectionClick();
                  widget.onQuit();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _panelButton({
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: color.withValues(alpha: 0.14),
            side: BorderSide(color: color),
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: Text(label, style: _pixel(11, color: color)),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tutorial overlay — shown once on first launch
// ---------------------------------------------------------------------------
class _TutorialOverlay extends StatefulWidget {
  final VoidCallback onDismiss;
  const _TutorialOverlay({required this.onDismiss});

  @override
  State<_TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<_TutorialOverlay> {
  int _page = 0;

  static const _pages = [
    _TutPage(
      title: 'MEMORIZE',
      body: 'Watch the tiles light up\nin order. Remember\nthe sequence.',
      icon: Icons.visibility,
    ),
    _TutPage(
      title: 'REPLAY IT',
      body: 'Tap the tiles back\nin the exact same order\nbefore time runs out.',
      icon: Icons.touch_app,
    ),
    _TutPage(
      title: 'BONUS TILE',
      body: 'Spot the orange tile\nwith the yellow heart.\nTap it to gain a life.',
      icon: Icons.favorite,
      iconColor: Colors.orange,
    ),
    _TutPage(
      title: 'REPLAY TOKENS',
      body: 'Earn a token each round.\nWatch the sequence again\nor save 13 to continue.',
      icon: Icons.bolt,
      iconColor: Colors.amber,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final page = _pages[_page];
    final isLast = _page == _pages.length - 1;

    return Container(
      color: Colors.black.withValues(alpha: 0.92),
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(page.icon, color: page.iconColor, size: 48),
            const SizedBox(height: 24),
            Text(page.title, style: _pixel(14, color: Colors.cyan)),
            const SizedBox(height: 20),
            Text(
              page.body,
              textAlign: TextAlign.center,
              style: _pixel(8, color: Colors.white.withValues(alpha: 0.85)),
            ),
            const SizedBox(height: 40),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_pages.length, (i) => Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: i == _page ? 18 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: i == _page ? Colors.cyan : Colors.white24,
                  borderRadius: BorderRadius.circular(4),
                ),
              )),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: 200,
              child: ElevatedButton(
                onPressed: () {
                  HapticFeedback.selectionClick();
                  if (isLast) {
                    widget.onDismiss();
                  } else {
                    setState(() => _page++);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyan.withValues(alpha: 0.15),
                  side: const BorderSide(color: Colors.cyan),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(
                  isLast ? "LET'S GO" : 'NEXT',
                  style: _pixel(10, color: Colors.cyan),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TutPage {
  final String title;
  final String body;
  final IconData icon;
  final Color iconColor;
  const _TutPage({
    required this.title,
    required this.body,
    required this.icon,
    this.iconColor = Colors.cyan,
  });
}

class _CreatorTag extends StatelessWidget {
  const _CreatorTag();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => launchUrl(
        Uri.parse('https://www.instagram.com/waltviviers'),
        mode: LaunchMode.externalApplication,
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          'created by @waltviviers',
          style: _pixel(6, color: Colors.white.withValues(alpha: 0.30)),
        ),
      ),
    );
  }
}
