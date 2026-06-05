import 'package:flutter/material.dart';

class RichUiSurfaceTheme {
  final Color surface;
  final Color elevatedSurface;
  final Color primaryText;
  final Color secondaryText;
  final Color border;
  final Color accent;

  const RichUiSurfaceTheme({
    required this.surface,
    required this.elevatedSurface,
    required this.primaryText,
    required this.secondaryText,
    required this.border,
    required this.accent,
  });

  RichUiSurfaceTheme copyWith({
    Color? surface,
    Color? elevatedSurface,
    Color? primaryText,
    Color? secondaryText,
    Color? border,
    Color? accent,
  }) {
    return RichUiSurfaceTheme(
      surface: surface ?? this.surface,
      elevatedSurface: elevatedSurface ?? this.elevatedSurface,
      primaryText: primaryText ?? this.primaryText,
      secondaryText: secondaryText ?? this.secondaryText,
      border: border ?? this.border,
      accent: accent ?? this.accent,
    );
  }
}

class RichUiSurfaceThemeOverride {
  final Color? surface;
  final Color? elevatedSurface;
  final Color? primaryText;
  final Color? secondaryText;
  final Color? border;
  final Color? accent;

  const RichUiSurfaceThemeOverride({
    this.surface,
    this.elevatedSurface,
    this.primaryText,
    this.secondaryText,
    this.border,
    this.accent,
  });
}

class RichUiTheme {
  final RichUiSurfaceTheme chat;
  final RichUiSurfaceTheme zone;
  final RichUiSurfaceTheme support;

  const RichUiTheme({
    required this.chat,
    required this.zone,
    required this.support,
  });

  factory RichUiTheme.defaults() {
    const base = RichUiSurfaceTheme(
      surface: Color(0xFF1F2033),
      elevatedSurface: Color(0xFF2B2C44),
      primaryText: Colors.white,
      secondaryText: Color(0xFFC5C8E2),
      border: Color(0x334E5175),
      accent: Color(0xFF7B68EE),
    );
    return const RichUiTheme(chat: base, zone: base, support: base);
  }

  RichUiTheme merge(RichUiThemeOverride? override) {
    if (override == null) return this;
    return RichUiTheme(
      chat: _mergeSurface(chat, override.chat),
      zone: _mergeSurface(zone, override.zone),
      support: _mergeSurface(support, override.support),
    );
  }

  RichUiSurfaceTheme _mergeSurface(
    RichUiSurfaceTheme base,
    RichUiSurfaceThemeOverride? override,
  ) {
    if (override == null) return base;
    return base.copyWith(
      surface: override.surface,
      elevatedSurface: override.elevatedSurface,
      primaryText: override.primaryText,
      secondaryText: override.secondaryText,
      border: override.border,
      accent: override.accent,
    );
  }
}

class RichUiThemeOverride {
  final RichUiSurfaceThemeOverride? chat;
  final RichUiSurfaceThemeOverride? zone;
  final RichUiSurfaceThemeOverride? support;

  const RichUiThemeOverride({
    this.chat,
    this.zone,
    this.support,
  });
}

class RichUiThemeScope extends InheritedWidget {
  final RichUiTheme theme;

  const RichUiThemeScope({
    super.key,
    required this.theme,
    required super.child,
  });

  static RichUiTheme of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<RichUiThemeScope>()?.theme ??
        RichUiTheme.defaults();
  }

  @override
  bool updateShouldNotify(RichUiThemeScope oldWidget) => theme != oldWidget.theme;
}

class RichUIProvider extends StatelessWidget {
  final RichUiTheme theme;
  final RichUiThemeOverride? themeOverride;
  final Widget child;

  const RichUIProvider({
    super.key,
    required this.theme,
    this.themeOverride,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return RichUiThemeScope(theme: theme.merge(themeOverride), child: child);
  }
}

typedef RichUITheme = RichUiTheme;
typedef RichUIThemeOverride = RichUiThemeOverride;
