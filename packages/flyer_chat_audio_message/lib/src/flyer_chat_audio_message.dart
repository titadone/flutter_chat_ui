import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;

/// Theme values for [FlyerChatAudioMessage].
typedef _LocalTheme = ({
  TextStyle bodyMedium,
  TextStyle labelSmall,
  Color onPrimary,
  Color onSurface,
  Color primary,
  BorderRadiusGeometry shape,
  Color surfaceContainer,
});

/// A widget that displays an audio message with play/pause controls and waveform visualization.
///
/// Uses [AudioPlayer] from just_audio for audio playback.
/// Supports waveform visualization and interactive seeking.
class FlyerChatAudioMessage extends StatefulWidget {
  /// The audio message data model.
  final AudioMessage message;

  /// The index of the message in the list.
  final int index;

  /// Padding around the message bubble content.
  final EdgeInsetsGeometry? padding;

  /// Border radius of the message bubble.
  final BorderRadiusGeometry? borderRadius;

  /// Box constraints for the message bubble.
  final BoxConstraints? constraints;

  /// Background color for messages sent by the current user.
  final Color? sentBackgroundColor;

  /// Background color for messages received from other users.
  final Color? receivedBackgroundColor;

  /// Color of the play/pause button for sent messages.
  final Color? sentButtonColor;

  /// Color of the play/pause button for received messages.
  final Color? receivedButtonColor;

  /// Color of the active (played) portion of the waveform for sent messages.
  final Color? sentWaveformActiveColor;

  /// Color of the inactive (unplayed) portion of the waveform for sent messages.
  final Color? sentWaveformInactiveColor;

  /// Color of the active (played) portion of the waveform for received messages.
  final Color? receivedWaveformActiveColor;

  /// Color of the inactive (unplayed) portion of the waveform for received messages.
  final Color? receivedWaveformInactiveColor;

  /// Text style for the message timestamp and status.
  final TextStyle? timeStyle;

  /// Whether to display the message timestamp.
  final bool showTime;

  /// Whether to display the message status (sent, delivered, seen) for sent messages.
  final bool showStatus;

  /// Position of the timestamp and status indicator relative to the audio.
  final TimeAndStatusPosition timeAndStatusPosition;

  /// Optional HTTP headers for authenticated audio requests.
  final Map<String, String>? headers;

  /// The widget to display on top of the message.
  final Widget? topWidget;

  /// Whether to show the download button.
  final bool showDownloadButton;

  /// Callback when download is completed.
  final Function(String filePath)? onDownloadComplete;

  /// Callback when download fails.
  final Function(String error)? onDownloadError;

  /// Creates a widget to display an audio message.
  const FlyerChatAudioMessage({
    super.key,
    required this.message,
    required this.index,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    this.borderRadius,
    this.constraints,
    this.sentBackgroundColor,
    this.receivedBackgroundColor,
    this.sentButtonColor,
    this.receivedButtonColor,
    this.sentWaveformActiveColor,
    this.sentWaveformInactiveColor,
    this.receivedWaveformActiveColor,
    this.receivedWaveformInactiveColor,
    this.timeStyle,
    this.showTime = true,
    this.showStatus = true,
    this.timeAndStatusPosition = TimeAndStatusPosition.end,
    this.headers,
    this.topWidget,
    this.showDownloadButton = true,
    this.onDownloadComplete,
    this.onDownloadError,
  });

  @override
  State<FlyerChatAudioMessage> createState() => _FlyerChatAudioMessageState();
}

class _FlyerChatAudioMessageState extends State<FlyerChatAudioMessage>
    with TickerProviderStateMixin {
  late final AudioPlayer _audioPlayer;
  late final StreamSubscription<Duration> _positionSubscription;
  late final StreamSubscription<PlayerState> _playerStateSubscription;

  bool _isPlaying = false;
  bool _isLoading = false;
  bool _isDownloading = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _duration = widget.message.duration;
    _setupAudioPlayer();
  }

  void _setupAudioPlayer() {
    // Configure audio player to reduce crackling
    _audioPlayer.setAudioSource(
      AudioSource.uri(Uri.parse('')),
      preload: false,
    );

    // Listen to position changes
    _positionSubscription = _audioPlayer.positionStream.listen((position) {
      if (mounted) {
        setState(() => _position = position);
      }
    });

    // Listen to player state changes
    _playerStateSubscription = _audioPlayer.playerStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state.playing;
          _isLoading = state.processingState == ProcessingState.loading ||
              state.processingState == ProcessingState.buffering;
        });

        // Update duration when available
        if (_audioPlayer.duration != null && _duration != _audioPlayer.duration!) {
          setState(() {
            _duration = _audioPlayer.duration!;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _positionSubscription.cancel();
    _playerStateSubscription.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _togglePlayPause() async {
    try {
      if (_isPlaying) {
        await _audioPlayer.pause();
      } else {
        if (_audioPlayer.processingState == ProcessingState.idle) {
          // Add a small delay to prevent crackling
          await _audioPlayer.setUrl(
            widget.message.source,
            headers: widget.headers,
          );
          // Wait a bit for the audio to be ready
          await Future.delayed(const Duration(milliseconds: 100));
        }
        await _audioPlayer.play();
      }
    } catch (e) {
      // Handle error - could show a snackbar or error state
      debugPrint('Error playing audio: $e');
    }
  }

  Future<void> _seekTo(Duration position) async {
    try {
      await _audioPlayer.seek(position);
    } catch (e) {
      debugPrint('Error seeking audio: $e');
    }
  }

  Future<void> _downloadAudio() async {
    if (_isDownloading) return;

    setState(() => _isDownloading = true);

    try {
      // Request storage permission
      final status = await Permission.storage.request();
      if (!status.isGranted) {
        widget.onDownloadError?.call('Permission de stockage refusée');
        return;
      }

      // Get download directory
      Directory? directory;
      if (Platform.isAndroid) {
        directory = await getExternalStorageDirectory();
      } else {
        directory = await getApplicationDocumentsDirectory();
      }

      if (directory == null) {
        widget.onDownloadError?.call('Impossible d\'accéder au répertoire de téléchargement');
        return;
      }

      // Create filename
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filename = 'audio_$timestamp.${_getFileExtension(widget.message.source)}';
      final filePath = '${directory.path}/$filename';

      // Download file
      final response = await http.get(
        Uri.parse(widget.message.source),
        headers: widget.headers,
      );

      if (response.statusCode == 200) {
        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);
        widget.onDownloadComplete?.call(filePath);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Audio téléchargé avec succès'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        widget.onDownloadError?.call('Erreur de téléchargement: ${response.statusCode}');
      }
    } catch (e) {
      widget.onDownloadError?.call('Erreur: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur de téléchargement: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isDownloading = false);
      }
    }
  }

  String _getFileExtension(String url) {
    final uri = Uri.parse(url);
    final path = uri.path;
    final lastDot = path.lastIndexOf('.');
    if (lastDot != -1 && lastDot < path.length - 1) {
      return path.substring(lastDot + 1);
    }
    return 'mp3'; // Default extension
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.select(
      (ChatTheme t) => (
        bodyMedium: t.typography.bodyMedium,
        labelSmall: t.typography.labelSmall,
        onPrimary: t.colors.onPrimary,
        onSurface: t.colors.onSurface,
        primary: t.colors.primary,
        shape: t.shape,
        surfaceContainer: t.colors.surfaceContainer,
      ),
    );
    final isSentByMe = context.read<UserID>() == widget.message.authorId;

    final timeAndStatus = widget.showTime || (isSentByMe && widget.showStatus)
        ? TimeAndStatus(
            time: widget.message.resolvedTime,
            status: widget.message.resolvedStatus,
            showTime: widget.showTime,
            showStatus: isSentByMe && widget.showStatus,
            textStyle: _resolveTimeStyle(isSentByMe, theme),
          )
        : null;

    return ClipRRect(
      borderRadius: widget.borderRadius ?? theme.shape,
      child: Container(
        constraints: widget.constraints,
        decoration: BoxDecoration(
          color: _resolveBackgroundColor(isSentByMe, theme),
        ),
        child: Padding(
          padding: widget.padding ?? EdgeInsets.zero,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.topWidget != null) widget.topWidget!,
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildPlayPauseButton(isSentByMe, theme),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildWaveform(isSentByMe, theme),
                        const SizedBox(height: 4),
                        _buildTimeAndStatus(timeAndStatus),
                      ],
                    ),
                  ),
                  if (widget.showDownloadButton) ...[
                    const SizedBox(width: 8),
                    _buildDownloadButton(isSentByMe, theme),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlayPauseButton(bool isSentByMe, _LocalTheme theme) {
    final buttonColor = isSentByMe
        ? (widget.sentButtonColor ?? theme.onPrimary)
        : (widget.receivedButtonColor ?? theme.onSurface);

    return GestureDetector(
      onTap: _togglePlayPause,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: buttonColor.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(
          _getPlayPauseIcon(),
          color: buttonColor,
          size: 20,
        ),
      ),
    );
  }

  Widget _buildWaveform(bool isSentByMe, _LocalTheme theme) {
    final activeColor = isSentByMe
        ? (widget.sentWaveformActiveColor ?? theme.onPrimary)
        : (widget.receivedWaveformActiveColor ?? theme.onSurface);

    final inactiveColor = isSentByMe
        ? (widget.sentWaveformInactiveColor ?? theme.onPrimary.withOpacity(0.3))
        : (widget.receivedWaveformInactiveColor ?? theme.onSurface.withOpacity(0.3));

    return SizedBox(
      height: 32,
      child: WaveformWidget(
        waveformData: widget.message.waveform,
        duration: _duration,
        position: _position,
        activeColor: activeColor,
        inactiveColor: inactiveColor,
        onSeek: _seekTo,
      ),
    );
  }

  Widget _buildTimeAndStatus(TimeAndStatus? timeAndStatus) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          _formatDurationWithTotal(_position, _duration),
          style: widget.timeStyle,
        ),
        if (timeAndStatus != null) timeAndStatus,
      ],
    );
  }

  Widget _buildDownloadButton(bool isSentByMe, _LocalTheme theme) {
    final buttonColor = isSentByMe
        ? (widget.sentButtonColor ?? theme.onPrimary)
        : (widget.receivedButtonColor ?? theme.onSurface);

    return GestureDetector(
      onTap: _isDownloading ? null : _downloadAudio,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: buttonColor.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: _isDownloading
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  color: buttonColor,
                  strokeWidth: 2,
                ),
              )
            : Icon(
                Icons.download,
                color: buttonColor,
                size: 16,
              ),
      ),
    );
  }

  IconData _getPlayPauseIcon() {
    if (_isLoading) return Icons.hourglass_empty;
    if (_isPlaying) return Icons.pause;
    return Icons.play_arrow;
  }

  Color _resolveBackgroundColor(bool isSentByMe, _LocalTheme theme) {
    if (isSentByMe) {
      return widget.sentBackgroundColor ?? theme.primary;
    }
    return widget.receivedBackgroundColor ?? theme.surfaceContainer;
  }

  TextStyle _resolveTimeStyle(bool isSentByMe, _LocalTheme theme) {
    if (widget.timeStyle != null) return widget.timeStyle!;

    if (isSentByMe) {
      return theme.labelSmall.copyWith(color: theme.onPrimary.withOpacity(0.8));
    }
    return theme.labelSmall.copyWith(color: theme.onSurface.withOpacity(0.8));
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(1, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatDurationWithTotal(Duration position, Duration total) {
    final positionStr = _formatDuration(position);
    final totalStr = _formatDuration(total);
    return '$positionStr / $totalStr';
  }
}

/// A widget that displays an interactive waveform visualization.
class WaveformWidget extends StatelessWidget {
  /// The waveform data as a list of amplitude values (0.0 to 1.0).
  final List<double>? waveformData;

  /// The total duration of the audio.
  final Duration duration;

  /// The current playback position.
  final Duration position;

  /// Color for the played portion of the waveform.
  final Color activeColor;

  /// Color for the unplayed portion of the waveform.
  final Color inactiveColor;

  /// Callback when user taps on the waveform to seek.
  final Function(Duration) onSeek;

  const WaveformWidget({
    super.key,
    required this.waveformData,
    required this.duration,
    required this.position,
    required this.activeColor,
    required this.inactiveColor,
    required this.onSeek,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (details) => _handleTap(details, context),
      child: CustomPaint(
        painter: WaveformPainter(
          waveformData: waveformData,
          progress: duration.inMilliseconds > 0
              ? position.inMilliseconds / duration.inMilliseconds
              : 0.0,
          activeColor: activeColor,
          inactiveColor: inactiveColor,
        ),
        child: Container(),
      ),
    );
  }

  void _handleTap(TapDownDetails details, BuildContext context) {
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final localPosition = details.localPosition;
    final progress = localPosition.dx / renderBox.size.width;
    final seekPosition = Duration(
      milliseconds: (duration.inMilliseconds * progress.clamp(0.0, 1.0)).round(),
    );
    onSeek(seekPosition);
  }
}

/// Custom painter for drawing the waveform visualization.
class WaveformPainter extends CustomPainter {
  final List<double>? waveformData;
  final double progress;
  final Color activeColor;
  final Color inactiveColor;

  const WaveformPainter({
    required this.waveformData,
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (waveformData == null || waveformData!.isEmpty) {
      _drawDefaultWaveform(canvas, size);
      return;
    }

    _drawWaveform(canvas, size);
  }

  void _drawDefaultWaveform(Canvas canvas, Size size) {
    final paint = Paint()..strokeWidth = 2.0;
    final barCount = 30;
    final barWidth = size.width / barCount;
    final progressX = size.width * progress;

    for (int i = 0; i < barCount; i++) {
      final x = i * barWidth;
      final height = (math.sin(i * 0.5) * 0.5 + 0.5) * size.height * 0.8;
      final y = (size.height - height) / 2;

      paint.color = x <= progressX ? activeColor : inactiveColor;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barWidth - 2, height),
          const Radius.circular(1),
        ),
        paint,
      );
    }
  }

  void _drawWaveform(Canvas canvas, Size size) {
    final paint = Paint()..strokeWidth = 2.0;
    final barWidth = size.width / waveformData!.length;
    final progressX = size.width * progress;

    for (int i = 0; i < waveformData!.length; i++) {
      final x = i * barWidth;
      final normalizedHeight = waveformData![i].clamp(0.0, 1.0);
      final height = normalizedHeight * size.height * 0.8;
      final y = (size.height - height) / 2;

      paint.color = x <= progressX ? activeColor : inactiveColor;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barWidth - 2, height),
          const Radius.circular(1),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.waveformData != waveformData ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor;
  }
}

/// A widget to display the message timestamp and status indicator.
class TimeAndStatus extends StatelessWidget {
  /// The time the message was created.
  final DateTime? time;

  /// The status of the message.
  final MessageStatus? status;

  /// Whether to display the timestamp.
  final bool showTime;

  /// Whether to display the status indicator.
  final bool showStatus;

  /// The text style for the time and status.
  final TextStyle? textStyle;

  /// Creates a widget for displaying time and status.
  const TimeAndStatus({
    super.key,
    required this.time,
    this.status,
    this.showTime = true,
    this.showStatus = true,
    this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    final timeFormat = context.watch<DateFormat>();

    return Row(
      spacing: 2,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showTime && time != null)
          Text(timeFormat.format(time!.toLocal()), style: textStyle),
        if (showStatus && status != null)
          if (status == MessageStatus.sending)
            SizedBox(
              width: 6,
              height: 6,
              child: CircularProgressIndicator(
                color: textStyle?.color,
                strokeWidth: 2,
              ),
            )
          else
            Icon(getIconForStatus(status!), color: textStyle?.color, size: 12),
      ],
    );
  }
}
