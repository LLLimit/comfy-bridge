import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/models/task_model.dart';

class MediaPreviewDialog extends StatefulWidget {
  const MediaPreviewDialog({
    super.key,
    required this.output,
    required this.uri,
    required this.headers,
    required this.onSave,
    required this.onDelete,
  });

  final TaskOutputModel output;
  final Uri uri;
  final Map<String, String> headers;
  final Future<void> Function() onSave;
  final Future<void> Function() onDelete;

  @override
  State<MediaPreviewDialog> createState() => _MediaPreviewDialogState();
}

class _MediaPreviewDialogState extends State<MediaPreviewDialog> {
  VideoPlayerController? _video;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    if (widget.output.mediaType == 'video') {
      final controller = VideoPlayerController.networkUrl(
        widget.uri,
        httpHeaders: widget.headers,
      );
      _video = controller;
      controller.initialize().then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.output.fileName),
          leading: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
          actions: [
            IconButton(
              tooltip: '保存到手机',
              onPressed: _working ? null : _save,
              icon: _working
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_outlined),
            ),
            IconButton(
              tooltip: '删除作品',
              onPressed: _working ? null : _delete,
              icon: const Icon(Icons.delete_outline),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Center(
          child: widget.output.mediaType == 'image'
              ? InteractiveViewer(
                  child: Image.network(
                    widget.uri.toString(),
                    headers: widget.headers,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Text('图片加载失败'),
                  ),
                )
              : _videoBody(),
        ),
        floatingActionButton: _video == null
            ? null
            : FloatingActionButton(
                onPressed: () => setState(() {
                  _video!.value.isPlaying ? _video!.pause() : _video!.play();
                }),
                child: Icon(
                  _video!.value.isPlaying ? Icons.pause : Icons.play_arrow,
                ),
              ),
      ),
    );
  }

  Widget _videoBody() {
    final video = _video;
    if (video == null || !video.value.isInitialized) {
      return const CircularProgressIndicator();
    }
    return AspectRatio(
      aspectRatio: video.value.aspectRatio,
      child: VideoPlayer(video),
    );
  }

  Future<void> _save() async {
    setState(() => _working = true);
    try {
      await widget.onSave();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存到手机相册的 Comfy Bridge 文件夹。')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('保存失败：$error')));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除这个作品？'),
        content: const Text('作品将从电脑 Agent 的作品库中永久删除，此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _working = true);
    try {
      await widget.onDelete();
      if (!mounted) return;
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      setState(() => _working = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('删除失败：$error')));
    }
  }
}
