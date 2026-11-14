import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/music_player_controller.dart';
import '../services/spotify_export_service.dart';
import '../theme/app_theme.dart';

/// Imports a real Spotify library from the official "Download your data"
/// package. Works without Premium and without the Web API: the export is a
/// ZIP of JSON files that Spotify emails to the account owner for free.
class SpotifyExportImportDialog extends StatefulWidget {
  final MusicPlayerController controller;

  const SpotifyExportImportDialog({super.key, required this.controller});

  /// Returns the first imported playlist id, or null when cancelled.
  static Future<String?> show(
    BuildContext context, {
    required MusicPlayerController controller,
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SpotifyExportImportDialog(controller: controller),
    );
  }

  @override
  State<SpotifyExportImportDialog> createState() =>
      _SpotifyExportImportDialogState();
}

class _SpotifyExportImportDialogState extends State<SpotifyExportImportDialog> {
  final SpotifyExportService _service = SpotifyExportService();

  SpotifyExportBundle? _bundle;
  final Set<int> _selected = <int>{};
  bool _isParsing = false;
  bool _isImporting = false;
  bool _downloadAfterImport = false;
  int _completed = 0;
  String _currentName = '';
  final List<String> _importedPlaylistIds = <String>[];
  int _importedTracks = 0;
  String? _error;

  bool get _isBusy => _isParsing || _isImporting;

  Future<void> _pickZip() async {
    if (_isBusy) return;
    setState(() {
      _isParsing = true;
      _error = null;
    });
    try {
      final file = await FilePicker.pickFile(type: FileType.any);
      if (file == null) {
        if (mounted) setState(() => _isParsing = false);
        return;
      }
      if (!file.name.toLowerCase().endsWith('.zip')) {
        throw const SpotifyExportException(
          'Choose the ZIP file Spotify emailed you.',
        );
      }
      final length = await file.length();
      if (length != null && length > SpotifyExportService.maxZipBytes) {
        throw const SpotifyExportException(
          'That ZIP is too large to read on this device.',
        );
      }
      final bytes = await _readFile(file, SpotifyExportService.maxZipBytes);
      final bundle = _service.parseZipBytes(bytes);
      _applyBundle(bundle);
    } on SpotifyExportException catch (e) {
      _fail(e.message);
    } on PlatformException catch (_) {
      _fail('Could not open the file picker. Please try again.');
    } catch (_) {
      _fail('Could not read that file. Please choose the export ZIP again.');
    }
  }

  Future<Uint8List> _readFile(PlatformFile file, int cap) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in file.readAsByteStream()) {
      builder.add(chunk);
      if (builder.length > cap) {
        throw const SpotifyExportException(
          'That file is larger than expected.',
        );
      }
    }
    return builder.takeBytes();
  }

  void _applyBundle(SpotifyExportBundle bundle) {
    if (!mounted) return;
    if (bundle.isEmpty) {
      setState(() {
        _isParsing = false;
        _error = _emptyBundleMessage(bundle);
      });
      return;
    }
    setState(() {
      _bundle = bundle;
      _selected
        ..clear()
        ..addAll(List<int>.generate(bundle.playlists.length, (i) => i));
      _isParsing = false;
      _error = null;
    });
  }

  String _emptyBundleMessage(SpotifyExportBundle bundle) {
    final buffer = StringBuffer(
      'No importable music was found in that export.',
    );
    if (bundle.skippedEpisodes > 0) {
      buffer.write(
        ' ${_count(bundle.skippedEpisodes, 'podcast episode', 'podcast episodes')} '
        'were skipped — Pulse is a music player.',
      );
    }
    if (bundle.savedAlbums > 0) {
      buffer.write(
        ' ${_count(bundle.savedAlbums, 'saved album', 'saved albums')} only '
        'list album names, not their tracks.',
      );
    }
    return buffer.toString();
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _isParsing = false;
      _isImporting = false;
      _error = message;
    });
  }

  Future<void> _runImport() async {
    final bundle = _bundle;
    if (bundle == null || _selected.isEmpty || _isBusy) return;

    final indices = _selected.toList()..sort();
    setState(() {
      _isImporting = true;
      _error = null;
      _completed = 0;
      _importedTracks = 0;
      _importedPlaylistIds.clear();
    });

    final previousAutoDownload = widget.controller.autoDownloadOnImport;
    widget.controller.autoDownloadOnImport = _downloadAfterImport;
    try {
      for (var i = 0; i < indices.length; i++) {
        final playlist = bundle.playlists[indices[i]];
        if (mounted) {
          setState(() => _currentName = playlist.name);
        }
        final outcome = await widget.controller.importSpotifyTracksAsync(
          playlistName: playlist.name,
          tracks: playlist.tracks,
        );
        _importedPlaylistIds.add(outcome.playlistId);
        _importedTracks += outcome.addedCount;
        if (mounted) {
          setState(() => _completed = i + 1);
        }
      }
      if (!mounted) return;
      setState(() {
        _isImporting = false;
        _currentName = '';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isImporting = false;
        _currentName = '';
        _error =
            'Import stopped after $_completed of ${indices.length} playlists. '
            'The playlists already imported were kept.';
      });
    } finally {
      widget.controller.autoDownloadOnImport = previousAutoDownload;
    }
  }

  void _toggleAll(bool selected) {
    final bundle = _bundle;
    if (bundle == null) return;
    setState(() {
      _selected.clear();
      if (selected) {
        _selected.addAll(List<int>.generate(bundle.playlists.length, (i) => i));
      }
    });
  }

  void _close() {
    Navigator.of(context).pop(_importedPlaylistIds.firstOrNull);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(
        children: [
          Icon(Icons.inventory_2_rounded, color: AppTheme.primary, size: 26),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Import Spotify data export',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 18),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_bundle == null) _buildIntro(),
              if (_bundle != null) _buildPreview(_bundle!),
              if (_isParsing || _isImporting) ...[
                const SizedBox(height: 14),
                _buildProgress(),
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
      actions: _buildActions(),
    );
  }

  Widget _buildIntro() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Spotify gives you a copy of your library for free — no Premium and '
          'no developer app needed.',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 13.5,
            height: 1.4,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        _step('1', 'Open Spotify → Account → Privacy settings.'),
        _step('2', 'Tap "Download your data" and request Account data.'),
        _step('3', 'Spotify emails a ZIP, usually within a few days.'),
        _step('4', 'Choose that ZIP below to import your library.'),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.cardSurface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.border),
          ),
          child: const Text(
            'Imports Liked Songs and every playlist, including private ones. '
            'Saved albums and followed artists appear in the export as names '
            'only, so their tracks cannot be recovered from it. Podcast '
            'episodes are skipped.',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 14),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
          ),
          onPressed: _isBusy ? null : _pickZip,
          icon: const Icon(Icons.folder_zip_rounded, size: 18),
          label: const Text('Choose export ZIP'),
        ),
      ],
    );
  }

  Widget _step(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 18,
            height: 18,
            alignment: Alignment.center,
            margin: const EdgeInsets.only(top: 1),
            decoration: const BoxDecoration(
              color: AppTheme.primary,
              shape: BoxShape.circle,
            ),
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview(SpotifyExportBundle bundle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${_count(bundle.playlistCount, 'playlist', 'playlists')} · '
                '${_count(bundle.totalTracks, 'track', 'tracks')} found',
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton(
              onPressed: _isBusy
                  ? null
                  : () => _toggleAll(_selected.length != bundle.playlistCount),
              child: Text(
                _selected.length == bundle.playlistCount
                    ? 'Clear all'
                    : 'Select all',
                style: const TextStyle(color: AppTheme.primary, fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          constraints: const BoxConstraints(maxHeight: 260),
          decoration: BoxDecoration(
            color: AppTheme.background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
          ),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: bundle.playlists.length,
            itemBuilder: (context, index) {
              final playlist = bundle.playlists[index];
              final selected = _selected.contains(index);
              return CheckboxListTile(
                dense: true,
                value: selected,
                activeColor: AppTheme.primary,
                checkColor: Colors.white,
                onChanged: _isBusy
                    ? null
                    : (value) => setState(() {
                        if (value == true) {
                          _selected.add(index);
                        } else {
                          _selected.remove(index);
                        }
                      }),
                title: Row(
                  children: [
                    Flexible(
                      child: Text(
                        playlist.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    if (playlist.isLikedSongs) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.accentGreen.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Liked',
                          style: TextStyle(
                            color: AppTheme.accentGreen,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                subtitle: Text(
                  _count(playlist.trackCount, 'track', 'tracks'),
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 11,
                  ),
                ),
                controlAffinity: ListTileControlAffinity.leading,
              );
            },
          ),
        ),
        if (_skippedSummary(bundle).isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            _skippedSummary(bundle),
            style: const TextStyle(
              color: AppTheme.textMuted,
              fontSize: 11.5,
              height: 1.35,
            ),
          ),
        ],
        const SizedBox(height: 8),
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          value: _downloadAfterImport,
          activeColor: AppTheme.primary,
          checkColor: Colors.white,
          onChanged: _isBusy
              ? null
              : (value) =>
                    setState(() => _downloadAfterImport = value ?? false),
          title: const Text(
            'Download audio for offline playback',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 12.5),
          ),
          subtitle: const Text(
            'Off by default. Large libraries can use a lot of storage and data.',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
          ),
          controlAffinity: ListTileControlAffinity.leading,
        ),
      ],
    );
  }

  String _count(int value, String singular, String plural) =>
      '$value ${value == 1 ? singular : plural}';

  String _skippedSummary(SpotifyExportBundle bundle) {
    final parts = <String>[];
    if (bundle.skippedEpisodes > 0) {
      parts.add(
        '${_count(bundle.skippedEpisodes, 'podcast episode', 'podcast episodes')} '
        'skipped',
      );
    }
    if (bundle.skippedUnavailable > 0) {
      parts.add(
        '${_count(bundle.skippedUnavailable, 'unavailable row', 'unavailable rows')} '
        'skipped',
      );
    }
    if (bundle.emptyPlaylists > 0) {
      parts.add(
        '${_count(bundle.emptyPlaylists, 'empty playlist', 'empty playlists')} '
        'skipped',
      );
    }
    if (bundle.savedAlbums > 0) {
      parts.add(
        '${_count(bundle.savedAlbums, 'saved album', 'saved albums')} '
        '(names only)',
      );
    }
    if (bundle.followedArtists > 0) {
      parts.add(
        '${_count(bundle.followedArtists, 'followed artist', 'followed artists')} '
        '(names only)',
      );
    }
    if (bundle.renamedPlaylists > 0) {
      parts.add(
        '${_count(bundle.renamedPlaylists, 'duplicate name', 'duplicate names')} '
        'kept separate',
      );
    }
    return parts.join(' · ');
  }

  Widget _buildProgress() {
    final bundle = _bundle;
    final total = _selected.isEmpty
        ? (bundle?.playlists.length ?? 0)
        : _selected.length;
    final value = total == 0 ? null : (_completed / total).clamp(0.0, 1.0);
    final label = _isImporting
        ? (_completed >= total && total > 0
              ? 'Saving…'
              : 'Importing ${_completed + 1} of $total · $_currentName')
        : 'Reading export…';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(
          value: _isImporting ? value : null,
          backgroundColor: AppTheme.border,
          color: AppTheme.primary,
          minHeight: 5,
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11.5),
        ),
      ],
    );
  }

  List<Widget> _buildActions() {
    final bundle = _bundle;
    final finished = bundle != null && !_isImporting && _completed > 0;

    if (finished) {
      return [
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.accentGreen,
            foregroundColor: Colors.white,
          ),
          onPressed: _close,
          child: Text(
            'Done · ${_count(_importedTracks, 'track', 'tracks')} imported',
          ),
        ),
      ];
    }

    return [
      TextButton(
        onPressed: _isImporting ? null : _close,
        child: const Text(
          'Cancel',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
      ),
      if (bundle != null)
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.accentGreen,
            foregroundColor: Colors.white,
          ),
          onPressed: _isBusy || _selected.isEmpty ? null : _runImport,
          icon: _isImporting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.download_rounded, size: 18),
          label: Text(
            _isImporting
                ? 'Importing…'
                : 'Import ${_selected.length} playlist'
                      '${_selected.length == 1 ? '' : 's'}',
          ),
        ),
    ];
  }
}
