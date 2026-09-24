import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:miru_app/controllers/music_controller.dart';
import 'package:miru_app/models/index.dart';
import 'package:miru_app/router/router.dart';

/// 全局悬浮小播放器
/// 当音乐播放时，在所有页面左下角显示固定播放器组件
class GlobalMiniPlayer extends StatefulWidget {
  const GlobalMiniPlayer({super.key});

  @override
  State<GlobalMiniPlayer> createState() => _GlobalMiniPlayerState();
}

class _GlobalMiniPlayerState extends State<GlobalMiniPlayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;
  late final Animation<double> _slideAnimation;
  late final Animation<double> _fadeAnimation;
  bool _isExpanded = false;
  bool _showVolumeSlider = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _slideAnimation = Tween<double>(begin: -120, end: 0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _show() {
    if (!_animationController.isCompleted) {
      _animationController.forward();
    }
  }

  void _hide() {
    if (_animationController.isCompleted) {
      _animationController.reverse();
    }
  }

  void _toggleExpand() {
    setState(() => _isExpanded = !_isExpanded);
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) return '--:--';
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String _formatPosition(Duration position) {
    final minutes = position.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = position.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return GetX<MusicPlayerController>(
      tag: 'global',
      builder: (player) {
        final track = player.current.value;
        final hasTrack = track != null;

        if (hasTrack) {
          _show();
        } else {
          _hide();
        }

        return AnimatedBuilder(
          animation: _animationController,
          builder: (context, child) {
            if (_animationController.value == 0) {
              return const SizedBox.shrink();
            }

            return Positioned(
              left: 12,
              bottom: _getBottomOffset(context),
              child: Transform.translate(
                offset: Offset(0, _slideAnimation.value),
                child: Opacity(
                  opacity: _fadeAnimation.value,
                  child: _isExpanded
                      ? _buildExpandedPlayer(context, player, track)
                      : _buildCompactPlayer(context, player, track),
                ),
              ),
            );
          },
        );
      },
    );
  }

  double _getBottomOffset(BuildContext context) {
    // 根据是否有底部导航栏调整偏移量
    final isTablet = MediaQuery.of(context).size.shortestSide >= 600;
    if (isTablet) {
      return 24;
    }
    // Android 底部导航栏高度约 80
    return 90;
  }

  Widget _buildCompactPlayer(
    BuildContext context,
    MusicPlayerController player,
    MusicTrack? track,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 8,
      shadowColor: Colors.black38,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 320,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [
              colorScheme.primaryContainer.withOpacity(0.95),
              colorScheme.surfaceContainerHighest.withOpacity(0.95),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Row(
          children: [
            // 封面
            _buildCover(track),
            const SizedBox(width: 8),
            // 歌曲信息
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track?.title ?? '未播放',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onPrimaryContainer,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (track?.artist != null)
                    Text(
                      track!.artist!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onPrimaryContainer.withOpacity(0.7),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            // 播放控制
            _buildCompactControls(player),
            // 扩展按钮
            IconButton(
              icon: Icon(
                _isExpanded ? Icons.fullscreen_exit : Icons.fullscreen,
                size: 20,
              ),
              onPressed: _toggleExpand,
              tooltip: _isExpanded ? '收起' : '展开',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedPlayer(
    BuildContext context,
    MusicPlayerController player,
    MusicTrack? track,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 8,
      shadowColor: Colors.black38,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 340,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [
              colorScheme.primaryContainer.withOpacity(0.95),
              colorScheme.surfaceContainerHighest.withOpacity(0.95),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 头部：封面 + 歌曲信息
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildCover(track, size: 64),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track?.title ?? '未播放',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onPrimaryContainer,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        track?.artist ?? '未知艺术家',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onPrimaryContainer.withOpacity(0.7),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (track?.album != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          track!.album!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onPrimaryContainer.withOpacity(0.5),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.fullscreen_exit, size: 20),
                  onPressed: _toggleExpand,
                  tooltip: '收起',
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 进度条
            _buildProgressBar(context, player),
            const SizedBox(height: 12),
            // 控制按钮
            _buildExpandedControls(context, player),
          ],
        ),
      ),
    );
  }

  Widget _buildCover(MusicTrack? track, {double size = 40}) {
    if (track?.cover != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          track!.cover!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildDefaultCover(size),
        ),
      );
    }
    return _buildDefaultCover(size);
  }

  Widget _buildDefaultCover(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: Colors.grey.shade300,
      ),
      child: Icon(Icons.music_note, size: size * 0.5, color: Colors.grey.shade600),
    );
  }

  Widget _buildCompactControls(MusicPlayerController player) {
    return Obx(() {
      final isPlaying = player.player.state.playing;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.skip_previous, size: 20),
            onPressed: player.previous,
            tooltip: '上一曲',
          ),
          IconButton(
            icon: Icon(
              isPlaying ? Icons.pause : Icons.play_arrow,
              size: 24,
            ),
            onPressed: player.toggle,
            tooltip: isPlaying ? '暂停' : '播放',
          ),
          IconButton(
            icon: const Icon(Icons.skip_next, size: 20),
            onPressed: player.next,
            tooltip: '下一曲',
          ),
        ],
      );
    });
  }

  Widget _buildProgressBar(BuildContext context, MusicPlayerController player) {
    return Obx(() {
      final duration = player.player.state.duration;
      final position = player.player.state.position;
      final progress = duration.inMilliseconds > 0
          ? position.inMilliseconds / duration.inMilliseconds
          : 0.0;

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: progress.clamp(0.0, 1.0),
              onChanged: (value) {
                final newPosition = Duration(
                  milliseconds: (duration.inMilliseconds * value).round(),
                );
                player.player.seek(newPosition);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatPosition(position),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  _formatDuration(duration),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      );
    });
  }

  Widget _buildExpandedControls(BuildContext context, MusicPlayerController player) {
    final theme = Theme.of(context);

    return Obx(() {
      final isPlaying = player.player.state.playing;
      final volume = player.player.state.volume;

      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // 音量控制
          _buildVolumeControl(context, player, volume),
          // 上一曲
          IconButton(
            icon: const Icon(Icons.skip_previous),
            onPressed: player.previous,
            iconSize: 28,
            tooltip: '上一曲',
          ),
          // 播放/暂停
          IconButton.filled(
            icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
            onPressed: player.toggle,
            iconSize: 32,
            tooltip: isPlaying ? '暂停' : '播放',
          ),
          // 下一曲
          IconButton(
            icon: const Icon(Icons.skip_next),
            onPressed: player.next,
            iconSize: 28,
            tooltip: '下一曲',
          ),
          // 返回完整播放器
          IconButton(
            icon: const Icon(Icons.album),
            onPressed: () => router.go('/music'),
            tooltip: '打开播放器',
          ),
        ],
      );
    });
  }

  Widget _buildVolumeControl(
    BuildContext context,
    MusicPlayerController player,
    double volume,
  ) {
    return MouseRegion(
      onEnter: (_) => setState(() => _showVolumeSlider = true),
      onExit: (_) => setState(() => _showVolumeSlider = false),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(
              volume == 0
                  ? Icons.volume_off
                  : volume < 0.5
                      ? Icons.volume_down
                      : Icons.volume_up,
              size: 20,
            ),
            onPressed: () {
              // 静音切换
              if (volume > 0) {
                player.player.setVolume(0);
              } else {
                player.player.setVolume(1.0);
              }
            },
            tooltip: '音量',
          ),
          if (_showVolumeSlider)
            SizedBox(
              width: 80,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                ),
                child: Slider(
                  value: volume.clamp(0.0, 1.0),
                  onChanged: (value) => player.player.setVolume(value),
                ),
              ),
            ),
        ],
      ),
    );
  }
}