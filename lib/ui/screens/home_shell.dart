import 'package:flutter/material.dart';
import './conversations_screen.dart';
import './medications_screen.dart';
import 'reports_screen.dart';
import 'group_screen.dart';
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
  final _pages = const [ConversationsScreen(), MedicationsScreen(), ReportsScreen(), GroupScreen(), DataScreen()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), label: 'Messages'),
          NavigationDestination(icon: Icon(Icons.medication), label: 'Medications'),
          NavigationDestination(icon: Icon(Icons.description_outlined), label: 'Reports'),
          NavigationDestination(icon: Icon(Icons.group_outlined), label: 'Group'),
          NavigationDestination(icon: Icon(Icons.table_chart_outlined), label: 'Data'),
        ],
      ),
    );
  }
}
