import 'package:flutter/material.dart';

class HiDocAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String pageTitle;
  final List<Widget>? actions;
  final double subtitleHeight = 36.0;

  const HiDocAppBar({
    super.key,
    required this.pageTitle,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: const Text('Hi-Doc', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
      centerTitle: true,
      actions: actions,
      bottom: PreferredSize(
        preferredSize: Size.fromHeight(subtitleHeight),
        child: Container(
          width: double.infinity,
          height: subtitleHeight,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
                width: 1,
              ),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          alignment: Alignment.centerLeft,
          child: Text(
            pageTitle,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Size get preferredSize => Size.fromHeight(kToolbarHeight + subtitleHeight);
}
