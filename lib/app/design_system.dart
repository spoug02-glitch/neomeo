import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class NeomeDesignSystem {
  // Colors
  static const Color primary = Color(0xFFFF4500);
  static const Color background = Color(0xFFF2F4F6);
  static const Color surface = Colors.white;
  static const Color textMain = Color(0xFF191F28);
  static const Color textSub = Color(0xFF8B95A1);
  static const Color textHint = Color(0xFFADB5BD);
  static const Color border = Color(0xFFE5E8EB);
  
  // Spacing
  static const double spacingBase = 8.0;
  static const double spacingXS = 4.0;
  static const double spacingS = 12.0;
  static const double spacingM = 16.0;
  static const double spacingL = 24.0;
  static const double spacingXL = 32.0;

  // Typography (Moderate sizes as requested)
  static const TextStyle heading1 = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.bold,
    color: textMain,
    letterSpacing: -0.5,
  );

  static const TextStyle heading2 = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.bold,
    color: textMain,
    letterSpacing: -0.3,
  );

  static const TextStyle body1 = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    color: textMain,
  );

  static const TextStyle body2 = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.normal,
    color: textSub,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.normal,
    color: textHint,
  );
}

class NeomeBottomNav extends StatelessWidget {
  final int currentIndex;
  const NeomeBottomNav({super.key, required this.currentIndex});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: NeomeDesignSystem.border, width: 1)),
      ),
      child: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: (i) {
          if (i == 0) context.go('/home');
          if (i == 1) context.go('/settings');
          if (i == 2) context.go('/calendar');
        },
        backgroundColor: Colors.white,
        selectedItemColor: NeomeDesignSystem.textMain,
        unselectedItemColor: NeomeDesignSystem.textSub,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        unselectedLabelStyle: const TextStyle(fontSize: 12),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home), label: '홈'),
          BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), activeIcon: Icon(Icons.settings), label: '설정'),
          BottomNavigationBarItem(icon: Icon(Icons.calendar_month_outlined), activeIcon: Icon(Icons.calendar_month), label: '달력'),
        ],
      ),
    );
  }
}

class WindowLogo extends StatelessWidget {
  final double size;
  final Color color;

  const WindowLogo({
    super.key,
    this.size = 40,
    this.color = NeomeDesignSystem.primary,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          // Outer frame
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: color, width: size * 0.08),
              borderRadius: BorderRadius.circular(size * 0.15),
            ),
          ),
          // Horizontal divider
          Center(
            child: Container(
              height: size * 0.08,
              width: size,
              color: color,
            ),
          ),
          // Vertical divider
          Center(
            child: Container(
              width: size * 0.08,
              height: size,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
