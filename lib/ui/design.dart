import 'package:flutter/material.dart';
import '../domain/models.dart';

class AppPalette {
  const AppPalette(this.text, this.secondary, this.accent, this.background,
      this.surface, this.line, this.selected, this.error);
  final Color text,
      secondary,
      accent,
      background,
      surface,
      line,
      selected,
      error;
  static const light = AppPalette(
      Color(0xFF202124),
      Color(0xFF96999F),
      Color(0xFF242528),
      Color(0xFFF7F7F8),
      Colors.white,
      Color(0xFFEBECEF),
      Color(0xFFF0F1F3),
      Color(0xFFB85B5B));
  static const dark = AppPalette(
      Color(0xFFE8E9EB),
      Color(0xFF858991),
      Color(0xFFE8E9EB),
      Color(0xFF141517),
      Color(0xFF1E2023),
      Color(0xFF2C2F34),
      Color(0xFF2B2E33),
      Color(0xFFDC8D8D));
}

extension PaletteContext on BuildContext {
  AppPalette get palette => Theme.of(this).brightness == Brightness.dark
      ? AppPalette.dark
      : AppPalette.light;
}

ThemeData appTheme({bool dark = false}) {
  final p = dark ? AppPalette.dark : AppPalette.light;
  final scheme = ColorScheme.fromSeed(
      seedColor: p.accent,
      brightness: dark ? Brightness.dark : Brightness.light,
      primary: p.accent,
      onPrimary: p.background,
      surface: p.surface,
      onSurface: p.text,
      surfaceContainerHighest: p.selected,
      outline: p.line,
      error: p.error);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.background,
    fontFamily: 'HarmonyOS Sans SC',
    fontFamilyFallback: const ['Microsoft YaHei', 'PingFang SC', 'sans-serif'],
    textTheme: TextTheme(
        bodyMedium: TextStyle(fontSize: 14, color: p.text, height: 1.6),
        bodySmall: TextStyle(fontSize: 12, color: p.secondary, height: 1.5)),
    dividerColor: p.line,
    dividerTheme: DividerThemeData(color: p.line, thickness: 1),
    iconTheme: IconThemeData(color: p.secondary),
    textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: p.text)),
    navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.surface,
        indicatorColor: p.selected,
        labelTextStyle:
            WidgetStatePropertyAll(TextStyle(fontSize: 10, color: p.text))),
    filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
            backgroundColor: p.accent,
            foregroundColor: p.background,
            padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 15),
            textStyle:
                const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(11)))),
    outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
            foregroundColor: p.text,
            side: BorderSide(color: p.line),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(11)))),
    inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.background,
        contentPadding: const EdgeInsets.all(16),
        border: OutlineInputBorder(
            borderSide: BorderSide.none,
            borderRadius: BorderRadius.circular(12)),
        focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: p.secondary),
            borderRadius: BorderRadius.circular(12))),
    snackBarTheme: SnackBarThemeData(
        backgroundColor: p.accent,
        contentTextStyle: TextStyle(color: p.background),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
    dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
  );
}

String maskedUid(String uid, bool hide) => hide && uid.length > 4
    ? '${uid.substring(0, 3)}•••${uid.substring(uid.length - 3)}'
    : uid;
String clockText(DateTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
String remainingText(Duration? duration) {
  if (duration == null) return '恢复时间暂未提供';
  if (duration.inSeconds <= 0) return '预计已恢复至上限';
  final minutes = (duration.inSeconds / 60).ceil();
  return minutes >= 60
      ? '${minutes ~/ 60} 小时 ${minutes % 60} 分钟后回满'
      : '$minutes 分钟后回满';
}

class Brand extends StatelessWidget {
  const Brand({super.key, this.compact = false});
  final bool compact;
  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
                color: context.palette.accent,
                borderRadius: BorderRadius.circular(10)),
            child: Icon(Icons.layers_outlined,
                color: context.palette.surface, size: 21)),
        const SizedBox(width: 10),
        Text('栖游',
            style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
                color: context.palette.text)),
      ]);
}

class Surface extends StatelessWidget {
  const Surface(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(24),
      this.color});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  @override
  Widget build(BuildContext context) => Container(
      padding: padding,
      decoration: BoxDecoration(
          color: color ?? context.palette.surface,
          border: Border.all(color: context.palette.line),
          borderRadius: BorderRadius.circular(16)),
      child: child);
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color, this.background, this.icon});
  final String text;
  final Color? color, background;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final foreground = color ?? context.palette.secondary;
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color: background ?? context.palette.selected,
            borderRadius: BorderRadius.circular(7)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: foreground),
            const SizedBox(width: 5)
          ],
          Text(text, style: TextStyle(color: foreground, fontSize: 11)),
        ]));
  }
}

class GameMark extends StatelessWidget {
  const GameMark(this.game, {super.key, this.size = 46});
  final Game game;
  final double size;
  @override
  Widget build(BuildContext context) => ClipRRect(
      borderRadius: BorderRadius.circular(size * .24),
      child: Image.asset('assets/games/${game.name}.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
          semanticLabel: '${game.shortTitle}官方图标'));
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: context.palette.text)),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(subtitle!,
                style:
                    TextStyle(fontSize: 11, color: context.palette.secondary))
          ],
        ])),
        if (trailing != null) trailing!,
      ]);
}
