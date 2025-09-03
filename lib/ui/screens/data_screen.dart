import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../services/database_service.dart';
import 'package:provider/provider.dart';
import '../../config/app_config.dart';
import '../../providers/auth_provider.dart';
import '../common/hi_doc_app_bar.dart';

class DataScreen extends StatefulWidget {
  const DataScreen({super.key});
  @override
  State<DataScreen> createState() => _DataScreenState();
}

class _DataScreenState extends State<DataScreen> {
  List<String> _tables = [];
  String? _selectedTable;
  int _page = 1;
  bool _loading = false;
  List<Map<String, dynamic>> _rows = [];
  List<String> _columns = [];
  int _total = 0;
  static const int _limit = 20;
  String? _error;
  final _horizontalScrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _fetchTables();
  }

  Future<void> _fetchTables() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uri = Uri.parse('${AppConfig.backendBaseUrl}/api/admin/tables');
      final resp = await http.get(uri).timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        final json = jsonDecode(resp.body) as Map<String, dynamic>;
        final remote = (json['tables'] as List).cast<String>();
        // Append local-only medication tables (not yet backed by backend API)
        const localMedicationTables = [
          'medications',
          'medication_schedules',
          'medication_schedule_times',
          'medication_intake_logs',
        ];
        final merged = {
          ...remote,
          ...localMedicationTables,
        }.toList()..sort();
        setState(() {
          _tables = merged;
        });
      } else {
        setState(() {
          _error = 'Tables load failed ${resp.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Tables error: $e';
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _fetchRows({int page = 1}) async {
    final table = _selectedTable;
    if (table == null || _loading) return; // Prevent multiple simultaneous requests
    
    setState(() {
      _loading = true;
      _error = null;
    });
    
    try {
      // Local medication-related tables are not (yet) exposed via backend; query local SQLite directly.
      const localMedicationTables = {
        'medications',
        'medication_schedules',
        'medication_schedule_times',
        'medication_intake_logs',
      };
      if (table == 'messages') {
        await _fetchLocalMessages(page: page);
        return;
      } else if (localMedicationTables.contains(table) && table != 'messages') {
        final db = context.read<DatabaseService>();
        String orderBy;
        switch (table) {
          case 'medications': orderBy = 'name ASC'; break;
          case 'medication_schedules': orderBy = 'start_date DESC'; break;
          case 'medication_schedule_times': orderBy = 'sort_order ASC, time_local ASC'; break;
          case 'medication_intake_logs': orderBy = 'taken_ts DESC'; break;
          default: orderBy = 'rowid DESC';
        }
        final rows = await db.rawQuery('SELECT * FROM $table ORDER BY $orderBy');
        setState(() {
          _rows = rows;
          _columns = rows.isNotEmpty ? rows.first.keys.where((c) => c != 'user_id' && c != 'id').toList() : [];
          _page = 1; // paging not applied for local tables
          _total = rows.length;
        });
        return;
      }
      
      // For other tables, query backend API
      final uri = Uri.parse(
          '${AppConfig.backendBaseUrl}/api/admin/table/$table?page=$page&limit=$_limit');
      final resp = await http.get(uri).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final json = jsonDecode(resp.body) as Map<String, dynamic>;
        setState(() {
          _rows = (json['items'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          final allColumns = (json['columns'] as List).cast<String>();
          // Filter out user_id and id columns
          _columns = allColumns.where((col) => col != 'user_id' && col != 'id').toList();
          _page = page;
          _total =
              (json['paging'] as Map)['total'] as int? ?? _rows.length;
        });
      } else {
        setState(() {
          _error = 'Rows load failed ${resp.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Rows error: $e';
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _fetchLocalMessages({int page = 1}) async {
    try {
      // Query the backend messages table instead of local database
      final uri = Uri.parse(
          '${AppConfig.backendBaseUrl}/api/admin/table/messages?page=$page&limit=$_limit');
      final resp = await http.get(uri).timeout(const Duration(seconds: 8));
      
      if (resp.statusCode == 200) {
        final json = jsonDecode(resp.body) as Map<String, dynamic>;
        setState(() {
          _rows = (json['items'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          final allColumns = (json['columns'] as List).cast<String>();
          // Filter out user_id and id columns
          _columns = allColumns.where((col) => col != 'user_id' && col != 'id').toList();
          _page = page;
          _total = (json['paging'] as Map)['total'] as int? ?? _rows.length;
        });
      } else {
        setState(() {
          _error = 'Backend messages load failed ${resp.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Backend messages error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      appBar: HiDocAppBar(
        pageTitle: 'Data Browser',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _selectedTable == null
                ? _fetchTables
                : () => _fetchRows(page: _page),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Text(
                'Table:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButton<String>(
                  value: _selectedTable,
                  hint: const Text('Select table'),
                  isExpanded: true,
                  items: _tables
                      .map(
                        (t) => DropdownMenuItem(
                          value: t,
                          child: Text(t),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    setState(() {
                      _selectedTable = v;
                      _page = 1;
                    });
                    if (v != null) _fetchRows(page: 1);
                  },
                ),
              ),
            ]),
            if (_selectedTable != null) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search…',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            setState(() {
                              _searchQuery = '';
                              _searchController.clear();
                            });
                          },
                        )
                      : null,
                ),
                onChanged: (val) {
                  setState(() {
                    _searchQuery = val.trim();
                  });
                },
              ),
            ],
            const SizedBox(height: 12),
            if (_error != null)
              Text(
                _error!,
                style: const TextStyle(color: Colors.red),
              ),
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            if (_selectedTable != null && !_loading)
              Expanded(
                child: _rows.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.table_chart_outlined,
                              size: 48,
                              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No rows found',
                              style: TextStyle(
                                fontSize: 16,
                                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                              ),
                            ),
                          ],
                        ),
                      )
                    : Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Theme.of(context).colorScheme.surface.withOpacity(0.3),
                              Theme.of(context).colorScheme.surface.withOpacity(0.1),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Column(
                            children: [
                              // Header
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE3F2FD).withOpacity(0.5),
                                  border: Border(
                                    bottom: BorderSide(
                                      color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.table_rows,
                                      size: 16,
                                      color: const Color(0xFF1565C0),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${_selectedTable?.toUpperCase().replaceAll('_', ' ')} DATA',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF1565C0),
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    const Spacer(),
                                    Builder(builder: (_) {
                                      final filteredCount = _applySearch(_rows).length;
                                      final total = _rows.length;
                                      final text = _searchQuery.isEmpty
                                          ? '$total records'
                                          : '$filteredCount / $total';
                                      return Text(
                                        text,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: const Color(0xFF1565C0).withOpacity(0.7),
                                        ),
                                      );
                                    }),
                                  ],
                                ),
                              ),
                              // Data rows
                              Expanded(
                                child: ListView(
                                  padding: const EdgeInsets.all(8),
                                  children: _buildGroupedList(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
            if (_selectedTable != null) _buildPager(),
            const SizedBox(height: 4),
            Text(
              'User: ${auth.user?.email ?? 'dev (web)'}',
              style: const TextStyle(
                fontSize: 11,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _horizontalScrollController.dispose();
    super.dispose();
  }

  Widget _buildDataCard(Map<String, dynamic> row, int index, BuildContext context) {
    final theme = Theme.of(context);
  final createdBy = row['created_by']?.toString();
  final createdTime = _formatTimestamp(row);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: index.isEven 
          ? const Color(0xFFF5F5F5)
          : const Color(0xFFE3F2FD).withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withOpacity(0.1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPrimaryContent(row, theme),
          const SizedBox(height: 6),
          _buildMetaRow(row, theme),
          const SizedBox(height: 6),
          // Footer line (created_by  |  timestamp)
          if (createdBy != null || createdTime.isNotEmpty)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (createdBy != null)
                  Flexible(
                    child: Text(
                      createdBy,
                      style: TextStyle(
                        fontSize: 9,
                        color: theme.colorScheme.onSurface.withOpacity(0.45),
                        fontStyle: FontStyle.italic,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                else
                  const SizedBox.shrink(),
                if (createdTime.isNotEmpty)
                  Text(
                    createdTime,
                    style: TextStyle(
                      fontSize: 9,
                      color: theme.colorScheme.onSurface.withOpacity(0.45),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  List<Widget> _buildGroupedList(BuildContext context) {
  final theme = Theme.of(context);
  // Filter
  final source = _applySearch(_rows);
  // Sort rows by created_at / timestamp descending
  final sorted = [...source];
    sorted.sort((a, b) {
      final ad = _extractCreatedAt(a);
      final bd = _extractCreatedAt(b);
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return bd.compareTo(ad); // descending
    });

    final widgets = <Widget>[];
    DateTime? lastDay;
    int? lastWeekYearKey; // combine year & week into one int

    for (var i = 0; i < sorted.length; i++) {
      final row = sorted[i];
      final created = _extractCreatedAt(row);
      if (created == null) {
        widgets.add(_buildDataCard(row, i, context));
        continue;
      }
      final day = DateTime(created.year, created.month, created.day);
      final weekKey = created.year * 100 + _weekNumber(created);
      if (weekKey != lastWeekYearKey) {
        // Week header
        final start = _startOfWeek(created);
        final end = start.add(const Duration(days: 6));
        widgets.add(_WeekHeader(
          label:
              'Week of ${_fmtDate(start)} - ${_fmtDate(end)}',
        ));
        lastWeekYearKey = weekKey;
      }
      final isFirstOfDay = lastDay == null || day.isAfter(lastDay!);
      if (isFirstOfDay) {
        widgets.add(_DayHeaderAndCard(
          day: day,
          child: _buildDataCard(row, i, context),
        ));
      } else {
        widgets.add(_DaySpacerAndCard(child: _buildDataCard(row, i, context)));
      }
      lastDay = day;
    }
    return widgets;
  }

  List<Map<String, dynamic>> _applySearch(List<Map<String, dynamic>> input) {
    if (_searchQuery.isEmpty) return input;
    final q = _searchQuery.toLowerCase();
    return input.where((row) {
      for (final key in row.keys) {
        if (_isKeyField(key)) continue;
        final lk = key.toLowerCase();
        if (lk == 'created_by' || lk.startsWith('created_') || lk.startsWith('updated_')) continue;
        if (lk.endsWith('_at') || lk.contains('date') || lk.contains('time')) continue;
        final value = row[key];
        if (value == null) continue;
        final vs = value.toString().toLowerCase();
        if (vs.contains(q)) return true;
      }
      return false;
    }).toList();
  }

  DateTime? _extractCreatedAt(Map<String, dynamic> row) {
    final fields = ['created_at', 'timestamp', 'upload_date'];
    for (final f in fields) {
      final v = row[f];
      if (v == null) continue;
      try {
        if (v is int) {
          // heuristics: if seconds vs ms
            if (v.toString().length <= 10) {
              return DateTime.fromMillisecondsSinceEpoch(v * 1000, isUtc: true).toLocal();
            }
          return DateTime.fromMillisecondsSinceEpoch(v, isUtc: true).toLocal();
        } else if (v is String) {
          return DateTime.parse(v).toLocal();
        }
      } catch (_) {}
    }
    return null;
  }

  int _weekNumber(DateTime date) {
    // ISO week number calculation
    final thursday = date.add(Duration(days: 3 - ((date.weekday + 6) % 7)));
    final firstThursday = DateTime(thursday.year, 1, 4);
    final diff = thursday.difference(firstThursday);
    return 1 + (diff.inDays / 7).floor();
  }

  DateTime _startOfWeek(DateTime date) {
    final weekday = date.weekday; // 1=Mon
    return DateTime(date.year, date.month, date.day).subtract(Duration(days: weekday - 1));
  }

  String _fmtDate(DateTime d) {
    final day = d.day.toString().padLeft(2, '0');
    final month = d.month.toString().padLeft(2, '0');
    final year = d.year.toString();
    return '$month/$day/$year';
  }

  Widget _buildPrimaryContent(Map<String, dynamic> row, ThemeData theme) {
    final primaryField = _getPrimaryField(row);
    final primaryValue = _cleanValue(row[primaryField]);
    
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Icon based on data type
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: const Color(0xFF1565C0).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            _getIconForField(primaryField),
            size: 16,
            color: const Color(0xFF1565C0),
          ),
        ),
        const SizedBox(width: 12),
        // Main content
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    primaryField.toUpperCase().replaceAll('_', ' '),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface.withOpacity(0.55),
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                primaryValue.isEmpty ? '—' : primaryValue,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: primaryValue.isEmpty
                      ? theme.colorScheme.onSurface.withOpacity(0.35)
                      : theme.colorScheme.onSurface,
                  height: 1.25,
                ),
                maxLines: 2, // limit to 2 lines for compactness
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMetaRow(Map<String, dynamic> row, ThemeData theme) {
    final fields = _getSecondaryFields(row);
    if (fields.isEmpty) return const SizedBox.shrink();

    // Horizontal chips to keep height small
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: fields.map((f) {
          final value = _cleanValue(row[f]);
          if (value.isEmpty) return const SizedBox.shrink();
          return Container(
            margin: const EdgeInsets.only(right: 6),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.55),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  f.replaceAll('_', ' ').toUpperCase(),
                  style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface.withOpacity(0.55),
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 10,
                    color: theme.colorScheme.onSurface.withOpacity(0.85),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  String _getPrimaryField(Map<String, dynamic> row) {
    final priorityFields = [
      'content',
      'value',
      'name',
      'title',
      'description',
      'dose',
      'amount',
      'quantity',
      'message'
    ];
    for (final f in priorityFields) {
      if (row.containsKey(f) && !_isKeyField(f) && _cleanValue(row[f]).isNotEmpty) return f;
    }
    // fallback: first non-empty, non key, non timestamp
    final skip = {'created_by'};
    final ts = {'created_at', 'timestamp', 'upload_date'};
    for (final k in row.keys) {
      if (_isKeyField(k) || ts.contains(k) || skip.contains(k)) continue;
      if (_cleanValue(row[k]).isNotEmpty) return k;
    }
    return row.keys.first; // last resort
  }

  List<String> _getSecondaryFields(Map<String, dynamic> row) {
    final primaryField = _getPrimaryField(row);
    final timestampFields = {'created_at', 'timestamp', 'upload_date'};
    final suppressed = {'created_by'}; // shown separately
    final metaPriority = [
      'type',
      'category',
      'unit',
      'status',
      'role',
      'frequency',
      'schedule',
      'profile',
    ];

    bool include(String k) =>
        k != primaryField &&
        !timestampFields.contains(k) &&
        !suppressed.contains(k) &&
        !_isKeyField(k) &&
        _cleanValue(row[k]).isNotEmpty;

    final ordered = <String>[];
    for (final p in metaPriority) {
      if (row.containsKey(p) && include(p)) ordered.add(p);
    }
    // add any remaining fields (still respecting filter)
    for (final k in row.keys) {
      if (!ordered.contains(k) && include(k)) ordered.add(k);
    }
    return ordered.take(5).toList(); // keep compact
  }

  IconData _getIconForField(String field) {
    switch (field.toLowerCase()) {
      case 'content':
      case 'message':
        return Icons.chat_bubble_outline;
      case 'role':
        return Icons.person_outline;
      case 'type':
      case 'category':
        return Icons.category_outlined;
      case 'value':
        return Icons.numbers;
      case 'unit':
        return Icons.straighten;
      case 'processed':
        return Icons.check_circle_outline;
      default:
        return Icons.data_object;
    }
  }

  String _formatTimestamp(Map<String, dynamic> row) {
    final timestampFields = ['created_at', 'timestamp', 'upload_date'];
    
    for (final field in timestampFields) {
      final value = row[field];
      if (value != null) {
        try {
          DateTime dateTime;
          if (value is int) {
            dateTime = DateTime.fromMillisecondsSinceEpoch(value);
          } else if (value is String) {
            dateTime = DateTime.parse(value);
          } else {
            continue;
          }
          
          final hour = dateTime.hour.toString().padLeft(2, '0');
          final minute = dateTime.minute.toString().padLeft(2, '0');
          final day = dateTime.day.toString().padLeft(2, '0');
          final month = dateTime.month.toString().padLeft(2, '0');
          
          return '$day/$month $hour:$minute';
        } catch (e) {
          // Continue to next field if parsing fails
        }
      }
    }
    
    return '';
  }

  bool _isKeyField(String field) {
    final f = field.toLowerCase();
    return f == 'id' ||
        f == 'rowid' ||
        f.endsWith('_id') ||
        f == 'user_id' ||
        f == 'profile_id';
  }

  String _cleanValue(dynamic v) {
    if (v == null) return '';
    final s = v.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }
  Widget _buildPager() {
    final totalPages = (_total / _limit).ceil().clamp(1, 9999);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          Text(
            'Page $_page / $totalPages (total $_total rows)',
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
          const SizedBox(width: 16),
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: _page > 1 && !_loading
                ? () => _fetchRows(page: _page - 1)
                : null,
            tooltip: 'Previous page',
          ),
            IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: _page < totalPages && !_loading
                ? () => _fetchRows(page: _page + 1)
                : null,
            tooltip: 'Next page',
          ),
        ],
      ),
    );
  }
} // end _DataScreenState

class _WeekHeader extends StatelessWidget {
  final String label;
  const _WeekHeader({required this.label});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Row(
        children: [
          Expanded(
            child: Divider(
              color: theme.colorScheme.outline.withOpacity(0.25),
              thickness: 1,
              endIndent: 8,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.primary,
              letterSpacing: 0.4,
            ),
          ),
          Expanded(
            child: Divider(
              color: theme.colorScheme.outline.withOpacity(0.25),
              thickness: 1,
              indent: 8,
            ),
          ),
        ],
      ),
    );
  }
}

class _DayHeaderAndCard extends StatelessWidget {
  final DateTime day;
  final Widget child;
  const _DayHeaderAndCard({required this.day, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final weekday = _weekdayShort(day.weekday);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 50,
          child: Column(
            children: [
              Text(
                weekday,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                day.day.toString(),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.onSurface.withOpacity(0.85),
                ),
              ),
            ],
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _DaySpacerAndCard extends StatelessWidget {
  final Widget child;
  const _DaySpacerAndCard({required this.child});
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(width: 50),
        Expanded(child: child),
      ],
    );
  }
}

String _weekdayShort(int weekday) {
  switch (weekday) {
    case DateTime.monday:
      return 'MON';
    case DateTime.tuesday:
      return 'TUE';
    case DateTime.wednesday:
      return 'WED';
    case DateTime.thursday:
      return 'THU';
    case DateTime.friday:
      return 'FRI';
    case DateTime.saturday:
      return 'SAT';
    case DateTime.sunday:
      return 'SUN';
    default:
      return '';
  }
}
// End of file
