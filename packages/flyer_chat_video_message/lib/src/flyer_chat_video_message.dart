import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

/// Theme values for [FlyerChatVideoMessage].
typedef _LocalTheme = ({
  TextStyle bodyMedium,
  TextStyle labelSmall,
  Color onPrimary,
  Color onSurface,
  Color primary,
  BorderRadiusGeometry shape,
  Color surfaceContainer,
});

/// A widget that displays a video message with play/pause controls and progress bar.
///
/// Uses [VideoPlayerController] from video_player for video playback.
/// Supports video preview, interactive seeking, and fullscreen mode.
class FlyerChatVideoMessage extends StatefulWidget {
  /// The video message data model.
  final VideoMessage message;

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

  /// Color of the progress bar for sent messages.
  final Color? sentProgressColor;

  /// Color of the progress bar for received messages.
  final Color? receivedProgressColor;

  /// Text style for the message timestamp and status.
  final TextStyle? timeStyle;

  /// Whether to display the message timestamp.
  final bool showTime;

  /// Whether to display the message status (sent, delivered, seen) for sent messages.
  final bool showStatus;

  /// Position of the timestamp and status indicator relative to the video.
  final TimeAndStatusPosition timeAndStatusPosition;

  /// Optional HTTP headers for authenticated video requests.
  final Map<String, String>? headers;

  /// The widget to display on top of the message.
  final Widget? topWidget;

  /// Whether to show the download button.
  final bool showDownloadButton;

  /// Callback when download is completed.
  final Function(String filePath)? onDownloadComplete;

  /// Callback when download fails.
  final Function(String error)? onDownloadError;

  /// Maximum width for the video player.
  final double? maxWidth;

  /// Maximum height for the video player.
  final double? maxHeight;

  /// Creates a widget to display a video message.
  const FlyerChatVideoMessage({
    super.key,
    required this.message,
    required this.index,
    this.padding = const EdgeInsets.all(8),
    this.borderRadius,
    this.constraints,
    this.sentBackgroundColor,
    this.receivedBackgroundColor,
    this.sentButtonColor,
    this.receivedButtonColor,
    this.sentProgressColor,
    this.receivedProgressColor,
    this.timeStyle,
    this.showTime = true,
    this.showStatus = true,
    this.timeAndStatusPosition = TimeAndStatusPosition.end,
    this.headers,
    this.topWidget,
    this.showDownloadButton = true,
    this.onDownloadComplete,
    this.onDownloadError,
    this.maxWidth = 150,
    this.maxHeight = 200,
  });

  @override
  State<FlyerChatVideoMessage> createState() => _FlyerChatVideoMessageState();
}

class _FlyerChatVideoMessageState extends State<FlyerChatVideoMessage> {
  VideoPlayerController? _videoController;
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _isDownloading = false;
  bool _hasError = false;
  String? _errorMessage;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(widget.message.source),
        httpHeaders: widget.headers ?? {},
      );

      await _videoController!.initialize();

      if (mounted) {
        setState(() {
          _isInitialized = true;
          _duration = _videoController!.value.duration;
          _hasError = false;
        });

        _videoController!.addListener(_videoListener);
      }
    } catch (e) {
      debugPrint('Error initializing video: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = 'Erreur de chargement de la vidéo';
        });
      }
    }
  }

  void _videoListener() {
    if (!mounted) return;

    setState(() {
      _isPlaying = _videoController!.value.isPlaying;
      _position = _videoController!.value.position;
      _duration = _videoController!.value.duration;
    });
  }

  @override
  void dispose() {
    _videoController?.removeListener(_videoListener);
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _togglePlayPause() async {
    if (_videoController == null || !_isInitialized) return;

    try {
      if (_isPlaying) {
        await _videoController!.pause();
      } else {
        await _videoController!.play();
      }
    } catch (e) {
      debugPrint('Error toggling play/pause: $e');
    }
  }

  Future<void> _seekTo(Duration position) async {
    if (_videoController == null || !_isInitialized) return;

    try {
      await _videoController!.seekTo(position);
    } catch (e) {
      debugPrint('Error seeking video: $e');
    }
  }

  Future<void> _downloadVideo() async {
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
      final filename = 'video_$timestamp.${_getFileExtension(widget.message.source)}';
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
              content: Text('Vidéo téléchargée avec succès'),
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
    return 'mp4'; // Default extension
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
              _buildVideoPlayer(isSentByMe, theme),
              const SizedBox(height: 8),
              _buildControls(isSentByMe, theme, timeAndStatus),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVideoPlayer(bool isSentByMe, _LocalTheme theme) {
    // Show error state if video failed to load
    if (_hasError) {
      return Container(
        width: widget.maxWidth,
        height: widget.maxHeight,
        color: Colors.black87,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                color: Colors.white,
                size: 40,
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage ?? 'Erreur de chargement',
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  setState(() {
                    _hasError = false;
                    _isInitialized = false;
                  });
                  _initializeVideo();
                },
                child: const Text(
                  'Réessayer',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Show loading state
    if (!_isInitialized || _videoController == null) {
      return Container(
        width: widget.maxWidth,
        height: widget.maxHeight,
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final videoAspectRatio = _videoController!.value.aspectRatio;
    final videoWidth = widget.maxWidth ?? 150;
    final videoHeight = videoWidth / videoAspectRatio;
    final constrainedHeight = videoHeight > (widget.maxHeight ?? 200)
        ? widget.maxHeight ?? 200
        : videoHeight;

    return GestureDetector(
      onTap: _togglePlayPause,
      child: Container(
        width: videoWidth,
        height: constrainedHeight,
        color: Colors.black,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: videoWidth,
              height: constrainedHeight,
              child: FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: _videoController!.value.size.width,
                  height: _videoController!.value.size.height,
                  child: VideoPlayer(_videoController!),
                ),
              ),
            ),
            if (!_isPlaying)
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow,
                  color: Colors.white,
                  size: 40,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildControls(bool isSentByMe, _LocalTheme theme, TimeAndStatus? timeAndStatus) {
    return Column(
      children: [
        _buildProgressBar(isSentByMe, theme),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _formatDurationWithTotal(_position, _duration),
              style: _resolveTimeStyle(isSentByMe, theme),
            ),
            Row(
              children: [
                if (timeAndStatus != null) ...[
                  timeAndStatus,
                  const SizedBox(width: 8),
                ],
                if (widget.showDownloadButton)
                  _buildDownloadButton(isSentByMe, theme),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildProgressBar(bool isSentByMe, _LocalTheme theme) {
    final progressColor = isSentByMe
        ? (widget.sentProgressColor ?? theme.onPrimary)
        : (widget.receivedProgressColor ?? theme.onSurface);

    final progress = _duration.inMilliseconds > 0
        ? _position.inMilliseconds / _duration.inMilliseconds
        : 0.0;

    return GestureDetector(
      onTapDown: (details) => _handleProgressBarTap(details),
      child: Container(
        height: 4,
        decoration: BoxDecoration(
          color: progressColor.withOpacity(0.3),
          borderRadius: BorderRadius.circular(2),
        ),
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: progress.clamp(0.0, 1.0),
          child: Container(
            decoration: BoxDecoration(
              color: progressColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }

  void _handleProgressBarTap(TapDownDetails details) {
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final localPosition = details.localPosition;
    final progress = localPosition.dx / renderBox.size.width;
    final seekPosition = Duration(
      milliseconds: (_duration.inMilliseconds * progress.clamp(0.0, 1.0)).round(),
    );
    _seekTo(seekPosition);
  }

  Widget _buildDownloadButton(bool isSentByMe, _LocalTheme theme) {
    final buttonColor = isSentByMe
        ? (widget.sentButtonColor ?? theme.onPrimary)
        : (widget.receivedButtonColor ?? theme.onSurface);

    return GestureDetector(
      onTap: _isDownloading ? null : _downloadVideo,
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
