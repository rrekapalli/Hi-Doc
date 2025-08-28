import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Utility to help show the originating Dart file name in AppBar titles during development.
/// In release/profile modes it returns the original widget unchanged.
class DevTitle extends StatelessWidget {
  final String fileName;
  final Widget? child;
  final TextStyle? style;
  const DevTitle(this.fileName,{super.key, this.child, this.style});

  @override
  Widget build(BuildContext context) {
    if (kReleaseMode || kProfileMode) {
      return child ?? const SizedBox.shrink();
    }
    return Row(children:[
      if(child!=null) child! else const SizedBox.shrink(),
      if(child!=null) const SizedBox(width:8),
      Flexible(child: Text('[$fileName]', style: style ?? DefaultTextStyle.of(context).style.copyWith(fontSize: 11, color: const Color(0xFF666666))))
    ]);
  }
}

/// Helper to wrap an existing AppBar title widget (Text typically) with filename tag.
Widget devTitle(BuildContext context, String fileName, Widget title){
  if (kReleaseMode || kProfileMode) return title;
  return LayoutBuilder(builder: (context, constraints){
    return Row(
      mainAxisSize: MainAxisSize.min,
      children:[
        Flexible(child: title),
        const SizedBox(width:6),
        Text('($fileName)', style: const TextStyle(fontSize: 11, color: Color(0xFF666666)), overflow: TextOverflow.ellipsis),
      ],
    );
  });
}
