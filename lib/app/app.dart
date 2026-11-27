import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';
import 'router.dart';

class AssetApp extends ConsumerStatefulWidget {
  const AssetApp({super.key, required this.onExit});
  final Future<void> Function() onExit;

  @override
  ConsumerState<AssetApp> createState() => _AssetAppState();
}

class _AssetAppState extends ConsumerState<AssetApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Tutup database dengan aman (wal_checkpoint) dan lepas app.lock saat aplikasi ditutup.
    _lifecycle = AppLifecycleListener(onExitRequested: () async {
      await widget.onExit();
      return AppExitResponse.exit;
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final location = ref.watch(dataLocationProvider);
    final theme = ref.watch(settingsProvider).themeMode;
    return MaterialApp.router(
      title: 'Aset',
      debugShowCheckedModeBanner: false,
      routerConfig: appRouter,
      themeMode: switch (theme) { 'light' => ThemeMode.light, 'dark' => ThemeMode.dark, _ => ThemeMode.system },
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: Colors.indigo, brightness: Brightness.dark, useMaterial3: true),
      builder: (context, child) => Column(children: [
        if (location.fellBackFromPortable)
          Material(
            color: Colors.amber.shade200,
            child: const SafeArea(
              bottom: false,
              child: Padding(
                padding: EdgeInsets.all(8),
                child: Text('Mode non-portabel: data di AppData', style: TextStyle(color: Colors.black87)),
              ),
            ),
          ),
        Expanded(child: child ?? const SizedBox()),
      ]),
    );
  }
}
