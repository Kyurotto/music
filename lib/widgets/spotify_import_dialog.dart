import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../controllers/music_player_controller.dart';
import '../services/spotify_import_service.dart';
import '../theme/app_theme.dart';

/// Dialog that accepts a Spotify track/playlist/album link and imports it
/// into a new or existing playlist.
class SpotifyImportDialog extends StatefulWidget {
  final MusicPlayerController controller;

  const SpotifyImportDialog({super.key, required this.controller});

  /// Opens the import dialog. Returns the target playlist id when the import
  /// completed, or null when cancelled.
  static Future<String?> show(
    BuildContext context, {
    required MusicPlayerController controller,
  }) async {
    return showDialog<String>(
      context: context,
      builder: (_) => SpotifyImportDialog(controller: controller),
    );
  }

  @override
  State<SpotifyImportDialog> createState() => _SpotifyImportDialogState();
}

class _SpotifyImportDialogState extends State<SpotifyImportDialog> {
  final TextEditingController _linkController = TextEditingController();
  final SpotifyImportService _service = SpotifyImportService();
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = false;
  String? _error;
  String? _targetPlaylistId;
  SpotifyImportResult? _preview;

  @override
  void dispose() {
    _linkController.dispose();
    _service.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) return;
    _linkController.text = text;
    _linkController.selection = TextSelection.collapsed(offset: text.length);
    setState(() => _error = null);
  }

  Future<void> _previewLink() async {
    final link = _linkController.text.trim();
    if (link.isEmpty) {
      setState(() => _error = 'Paste a Spotify link first.');
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
      _preview = null;
    });
    try {
      final result = await _service.importFromLink(link);
      if (!mounted) return;
      setState(() {
        _preview = result;
        _isLoading = false;
      });
    } on SpotifyImportException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Something went wrong. Please try again.';
        _isLoading = false;
      });
    }
  }

  Future<void> _confirmImport() async {
    final preview = _preview;
    if (preview == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final outcome = widget.controller.importSpotifyTracks(
        playlistName: preview.title,
        tracks: preview.tracks,
        targetPlaylistId: _targetPlaylistId,
        spotifyUrl: _linkController.text.trim(),
        imageUrl: preview.imageUrl,
      );
      if (!mounted) return;
      Navigator.of(context).pop(outcome.playlistId);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not save the playlist. Please try again.';
        _isLoading = false;
      });
    }
  }

  String get _playlistLabel {
    switch (_preview?.type) {
      case SpotifyLinkType.playlist:
        return 'Save as playlist "${_preview!.title}"';
      case SpotifyLinkType.album:
        return 'Save as playlist "${_preview!.title}"';
      case SpotifyLinkType.artist:
        return 'Save as playlist "${_preview!.title}"';
      case SpotifyLinkType.track:
        return 'Add to playlist';
      case null:
        return 'Playlist';
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final playlists = widget.controller.playlists;

    return AlertDialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(
        children: [
          Icon(Icons.library_add_rounded, color: AppTheme.primary, size: 26),
          SizedBox(width: 10),
          Text(
            'Import from Spotify',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 18),
          ),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Paste a Spotify track, playlist, album, or artist link — or just type an artist name like "Bruno Mars" to import their top songs.\n\nSpotify only shares metadata, so imported tracks may play as 30-second previews. Use the "Open in Spotify" button in the player to hear the full song. Lyrics are fetched automatically where available.',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _linkController,
                enabled: !_isLoading,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 14,
                ),
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  hintText:
                      'https://open.spotify.com/playlist/... or "Bruno Mars"',
                  hintStyle: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 13,
                  ),
                  filled: true,
                  fillColor: AppTheme.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: AppTheme.primary,
                      width: 1.5,
                    ),
                  ),
                  suffixIcon: IconButton(
                    tooltip: 'Paste from clipboard',
                    icon: const Icon(
                      Icons.content_paste_rounded,
                      size: 18,
                      color: AppTheme.textSecondary,
                    ),
                    onPressed: _isLoading ? null : _pasteFromClipboard,
                  ),
                ),
                onFieldSubmitted: (_) => _previewLink(),
              ),
              if (preview != null) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.cardSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Row(
                    children: [
                      if (preview.imageUrl.isNotEmpty) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            preview.imageUrl,
                            width: 52,
                            height: 52,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const SizedBox.shrink(),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              preview.title,
                              style: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            if (preview.subtitle.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                preview.subtitle,
                                style: const TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                            const SizedBox(height: 6),
                            Text(
                              preview.type == SpotifyLinkType.track
                                  ? '1 track ready to import'
                                  : '${preview.tracks.length} tracks ready to import',
                              style: const TextStyle(
                                color: AppTheme.accentGreen,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String?>(
                  initialValue: _targetPlaylistId,
                  dropdownColor: AppTheme.cardSurface,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                  ),
                  decoration: InputDecoration(
                    labelText: _playlistLabel,
                    labelStyle: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                    filled: true,
                    fillColor: AppTheme.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.border),
                    ),
                  ),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(
                        preview.type == SpotifyLinkType.track
                            ? 'Create new playlist'
                            : 'New playlist from link',
                      ),
                    ),
                    ...playlists.map(
                      (playlist) => DropdownMenuItem<String?>(
                        value: playlist.id,
                        child: Text(
                          playlist.title,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: _isLoading
                      ? null
                      : (value) => setState(() => _targetPlaylistId = value),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: AppTheme.accentPink,
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          child: const Text(
            'Cancel',
            style: TextStyle(color: AppTheme.textSecondary),
          ),
        ),
        if (_preview == null)
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            onPressed: _isLoading ? null : _previewLink,
            icon: _isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.search_rounded, size: 18),
            label: Text(_isLoading ? 'Checking…' : 'Check link'),
          )
        else
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            onPressed: _isLoading ? null : _confirmImport,
            icon: _isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.download_rounded, size: 18),
            label: Text(_isLoading ? 'Importing…' : 'Import'),
          ),
      ],
    );
  }
}
