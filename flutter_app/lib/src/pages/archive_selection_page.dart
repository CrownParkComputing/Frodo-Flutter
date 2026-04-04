import 'package:flutter/material.dart';

class ArchiveSelectionPage extends StatefulWidget {
  const ArchiveSelectionPage({
    required this.archiveTitle,
    required this.entries,
    super.key,
  });

  final String archiveTitle;
  final List<String> entries;

  @override
  State<ArchiveSelectionPage> createState() => _ArchiveSelectionPageState();
}

class _ArchiveSelectionPageState extends State<ArchiveSelectionPage> {
  late Set<String> _selected;
  final searchController = TextEditingController();
  String _query = '';
  String _extensionFilter = 'All';
  bool _selectedOnly = false;
  String _alphaFilter = 'All';
  late List<String> _sortedEntries;

  @override
  void initState() {
    super.initState();
    _selected = <String>{};
    _initializeSortedEntries();
  }

  void _initializeSortedEntries() {
    _sortedEntries = List<String>.from(widget.entries);
    _sortedEntries.sort((a, b) {
      final nameA = a.split('/').last.toLowerCase();
      final nameB = b.split('/').last.toLowerCase();
      return nameA.compareTo(nameB);
    });
  }

  List<String> _computeFilteredEntries() {
    final normalizedQuery = _query.trim().toLowerCase();
    return _sortedEntries
        .where((entry) {
          final lower = entry.toLowerCase();
          if (_extensionFilter != 'All' &&
              !lower.endsWith('.${_extensionFilter.toLowerCase()}')) {
            return false;
          }
          if (_selectedOnly && !_selected.contains(entry)) {
            return false;
          }
          final fileName = entry.split('/').last;
          if (_alphaFilter != 'All') {
            final first = fileName.isEmpty ? '#' : fileName[0].toUpperCase();
            final alpha = RegExp(r'[A-Z]').hasMatch(first) ? first : '#';
            if (alpha != _alphaFilter) {
              return false;
            }
          }
          if (normalizedQuery.isEmpty) {
            return true;
          }
          final lowerName = fileName.toLowerCase();
          return lowerName.contains(normalizedQuery) ||
              lower.contains(normalizedQuery);
        })
        .toList(growable: false);
  }

  Set<String> _getExtensionOptions() {
    final extensionOptions = <String>{'All'};
    for (final entry in widget.entries) {
      final lower = entry.toLowerCase();
      for (final ext in const ['.d64', '.t64', '.tap', '.z64', '.prg']) {
        if (lower.endsWith(ext)) {
          extensionOptions.add(ext.substring(1).toUpperCase());
          break;
        }
      }
    }
    return extensionOptions;
  }

  List<String> _getAlphaOptions() {
    final set = <String>{'All'};
    for (final entry in _sortedEntries) {
      final fileName = entry.split('/').last;
      final first = fileName.isEmpty ? '#' : fileName[0].toUpperCase();
      set.add(RegExp(r'[A-Z]').hasMatch(first) ? first : '#');
    }

    final letters = set.where((e) => e != 'All').toList()..sort();
    return ['All', ...letters];
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredEntries = _computeFilteredEntries();
    final extensionOptions = _getExtensionOptions();
    final alphaOptions = _getAlphaOptions();

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Text(
          'Extract (${_selected.length}/${widget.entries.length})',
          style: const TextStyle(fontSize: 16),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'clear') {
                setState(_selected.clear);
              } else if (value == 'tick') {
                setState(() => _selected.addAll(filteredEntries));
              }
            },
            itemBuilder:
                (_) => [
                  const PopupMenuItem(
                    value: 'tick',
                    child: Text('Tick all shown'),
                  ),
                  const PopupMenuItem(value: 'clear', child: Text('Clear all')),
                ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: searchController,
                        onChanged: (value) {
                          setState(() {
                            _query = value;
                          });
                        },
                        decoration: InputDecoration(
                          isDense: true,
                          prefixIcon: const Icon(Icons.search, size: 18),
                          hintText: 'Search...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          suffixIcon:
                              _query.isEmpty
                                  ? null
                                  : IconButton(
                                    onPressed: () {
                                      setState(() {
                                        searchController.clear();
                                        _query = '';
                                      });
                                    },
                                    icon: const Icon(Icons.clear, size: 18),
                                  ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 36,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      DropdownButton<String>(
                        value: _extensionFilter,
                        underline: const SizedBox(),
                        isDense: true,
                        items:
                            extensionOptions
                                .toList()
                                .map(
                                  (option) => DropdownMenuItem<String>(
                                    value: option,
                                    child: Text(
                                      option,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                )
                                .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _extensionFilter = value);
                        },
                      ),
                      const SizedBox(width: 4),
                      ChoiceChip(
                        label: const Icon(Icons.check_box, size: 16),
                        selected: _selectedOnly,
                        visualDensity: VisualDensity.compact,
                        onSelected:
                            (value) => setState(() => _selectedOnly = value),
                      ),
                      const SizedBox(width: 4),
                      for (final alpha in alphaOptions)
                        Padding(
                          padding: const EdgeInsets.only(right: 2),
                          child: ChoiceChip(
                            label: Text(
                              alpha,
                              style: const TextStyle(fontSize: 11),
                            ),
                            selected: _alphaFilter == alpha,
                            onSelected:
                                (_) => setState(() => _alphaFilter = alpha),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            labelPadding: const EdgeInsets.symmetric(
                              horizontal: 6,
                            ),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        child: Text(
                          '${filteredEntries.length}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1),
          Expanded(
            child:
                filteredEntries.isEmpty
                    ? Center(
                      child: Text(
                        _query.isEmpty && !_selectedOnly
                            ? 'No games found'
                            : 'No matches for current filters',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    )
                    : ListView.builder(
                      itemCount: filteredEntries.length,
                      itemBuilder: (context, index) {
                        final entry = filteredEntries[index];
                        final fileName = entry.split('/').last;
                        final isChecked = _selected.contains(entry);
                        return ListTile(
                          dense: true,
                          visualDensity: const VisualDensity(
                            vertical: -3,
                            horizontal: -2,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                          ),
                          leading: Checkbox(
                            value: isChecked,
                            onChanged: (checked) {
                              setState(() {
                                if (checked == true) {
                                  _selected.add(entry);
                                } else {
                                  _selected.remove(entry);
                                }
                              });
                            },
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                          title: Text(
                            fileName,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle:
                              fileName == entry
                                  ? null
                                  : Text(
                                    entry,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 10),
                                  ),
                          onTap: () {
                            setState(() {
                              if (isChecked) {
                                _selected.remove(entry);
                              } else {
                                _selected.add(entry);
                              }
                            });
                          },
                        );
                      },
                    ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
              IconButton(
                onPressed:
                    filteredEntries.isEmpty
                        ? null
                        : () => setState(
                          () => _selected.removeAll(filteredEntries),
                        ),
                icon: const Icon(Icons.deselect),
              ),
              const Spacer(),
              FilledButton(
                onPressed:
                    _selected.isEmpty
                        ? null
                        : () => Navigator.pop(context, _selected.toList()),
                child: const Text('Extract'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
