import 'package:flutter/material.dart';
import './conversations_screen.dart';
import './medications_screen.dart';
import 'reports_screen.dart';
import 'activities_screen.dart';
import 'debug_entries_screen.dart';
import 'data_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  // Settings removed from bottom navigation; accessible via top-right user icon in each screen.
  static const List<Widget> _pages = [
    ConversationsScreen(), 
    MedicationsScreen(), 
    ReportsScreen(), 
    ActivitiesScreen(), 
    DataScreen()
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_index],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: Theme.of(context).dividerColor.withOpacity(.6),
              width: 1,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(.04),
              blurRadius: 12,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: NavigationBar(
          height: 64,
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.chat_bubble_outline), label: 'Messages'),
            NavigationDestination(icon: Icon(Icons.medication), label: 'Medications'),
            NavigationDestination(icon: Icon(Icons.description_outlined), label: 'Reports'),
            NavigationDestination(icon: Icon(Icons.local_activity_outlined), label: 'Activities'),
            NavigationDestination(icon: Icon(Icons.table_chart_outlined), label: 'Data'),
          ],
        ),
      ),
    );
  }
}
