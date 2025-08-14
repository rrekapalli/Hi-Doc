import 'package:flutter/material.dart';

class FluidDivider extends StatelessWidget {
  const FluidDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 1,
      child: LayoutBuilder(
        builder: (_, c) => Container(
          width: c.maxWidth,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.transparent, Color(0xFFE2E9F3), Colors.transparent],
              ),
            ),
        ),
      ),
    );
  }
}

const fluidDivider = FluidDivider();