import 'package:go_router/go_router.dart';

import '../features/assets/presentation/asset_form_screen.dart';
import '../features/assets/presentation/assets_page.dart';
import '../features/audit/opname_screens.dart';
import '../features/backup/backup_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/import_export/import_export_screen.dart';
import '../features/labels/labels_report_screen.dart';
import '../features/masters/presentation/master_screens.dart';
import '../features/scan/scan_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/sync/sync_screens.dart';
import 'shell.dart';

final appRouter = GoRouter(
  initialLocation: '/dashboard',
  routes: [
    ShellRoute(
      builder: (context, state, child) => AppShell(location: state.uri.path, child: child),
      routes: [
        GoRoute(path: '/dashboard', builder: (c, s) => const DashboardScreen()),
        GoRoute(path: '/assets', builder: (c, s) => const AssetsPage()),
        GoRoute(path: '/assets/new', builder: (c, s) => const AssetFormScreen()),
        GoRoute(path: '/assets/:id', builder: (c, s) => AssetsPage(detailId: s.pathParameters['id'])),
        GoRoute(path: '/assets/:id/edit', builder: (c, s) => AssetFormScreen(assetId: s.pathParameters['id'])),
        GoRoute(path: '/scan', builder: (c, s) => const ScanScreen()),
        GoRoute(path: '/more', builder: (c, s) => const MoreScreen()),
        GoRoute(path: '/more/categories', builder: (c, s) => const CategoriesScreen()),
        GoRoute(path: '/more/locations', builder: (c, s) => const LocationsScreen()),
        GoRoute(path: '/more/people', builder: (c, s) => const PeopleScreen()),
        GoRoute(path: '/more/opname', builder: (c, s) => const OpnameListScreen()),
        GoRoute(path: '/more/opname/:id', builder: (c, s) => OpnameSessionScreen(sessionId: s.pathParameters['id']!)),
        GoRoute(path: '/more/import-export', builder: (c, s) => const ImportExportScreen()),
        GoRoute(path: '/more/backup', builder: (c, s) => const BackupScreen()),
        GoRoute(path: '/more/labels', builder: (c, s) => const LabelsReportScreen()),
        GoRoute(path: '/more/sync', builder: (c, s) => const SyncScreen()),
        GoRoute(path: '/more/conflicts', builder: (c, s) => const ConflictsScreen()),
        GoRoute(path: '/more/settings', builder: (c, s) => const SettingsScreen()),
      ],
    ),
  ],
);
