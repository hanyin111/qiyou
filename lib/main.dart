import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_state.dart';
import 'ui/design.dart';
import 'ui/dashboard.dart';
import 'ui/pages.dart';
import 'ui/dialogs.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString('assets/fonts/LICENSE.txt');
    yield LicenseEntryWithLineBreaks(
        ['HarmonyOS Sans SC'], text.replaceAll('\u0000', ''));
  });
  runApp(QiyouApp());
}

class QiyouApp extends StatefulWidget {
  const QiyouApp({super.key, this.state});
  final AppState? state;
  @override
  State<QiyouApp> createState() => _QiyouAppState();
}

class _QiyouAppState extends State<QiyouApp> {
  late final AppState state = widget.state ?? AppState();
  @override
  void dispose() {
    if (widget.state == null) state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: state,
      builder: (context, _) => MaterialApp(
          title: '栖游',
          debugShowCheckedModeBanner: false,
          theme: appTheme(),
          darkTheme: appTheme(dark: true),
          themeMode: state.dark ? ThemeMode.dark : ThemeMode.light,
          home: Home(state: state)));
}

class Home extends StatefulWidget {
  const Home({super.key, this.state});
  final AppState? state;
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with WidgetsBindingObserver {
  late final AppState state;
  late final Timer timer;
  int page = 0;
  final pages = ['游戏', '清单', '账号', '设置'];
  final icons = [
    Icons.grid_view_rounded,
    Icons.checklist_rounded,
    Icons.person_outline_rounded,
    Icons.tune_rounded
  ];
  @override
  void initState() {
    super.initState();
    state = widget.state ?? AppState();
    unawaited(state.initialize());
    WidgetsBinding.instance.addObserver(this);
    timer = Timer.periodic(Duration(seconds: 30), (_) {
      if (mounted) {
        state.checkDay();
        setState(() {});
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState status) {
    if (status == AppLifecycleState.resumed) {
      state.checkDay();
      setState(() {});
    }
  }

  @override
  void dispose() {
    timer.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (widget.state == null) state.dispose();
    super.dispose();
  }

  void goPage(int index) => setState(() => page = index);
  void toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
          SnackBar(content: Text(message), duration: Duration(seconds: 4)));
  }

  Future<void> connect() async {
    final added = await showDialog<bool>(
        context: context, builder: (_) => ConnectDialog(state));
    if (added == true) toast('账号已连接');
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        final desktop = MediaQuery.sizeOf(context).width >= 900;
        return Scaffold(
          bottomNavigationBar: desktop
              ? null
              : NavigationBar(
                  selectedIndex: page,
                  height: 68,
                  backgroundColor: context.palette.surface,
                  indicatorColor: context.palette.selected,
                  onDestinationSelected: goPage,
                  destinations: [
                      for (var i = 0; i < pages.length; i++)
                        NavigationDestination(
                            icon: Icon(icons[i], size: 21), label: pages[i])
                    ]),
          body: SafeArea(
              child: Row(children: [
            if (desktop) _sidebar(),
            Expanded(
                child: Column(children: [
              Padding(
                  padding: EdgeInsets.fromLTRB(
                      desktop ? 36 : 20, 22, desktop ? 36 : 20, 10),
                  child: Row(children: [
                    if (!desktop) Brand(compact: true),
                    Spacer(),
                    if (state.demo)
                      Text('演示',
                          style: TextStyle(
                              fontSize: 11, color: context.palette.secondary)),
                    SizedBox(width: 12),
                    IconButton(
                        tooltip: '账号管理',
                        onPressed: () => goPage(2),
                        icon: Icon(Icons.person_outline_rounded,
                            size: 20, color: context.palette.secondary)),
                  ])),
              if (state.busy)
                LinearProgressIndicator(
                    minHeight: 2, color: context.palette.accent),
              Expanded(
                  child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                          desktop ? 36 : 20, 18, desktop ? 36 : 20, 24),
                      child: Center(
                          child: ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: 1150),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (state.notice != null) ...[
                                      InfoBanner(state.notice!),
                                      SizedBox(height: 18)
                                    ],
                                    switch (page) {
                                      0 => Overview(
                                          state: state,
                                          toast: toast,
                                          goPage: goPage),
                                      1 =>
                                        RoutinePage(state: state, toast: toast),
                                      2 => AccountPage(
                                          state: state,
                                          connect: connect,
                                          toast: toast,
                                          goPage: goPage),
                                      _ => SettingsPage(state: state),
                                    },
                                  ]))))),
            ])),
          ])),
        );
      });
  Widget _sidebar() => Container(
      width: 176,
      decoration: BoxDecoration(
          color: context.palette.surface,
          border: Border(right: BorderSide(color: context.palette.line))),
      padding: EdgeInsets.fromLTRB(19, 30, 19, 22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Brand(compact: true),
        SizedBox(height: 44),
        for (var i = 0; i < pages.length; i++)
          Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Material(
                  color:
                      page == i ? context.palette.selected : Colors.transparent,
                  borderRadius: BorderRadius.circular(11),
                  child: InkWell(
                      borderRadius: BorderRadius.circular(11),
                      onTap: () => goPage(i),
                      child: Padding(
                          padding: EdgeInsets.symmetric(
                              vertical: 14, horizontal: 16),
                          child: Row(children: [
                            Icon(icons[i],
                                size: 18,
                                color: page == i
                                    ? context.palette.accent
                                    : context.palette.secondary),
                            SizedBox(width: 13),
                            Text(pages[i],
                                style: TextStyle(
                                    fontSize: 13,
                                    color: page == i
                                        ? context.palette.accent
                                        : context.palette.secondary,
                                    fontWeight: page == i
                                        ? FontWeight.w600
                                        : FontWeight.w400)),
                          ]))))),
        Spacer(),
        Padding(
            padding: EdgeInsets.only(left: 15),
            child: Text('v0.1.10',
                style:
                    TextStyle(fontSize: 10, color: context.palette.secondary))),
      ]));
}
