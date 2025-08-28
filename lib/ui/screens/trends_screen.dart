import 'package:flutter/material.dart';
import '../common/hi_doc_app_bar.dart';

class TrendsScreen extends StatelessWidget {
  const TrendsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const HiDocAppBar(pageTitle: 'Trends'),
      body: const Center(
        child: Text(
          'Trends coming soon...\n(Charts & analytics for your health data)',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}
