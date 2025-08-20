import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path_helper;
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/reports_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/report.dart';
import '../../services/reports_service.dart';
import 'user_settings_screen.dart';
import 'report_detail_screen.dart';
import '../common/hi_doc_app_bar.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final ImagePicker _imagePicker = ImagePicker();
  final ReportsService _reportsService = ReportsService();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadReports();
    });
  }

  Future<void> _loadReports() async {
    if (_isLoading) return; // Prevent multiple simultaneous loads
    
    _isLoading = true;
    final reportsProvider = context.read<ReportsProvider>();
    
    // Using prototype user ID for development
    const userId = 'prototype-user-12345';
    await reportsProvider.loadReports(userId);
    _isLoading = false;
  }

  Future<void> _showAddReportDialog() async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Container(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Text(
                'Add Report',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),
              _buildOptionCard(
                context: context,
                icon: Icons.camera_alt,
                title: 'Scan with Camera',
                subtitle: 'Take a photo of your report or prescription',
                onTap: () {
                  Navigator.pop(context);
                  _scanWithCamera();
                },
              ),
              const SizedBox(height: 16),
              _buildOptionCard(
                context: context,
                icon: Icons.file_upload,
                title: 'Upload PDF',
                subtitle: 'Choose a PDF file from your device',
                onTap: () {
                  Navigator.pop(context);
                  _uploadPdf();
                },
              ),
              const SizedBox(height: 16),
              _buildOptionCard(
                context: context,
                icon: Icons.photo_library,
                title: 'Choose Image',
                subtitle: 'Select an image from your gallery',
                onTap: () {
                  Navigator.pop(context);
                  _chooseImage();
                },
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptionCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _scanWithCamera() async {
    try {
      setState(() => _isLoading = true);
      
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );
      
      if (image != null) {
        if (kIsWeb) {
          // On web, use bytes
          final bytes = await image.readAsBytes();
          final fileName = 'Camera_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.jpg';
          await _processSelectedFileBytes(
            bytes,
            fileName,
            ReportSource.camera,
          );
        } else {
          // On mobile/desktop, use file path
          await _processSelectedFile(
            File(image.path),
            ReportSource.camera,
            originalFileName: 'Camera_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.jpg',
          );
        }
      }
    } catch (e) {
      _showErrorSnackBar('Failed to capture image: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _chooseImage() async {
    try {
      setState(() => _isLoading = true);
      
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );
      
      if (image != null) {
        if (kIsWeb) {
          // On web, use bytes
          final bytes = await image.readAsBytes();
          final fileName = image.name;
          await _processSelectedFileBytes(
            bytes,
            fileName,
            ReportSource.upload,
          );
        } else {
          // On mobile/desktop, use file path
          final fileName = image.path.split('/').last;
          await _processSelectedFile(
            File(image.path),
            ReportSource.upload,
            originalFileName: fileName,
          );
        }
      }
    } catch (e) {
      _showErrorSnackBar('Failed to select image: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _uploadPdf() async {
    try {
      setState(() => _isLoading = true);
      
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: false,
      );
      
      if (result != null) {
        final platformFile = result.files.single;
        
        if (kIsWeb) {
          // On web, use bytes instead of file path
          if (platformFile.bytes != null) {
            await _processSelectedFileBytes(
              platformFile.bytes!,
              platformFile.name,
              ReportSource.upload,
            );
          } else {
            _showErrorSnackBar('Failed to read file data');
          }
        } else {
          // On mobile/desktop, use file path
          if (platformFile.path != null) {
            await _processSelectedFile(
              File(platformFile.path!),
              ReportSource.upload,
              originalFileName: platformFile.name,
            );
          } else {
            _showErrorSnackBar('Failed to access file path');
          }
        }
      }
    } catch (e) {
      _showErrorSnackBar('Failed to upload PDF: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _processSelectedFile(
    File file,
    ReportSource source, {
    String? originalFileName,
  }) async {
    try {
      final reportsProvider = context.read<ReportsProvider>();
      
      // Upload file directly to backend instead of saving locally
      const userId = 'prototype-user-12345';
      final report = await reportsProvider.addReportByUpload(
        file: file,
        userId: userId,
        source: source,
        conversationId: 'default-conversation',
      );
      
      if (mounted && report != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Report uploaded successfully'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (mounted) {
        _showErrorSnackBar('Failed to upload report');
      }
    } catch (e) {
      _showErrorSnackBar('Failed to process file: $e');
    }
  }

  Future<void> _processSelectedFileBytes(
    Uint8List bytes,
    String fileName,
    ReportSource source,
  ) async {
    try {
      final reportsProvider = context.read<ReportsProvider>();
      
      // Upload file bytes directly to backend instead of storing locally
      const userId = 'prototype-user-12345';
      final report = await reportsProvider.addReportByUploadBytes(
        bytes: bytes,
        fileName: fileName,
        userId: userId,
        source: source,
        conversationId: 'default-conversation',
      );
      
      if (mounted && report != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Report uploaded successfully'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (mounted) {
        _showErrorSnackBar('Failed to upload report');
      }
    } catch (e) {
      _showErrorSnackBar('Failed to process file: $e');
    }
  }

  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _deleteReport(Report report) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Report'),
        content: Text('Are you sure you want to delete "${report.displayName}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      final reportsProvider = context.read<ReportsProvider>();
      final success = await reportsProvider.removeReport(report.id);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success ? 'Report deleted successfully' : 'Failed to delete report',
            ),
            backgroundColor: success ? Colors.green : Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: HiDocAppBar(
        pageTitle: 'Reports',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadReports,
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: const Icon(Icons.person_outline),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const UserSettingsScreen()),
            ),
          ),
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : Consumer<ReportsProvider>(
            builder: (context, reportsProvider, child) {
              if (reportsProvider.isLoading) {
                return const Center(child: CircularProgressIndicator());
              }

              if (reportsProvider.error != null) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Error loading reports',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        reportsProvider.error!,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _loadReports,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                );
              }

              final reports = reportsProvider.reports;

              if (reports.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.description_outlined,
                        size: 64,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No reports yet',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Scan, upload, or share reports to get started',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: _loadReports,
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: reports.length,
                  itemBuilder: (context, index) {
                    final report = reports[index];
                    return _buildReportCard(report);
                  },
                ),
              );
            },
          ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddReportDialog,
        child: const Icon(Icons.add),
        tooltip: 'Add Report',
      ),
    );
  }

  Widget _buildReportCard(Report report) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
        ),
      ),
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ReportDetailScreen(report: report),
          ),
        ),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      report.typeIcon,
                      style: const TextStyle(fontSize: 20),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          report.displayName,
                          style: Theme.of(context).textTheme.titleMedium,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              report.sourceIcon,
                              style: const TextStyle(fontSize: 12),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              DateFormat('MMM d, y • h:mm a').format(report.createdAt),
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (report.parsed)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green.withOpacity(0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle,
                            size: 14,
                            color: Colors.green[700],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Parsed',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: Colors.green[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'delete') {
                        _deleteReport(report);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, size: 20),
                            SizedBox(width: 8),
                            Text('Delete'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (report.aiSummary != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    report.aiSummary!,
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
