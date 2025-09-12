import 'package:flutter/material.dart';
import './profiles_screen.dart';
import './medications_list_v2_screen.dart';
import 'reports_screen.dart';
import 'activities_screen.dart';
import 'trends_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  // Settings removed from bottom navigation; accessible via top-right user icon in each screen.
  static const List<Widget> _pages = [
    ProfilesScreen(),
    MedicationsListV2Screen(),
    ReportsScreen(),
    ActivitiesScreen(),
    TrendsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RepaintBoundary(
        child: IndexedStack(
          index: _index,
          children: _pages.map((page) => RepaintBoundary(child: page)).toList(),
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: Theme.of(context).dividerColor.withValues(alpha: .6),
              width: 1,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .04),
              blurRadius: 12,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: RepaintBoundary(
          child: NavigationBar(
            height: 64,
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.chat_bubble_outline),
                label: 'Messages',
              ),
              NavigationDestination(
                icon: Icon(Icons.medication),
                label: 'Medications',
              ),
              NavigationDestination(
                icon: Icon(Icons.description_outlined),
                label: 'Reports',
              ),
              NavigationDestination(
                icon: Icon(Icons.local_activity_outlined),
                label: 'Activities',
              ),
              NavigationDestination(
                icon: Icon(Icons.show_chart),
                label: 'Trends',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
