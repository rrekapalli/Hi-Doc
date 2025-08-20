import 'package:contacts_service/contacts_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';
import 'package:contacts_service/contacts_service.dart' as contacts_service;

class DeviceContactsService {
  static final DeviceContactsService _instance = DeviceContactsService._internal();
  factory DeviceContactsService() => _instance;
  DeviceContactsService._internal();

  List<Contact>? _cachedContacts;

  /// Request contacts permission
  Future<bool> requestContactsPermission() async {
    // On web, contacts access is not supported
    if (kIsWeb) {
      return false;
    }

    final status = await Permission.contacts.status;
    
    if (status.isGranted) {
      return true;
    }
    
    if (status.isDenied) {
      final result = await Permission.contacts.request();
      return result.isGranted;
    }
    
    return false;
  }

  /// Get all contacts from device
  Future<List<Contact>> getAllContacts() async {
    if (kIsWeb) {
      // For web, return empty list since contacts access is not supported
      // In a real mobile deployment, this would access device contacts
      return [];
    }

    // Check permission first
    final hasPermission = await requestContactsPermission();
    if (!hasPermission) {
      throw Exception('Contacts permission not granted');
    }

    try {
      // Return cached contacts if available
      if (_cachedContacts != null) {
        return _cachedContacts!;
      }

      final contacts = await contacts_service.ContactsService.getContacts(
        withThumbnails: false, // Set to true if you want contact photos
        photoHighResolution: false,
      );
      
      // Cache the contacts
      _cachedContacts = contacts.toList();
      return _cachedContacts!;
    } catch (e) {
      debugPrint('Error loading contacts: $e');
      return [];
    }
  }

  /// Search contacts by name or phone number
  Future<List<Contact>> searchContacts(String query) async {
    if (query.trim().isEmpty) {
      return await getAllContacts();
    }

    final allContacts = await getAllContacts();
    final lowercaseQuery = query.toLowerCase();

    return allContacts.where((contact) {
      final name = contact.displayName?.toLowerCase() ?? '';
      final phones = contact.phones?.map((p) => p.value ?? '').join(' ').toLowerCase() ?? '';
      final emails = contact.emails?.map((e) => e.value ?? '').join(' ').toLowerCase() ?? '';
      
      return name.contains(lowercaseQuery) ||
             phones.contains(lowercaseQuery) ||
             emails.contains(lowercaseQuery);
    }).toList();
  }

  /// Convert Contact to a Map for easier use in UI
  Map<String, dynamic> contactToMap(Contact contact) {
    // Generate a unique identifier for device contacts
    // Use phone or email as primary identifier, fallback to name
    final phone = contact.phones?.isNotEmpty == true ? contact.phones!.first.value : null;
    final email = contact.emails?.isNotEmpty == true ? contact.emails!.first.value : null;
    final name = contact.displayName ?? 'Unknown';
    
    // Create a stable ID for device contacts
    final deviceContactId = phone ?? email ?? 'contact_${name.hashCode}';
    
    return {
      'id': deviceContactId, // Use device-specific ID
      'name': name,
      'email': email,
      'phone': phone,
      'photo_url': null, // contacts_service doesn't provide direct URL access
      'avatar': contact.avatar, // This is byte data for the photo
      'isDeviceContact': true, // Flag to indicate this is from device contacts
    };
  }

  /// Clear cached contacts (call this to refresh contacts)
  void clearCache() {
    _cachedContacts = null;
  }
}
