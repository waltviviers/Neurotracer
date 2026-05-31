import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      home: const LogoScene(),
    );
  }
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
const double kTrapChance = 0.35;

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

enum Phase { idle, revealing, input, roundEnd, gameOver }

class _GameState {
  int lives = kStartLives;
  int score = 0;
  int rows = 1;
  int roundsCleared = 0;
  int replayTokens = 1;

  final List<int> sequence = [];
  int? trapStepIndex;
  int inputProgress = 0;

  bool gaveSecondRowLife = false;

  void resetForNewRound() {
    sequence.clear();
    trapStepIndex = null;
    inputProgress = 0;
    // replayTokens intentionally not reset — they accumulate across rounds
  }
}

class _GameSceneState extends State<GameScene> {
  final _rng = Random();
  final _state = _GameState();
  Phase _phase = Phase.idle;

  int? _flashingIndex;
  bool _isTrapFlash = false;

  int _highScore = 0;
  SharedPreferences? _prefs;

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
    });
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
      _isTrapFlash = false;
    });

    final seqLen = max(3, _state.rows + 2);
    for (int i = 0; i < seqLen; i++) {
      _state.sequence.add(_rng.nextInt(totalTiles));
    }

    if (_state.rows >= 2 && _rng.nextDouble() < kTrapChance) {
      _state.trapStepIndex = _rng.nextInt(_state.sequence.length);
    }

    await Future.delayed(const Duration(milliseconds: 350));
    await _revealSequence();
    if (!mounted) return;
    setState(() => _phase = Phase.input);
  }

  Future<void> _revealSequence() async {
    setState(() => _phase = Phase.revealing);

    for (int i = 0; i < _state.sequence.length; i++) {
      final idx = _state.sequence[i];
      final isTrap = (i == _state.trapStepIndex);

      setState(() {
        _flashingIndex = idx;
        _isTrapFlash = isTrap;
      });
      await Future.delayed(kFlashOn);

      setState(() {
        _flashingIndex = null;
        _isTrapFlash = false;
      });
      await Future.delayed(kFlashOff + kInterStepPause);
    }
  }

  void _onTilePressed(int index) {
    if (_phase != Phase.input) return;
    HapticFeedback.selectionClick();

    final trapIndex = _state.trapStepIndex == null
        ? null
        : _state.sequence[_state.trapStepIndex!];

    if (trapIndex != null && index == trapIndex) {
      _loseLife(because: 'Trap tile tapped');
      return;
    }

    int progressed = 0;
    for (int i = 0; i < _state.sequence.length; i++) {
      if (i == _state.trapStepIndex) continue;
      if (progressed == _state.inputProgress) {
        final expected = _state.sequence[i];
        if (index == expected) {
          setState(() => _state.inputProgress++);
          _pulseTile(index);
          final needed =
              _state.sequence.length - (_state.trapStepIndex == null ? 0 : 1);
          if (_state.inputProgress == needed) {
            _handleRoundCleared();
          }
        } else {
          _loseLife(because: 'Wrong tile');
        }
        return;
      } else {
        progressed++;
      }
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
      setState(() => _phase = Phase.gameOver);
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
    setState(() {
      _phase = Phase.roundEnd;
      _state.roundsCleared += 1;
      _state.score += 100 + (_state.trapStepIndex != null ? 35 : 0);
      _state.replayTokens += 1;
    });
    _updateHighScore();

    await Future.delayed(kBetweenRoundsPause);

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
      _isTrapFlash = false;
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
                          final isFlashing = _flashingIndex == index;
                          final isTrapFlashNow = isFlashing && _isTrapFlash;

                          return _TileButton(
                            index: index,
                            size: tileSize,
                            disabled: _phase != Phase.input,
                            flashing: isFlashing,
                            trapFlash: isTrapFlashNow,
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
            ),
            const SizedBox(height: 12),
            ],
          ),
          ),
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

  const _HeaderBar({
    required this.lives,
    required this.score,
    required this.rows,
    required this.roundsCleared,
    required this.phase,
    required this.highScore,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Pixel hearts
          Column(
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
                Text('$score', style: _pixel(11, color: Colors.white)),
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

class _TileButton extends StatefulWidget {
  final int index;
  final double size;
  final bool disabled;
  final bool flashing;
  final bool trapFlash;
  final VoidCallback onPressed;

  const _TileButton({
    required this.index,
    required this.size,
    required this.disabled,
    required this.flashing,
    required this.trapFlash,
    required this.onPressed,
  });

  @override
  State<_TileButton> createState() => _TileButtonState();
}

class _TileButtonState extends State<_TileButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _redFade;

  @override
  void initState() {
    super.initState();
    _redFade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
  }

  @override
  void didUpdateWidget(_TileButton old) {
    super.didUpdateWidget(old);
    if (widget.trapFlash && !old.trapFlash) {
      _redFade.forward(from: 0.0);
    } else if (!widget.trapFlash && old.trapFlash) {
      _redFade.reset();
    }
  }

  @override
  void dispose() {
    _redFade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final glyph = widget.trapFlash
        ? '☠'   // ☠ skull
        : _kGlyphs[widget.index % _kGlyphs.length];

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: widget.disabled ? null : widget.onPressed,
          child: AnimatedBuilder(
            animation: _redFade,
            builder: (context, _) {
              // Red flashes in instantly, then fades to primary blue over 240ms
              final t = _redFade.value;
              final flashColor = widget.flashing
                  ? Color.lerp(Colors.redAccent, cs.primary, t)!
                  : const Color(0xFF121416);
              final borderColor = widget.flashing
                  ? Color.lerp(Colors.redAccent, cs.primary, t)!
                      .withValues(alpha: 0.85)
                  : cs.primary.withValues(alpha: 0.25);
              final glowColor = widget.flashing
                  ? Color.lerp(Colors.redAccent, cs.primary, t)!
                      .withValues(alpha: 0.6)
                  : Colors.transparent;

              return Container(
                decoration: BoxDecoration(
                  color: flashColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: borderColor,
                    width: widget.flashing ? 2 : 1,
                  ),
                  boxShadow: [
                    if (widget.flashing)
                      BoxShadow(
                        color: glowColor,
                        blurRadius: 14,
                        spreadRadius: 2,
                      ),
                  ],
                ),
                child: Center(
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 160),
                    style: TextStyle(
                      fontSize: widget.size * 0.34,
                      fontWeight: FontWeight.bold,
                      color: widget.flashing
                          ? Colors.white
                          : Colors.cyan.withValues(alpha: 0.5),
                    ),
                    child: Text(glyph),
                  ),
                ),
              );
            },
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

  const _BottomBar({
    required this.onRestart,
    required this.onReplaySequence,
    required this.phase,
    required this.replayTokens,
  });

  @override
  Widget build(BuildContext context) {
    final isOver = phase == Phase.gameOver;
    final canReplay = replayTokens > 0;
    final label = isOver
        ? 'Restart'
        : canReplay
            ? 'Replay  [$replayTokens]'
            : 'No Replays Left';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              icon: Icon(isOver ? Icons.refresh : Icons.play_arrow),
              onPressed: (isOver || canReplay)
                  ? () {
                      if (isOver) {
                        onRestart();
                      } else {
                        HapticFeedback.selectionClick();
                        onReplaySequence();
                      }
                    }
                  : null,
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(label, style: _pixel(9)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
