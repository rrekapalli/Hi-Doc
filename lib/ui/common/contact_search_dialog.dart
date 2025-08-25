import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import '../../services/database_service.dart';
import '../../services/contacts_service.dart';

class ContactSearchDialog extends StatefulWidget {
  const ContactSearchDialog({super.key});

  @override
  State<ContactSearchDialog> createState() => _ContactSearchDialogState();
}

class _ContactSearchDialogState extends State<ContactSearchDialog> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedContactIds = <String>{};
  final DeviceContactsService _contactsService = DeviceContactsService();
  List<Map<String, dynamic>> _contacts = [];
  List<Map<String, dynamic>> _selectedContacts = [];
  bool _isLoading = false;
  String? _error;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _loadContacts();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    // Cancel previous timer
    _debounceTimer?.cancel();
    
    // Set up new timer
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _loadContacts();
    });
  }

  Future<void> _loadContacts() async {
    if (!mounted) return;
    
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final query = _searchController.text.trim();
      
      // Try to load device contacts first (will be empty on web)
      if (kDebugMode) {
        debugPrint('Loading device contacts for query: "$query"');
      }
      final deviceContacts = await _contactsService.searchContacts(query);
      if (kDebugMode) {
        debugPrint('Found ${deviceContacts.length} device contacts');
      }
      
      // Convert contacts to maps for easier UI handling
      final contactMaps = deviceContacts
          .map((contact) => _contactsService.contactToMap(contact))
          .where((contactMap) => contactMap['name'] != 'Unknown' || 
                                contactMap['phone'] != null || 
                                contactMap['email'] != null)
          .toList();
      
      if (kDebugMode) {
        debugPrint('Converted to ${contactMaps.length} contact maps');
      }
      
      // If no device contacts (e.g., on web), fall back to database users
      if (contactMaps.isEmpty) {
        if (kDebugMode) {
          debugPrint('No device contacts found, falling back to database users');
        }
        final db = context.read<DatabaseService>();
        final users = await db.searchUsers(
          query: query.isEmpty ? null : query,
          limit: 50,
        );
        if (kDebugMode) {
          debugPrint('Found ${users.length} database users');
        }
        contactMaps.addAll(users);
      }
      
      // Sort by name
      contactMaps.sort((a, b) => 
          (a['name'] as String).toLowerCase().compareTo(
              (b['name'] as String).toLowerCase()));
      
      if (kDebugMode) {
        debugPrint('Final contact list has ${contactMaps.length} entries');
      }
      
      if (mounted) {
        setState(() {
          _contacts = contactMaps;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error loading contacts: $e');
      }
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _toggleContact(Map<String, dynamic> contact) {
    setState(() {
      final contactId = contact['id'] as String;
      if (_selectedContactIds.contains(contactId)) {
        _selectedContactIds.remove(contactId);
        _selectedContacts.removeWhere((c) => c['id'] == contactId);
      } else {
        _selectedContactIds.add(contactId);
        _selectedContacts.add(contact);
      }
    });
  }

  String _generateProfileTitle() {
    if (_selectedContacts.isEmpty) return 'New Chat';
    if (_selectedContacts.length == 1) {
      return 'Chat with ${_selectedContacts.first['name'] ?? 'Unknown'}';
    }
    final firstName = _selectedContacts.first['name'] ?? 'Unknown';
    return '$firstName & Others';
  }

  Future<void> _createProfile() async {
    if (_selectedContacts.isEmpty) return;

    try {
      final db = context.read<DatabaseService>();
  final title = _generateProfileTitle();
      
      // Create or get user IDs for all selected contacts
      final memberIds = <String>[];
      
      for (final contact in _selectedContacts) {
        final contactName = contact['name'] as String;
        final contactEmail = contact['email'] as String?;
        final contactPhone = contact['phone'] as String?;
        final isDeviceContact = contact['isDeviceContact'] == true;
        
        if (isDeviceContact) {
          // This is a device contact, create as external user
          final userId = await db.createExternalUser(
            name: contactName,
            email: contactEmail,
            phone: contactPhone,
          );
          memberIds.add(userId);
        } else {
          // This is already a registered user
          memberIds.add(contact['id'] as String);
        }
      }
      
      final profileId = await db.createProfile(
        title: title,
        type: memberIds.length == 1 ? 'direct' : 'group',
        memberIds: memberIds,
      );
      
      if (mounted) {
        Navigator.of(context).pop({
          'profileId': profileId,
          'title': title,
          'type': memberIds.length == 1 ? 'direct' : 'group',
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create profile: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Expanded(
                  child: Text(
                    kIsWeb ? 'Select Users' : 'Select Contacts',
                    style: theme.textTheme.headlineSmall,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Search field
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: kIsWeb 
                  ? 'Search users (device contacts not available on web)...'
                  : 'Search contacts...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // Selected contacts chips
            if (_selectedContacts.isNotEmpty) ...[
              Text(
                'Selected (${_selectedContacts.length}):',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: _selectedContacts.map((contact) {
                  return Chip(
                    label: Text(contact['name'] ?? 'Unknown'),
                    onDeleted: () => _toggleContact(contact),
                    deleteIcon: const Icon(Icons.close, size: 16),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
            ],
            
            // Contacts list
            Expanded(
              child: _buildContactsList(),
            ),
            
            // Action buttons
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _selectedContacts.isEmpty ? null : _createProfile,
                  child: const Text('Create Profile Chat'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactsList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Error loading contacts',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadContacts,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    
    if (_contacts.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.people_outline,
              size: 48,
              color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              kIsWeb ? 'No users found' : 'No contacts found',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (kIsWeb) ...[
              const SizedBox(height: 8),
              Text(
                'Device contacts are only available on mobile devices',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      );
    }
    
    return ListView.builder(
      itemCount: _contacts.length,
      itemBuilder: (context, index) {
        final contact = _contacts[index];
        final contactId = contact['id'] as String;
        final isSelected = _selectedContactIds.contains(contactId);
        
        return ListTile(
          onTap: () => _toggleContact(contact),
          leading: Checkbox(
            value: isSelected,
            onChanged: (bool? value) => _toggleContact(contact),
          ),
          title: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundImage: contact['photo_url'] != null
                  ? NetworkImage(contact['photo_url'] as String)
                  : null,
                child: contact['photo_url'] == null
                  ? Text(
                      (contact['name'] as String?)?.substring(0, 1).toUpperCase() ?? '?',
                      style: const TextStyle(fontSize: 16),
                    )
                  : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      contact['name'] ?? 'Unknown',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    if (contact['email'] != null)
                      Text(
                        contact['email'] as String,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    if (contact['phone'] != null && contact['email'] == null)
                      Text(
                        contact['phone'] as String,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
