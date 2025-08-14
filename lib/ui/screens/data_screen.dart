import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
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
        setState(() {
          _tables = (json['tables'] as List).cast<String>();
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
    if (table == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    
    try {
      // Special handling for messages table - query local database
      if (table == 'messages') {
        await _fetchLocalMessages(page: page);
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
                                    Text(
                                      '${_rows.length} records',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: const Color(0xFF1565C0).withOpacity(0.7),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Data rows
                              Expanded(
                                child: ListView.builder(
                                  padding: const EdgeInsets.all(8),
                                  itemCount: _rows.length,
                                  itemBuilder: (context, index) {
                                    final row = _rows[index];
                                    return _buildDataCard(row, index, context);
                                  },
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
          // Primary content row
          _buildPrimaryContent(row, theme),
          if (_getSecondaryFields(row).isNotEmpty) ...[
            const SizedBox(height: 8),
            // Secondary content in a compact grid
            _buildSecondaryContent(row, theme),
          ],
          // Timestamp at bottom right
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                _formatTimestamp(row),
                style: TextStyle(
                  fontSize: 10,
                  color: theme.colorScheme.onSurface.withOpacity(0.5),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryContent(Map<String, dynamic> row, ThemeData theme) {
    final primaryField = _getPrimaryField(row);
    final primaryValue = row[primaryField]?.toString() ?? '';
    
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
              Text(
                primaryField.toUpperCase().replaceAll('_', ' '),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                primaryValue.isEmpty ? '—' : primaryValue,
                style: TextStyle(
                  fontSize: 13,
                  color: primaryValue.isEmpty 
                    ? theme.colorScheme.onSurface.withOpacity(0.4)
                    : theme.colorScheme.onSurface,
                  height: 1.3,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSecondaryContent(Map<String, dynamic> row, ThemeData theme) {
    final secondaryFields = _getSecondaryFields(row);
    
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: secondaryFields.map((field) {
        final value = row[field]?.toString() ?? '';
        if (value.isEmpty) return const SizedBox.shrink();
        
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${field.replaceAll('_', ' ').toUpperCase()}:',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 10,
                    color: theme.colorScheme.onSurface.withOpacity(0.8),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  String _getPrimaryField(Map<String, dynamic> row) {
    // Determine the most important field to display prominently
    final priorityFields = ['content', 'name', 'title', 'description', 'value', 'type'];
    for (final field in priorityFields) {
      if (row.containsKey(field) && row[field]?.toString().isNotEmpty == true) {
        return field;
      }
    }
    // Fallback to first non-empty field
    return row.keys.firstWhere(
      (key) => row[key]?.toString().isNotEmpty == true,
      orElse: () => row.keys.first,
    );
  }

  List<String> _getSecondaryFields(Map<String, dynamic> row) {
    final primaryField = _getPrimaryField(row);
    final timestampFields = ['created_at', 'timestamp', 'upload_date'];
    
    return row.keys
        .where((key) => 
          key != primaryField && 
          !timestampFields.contains(key) &&
          row[key]?.toString().isNotEmpty == true)
        .take(6) // Limit to 6 secondary fields
        .toList();
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

  Widget _buildPager() {
    final totalPages =
        (_total / _limit).ceil().clamp(1, 9999);
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
} // End of file
