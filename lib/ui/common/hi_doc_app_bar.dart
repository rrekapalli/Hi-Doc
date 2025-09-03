import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app_theme.dart';
import '../screens/data_screen.dart';
import '../../providers/selected_profile_provider.dart';
import 'profile_switch_dialog.dart';

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
    final cs = Theme.of(context).colorScheme;
    final canPop = Navigator.of(context).canPop();
    return AppBar(
      centerTitle: true,
      automaticallyImplyLeading: canPop,
  leadingWidth: canPop ? null : 44,
      leading: canPop
          ? null
          : Padding(
              padding: const EdgeInsets.only(left: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.asset(
                  'assets/images/hi-doc.png',
                  width: 28,
                  height: 28,
                  fit: BoxFit.contain,
                ),
              ),
            ),
      title: const Text(
        'Hi-Doc',
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
      actions: [
        // Data explorer shortcut now in top bar
        IconButton(
          tooltip: 'Data',
          icon: const Icon(Icons.table_chart_outlined),
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DataScreen()),
            );
          },
        ),
        Builder(builder: (context) {
          final selectedProfileId = context.watch<SelectedProfileProvider?>()?.selectedProfileId;
          return IconButton(
            tooltip: selectedProfileId == null
                ? 'Switch Profiles'
                : 'Switch Profiles (current: ${selectedProfileId.length > 8 ? selectedProfileId.substring(0,8) : selectedProfileId})',
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () {
              showDialog(
                context: context,
                builder: (_) => const ProfileSwitchDialog(),
              );
            },
          );
        }),
        if (actions != null) ...actions!,
      ],
      bottom: PreferredSize(
        preferredSize: Size.fromHeight(subtitleHeight),
        child: Container(
          width: double.infinity,
          height: subtitleHeight,
          decoration: BoxDecoration(
            color: cs.surface,
            border: Border(
              top: BorderSide(color: AppTheme.line.withValues(alpha: .6), width: 0.6),
              bottom: BorderSide(color: AppTheme.line, width: 1),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          alignment: Alignment.centerLeft,
          child: Text(
            pageTitle,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSoft,
              letterSpacing: .2,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Size get preferredSize => Size.fromHeight(kToolbarHeight + subtitleHeight);
}
