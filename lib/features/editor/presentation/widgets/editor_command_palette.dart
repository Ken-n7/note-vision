import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../core/theme/app_theme.dart';

class EditorCommandChoice {
  const EditorCommandChoice({
    required this.id,
    required this.label,
    required this.group,
    required this.description,
    this.shortcut,
    this.disabledReason,
  });

  final String id, label, group, description;
  final String? shortcut, disabledReason;
  bool get enabled => disabledReason == null;

  bool matches(String query) {
    final text = '$label $group $description ${shortcut ?? ''}'.toLowerCase();
    return query
        .toLowerCase()
        .trim()
        .split(RegExp(r'\s+'))
        .every(text.contains);
  }
}

/// Search remains focused while arrows choose an action and Enter runs it.
/// Disabled actions stay discoverable and explain what enables them.
class EditorCommandPalette extends StatefulWidget {
  const EditorCommandPalette({super.key, required this.choices});

  final List<EditorCommandChoice> choices;

  @override
  State<EditorCommandPalette> createState() => _EditorCommandPaletteState();
}

class _EditorCommandPaletteState extends State<EditorCommandPalette> {
  String _query = '';
  String? _activeId;
  final _rowKeys = <String, GlobalKey>{};
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<EditorCommandChoice> get _matches =>
      widget.choices.where((c) => c.matches(_query)).toList();

  EditorCommandChoice? get _active {
    final enabled = _matches.where((c) => c.enabled);
    return enabled.where((c) => c.id == _activeId).firstOrNull ??
        enabled.firstOrNull;
  }

  void _move(int delta) {
    final enabled = _matches.where((c) => c.enabled).toList();
    if (enabled.isEmpty) return;
    final index = enabled.indexWhere((c) => c.id == _active?.id);
    final next = enabled[(index + delta) % enabled.length];
    setState(() => _activeId = next.id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final rowContext = _rowKeys[next.id]?.currentContext;
      if (rowContext != null) {
        Scrollable.ensureVisible(
          rowContext,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        );
      }
    });
  }

  void _runActive() {
    final active = _active;
    if (active != null) Navigator.pop(context, active.id);
  }

  @override
  Widget build(BuildContext context) {
    final matches = _matches;
    final active = _active;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 300;
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1),
            const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1),
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                Navigator.pop(context),
          },
          child: Column(
            children: [
              if (!compact)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Score commands',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              Padding(
                key: const ValueKey('command-input-row'),
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('editor-command-search'),
                        controller: _searchController,
                        autofocus: true,
                        textInputAction: TextInputAction.search,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search_rounded),
                          labelText: 'Find a command',
                          hintText: 'Pitch, duration, beams, save…',
                        ),
                        onChanged: (value) => setState(() {
                          _query = value;
                          _activeId = null;
                        }),
                        onSubmitted: (_) => _runActive(),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close commands',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: matches.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'No matching commands. Try pitch, rhythm or bars.',
                          ),
                        ),
                      )
                    : SingleChildScrollView(
                        key: const ValueKey('editor-command-results'),
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final choice in matches)
                              Padding(
                                key: _rowKeys.putIfAbsent(
                                  choice.id,
                                  GlobalKey.new,
                                ),
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Semantics(
                                  button: true,
                                  enabled: choice.enabled,
                                  selected: active?.id == choice.id,
                                  child: Material(
                                    color: active?.id == choice.id
                                        ? AppColors.accent.withValues(
                                            alpha: .12,
                                          )
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                    child: InkWell(
                                      key: ValueKey('command-${choice.id}'),
                                      borderRadius: BorderRadius.circular(8),
                                      onTap: choice.enabled
                                          ? () => Navigator.pop(
                                              context,
                                              choice.id,
                                            )
                                          : null,
                                      child: Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Wrap(
                                              spacing: 12,
                                              runSpacing: 4,
                                              crossAxisAlignment:
                                                  WrapCrossAlignment.center,
                                              children: [
                                                Text(
                                                  choice.label,
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                    color: choice.enabled
                                                        ? AppColors.textPrimary
                                                        : AppColors
                                                              .textSecondary,
                                                  ),
                                                ),
                                                if (choice.shortcut != null)
                                                  Text(
                                                    choice.shortcut!,
                                                    style: const TextStyle(
                                                      color: AppColors.accent,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '${choice.group} · ${choice.disabledReason ?? choice.description}',
                                              style: const TextStyle(
                                                color: AppColors.textSecondary,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
