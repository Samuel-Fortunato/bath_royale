import 'package:bath_royale/app.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'storage/local_store.dart';
import 'storage/open_store.dart';
import 'auth/production_auth.dart';
import 'state/account_state_scope.dart';
import 'widgets/account_state_provider.dart';
import 'sync/namespace.dart';
import 'pages/authentication.dart';
import 'theme/theme.dart';
import 'state/app_state.dart';
import 'sync/community_catalogue.dart';
import 'sync/http_remote_data_source.dart';
import 'sync/sync_coordinator.dart';
import 'sync/sync_store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  const endpoint = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  runApp(
    endpoint.isEmpty && key.isEmpty
        ? MaterialApp(
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            home: const AuthenticationUnavailablePage(),
          )
        : const AuthenticatedBootstrap(),
  );
}

class AuthenticatedBootstrap extends StatefulWidget {
  final ProductionAuth Function()? createAuth;
  final Future<LocalStore> Function(DataNamespace)? openStore;
  const AuthenticatedBootstrap({super.key, this.createAuth, this.openStore});
  @override
  State<AuthenticatedBootstrap> createState() => _AuthenticatedBootstrapState();
}

class _AuthenticatedBootstrapState extends State<AuthenticatedBootstrap>
    with WidgetsBindingObserver {
  ProductionAuth? auth;
  CommunityCatalogue? community;
  AppState? publicState;
  AccountStateScope? scope;
  String? error;
  bool loading = true;
  bool selecting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load();
  }

  Future<void> load() async {
    try {
      auth =
          widget.createAuth?.call() ??
          ProductionAuth(
            AuthConfiguration(
              const String.fromEnvironment('SUPABASE_URL'),
              const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
            ),
            const PlatformCredentialVault(),
          );
      final config = auth!.configuration;
      final publicStore =
          await (widget.openStore ?? (n) => openLocalStore(namespace: n))(
            DataNamespace.publicCatalogue(config.environment),
          );
      final publicRemote = HttpRemoteDataSource(
        endpoint: Uri.parse('${config.environment}/rest/v1/'),
        environment: config.environment,
        clientKey: config.clientKey,
        accessToken: (_) => null,
      );
      community = CommunityCatalogue(
        SyncCoordinator(
          store: SyncStore(publicStore),
          auth: FakeAuthSession(),
          remote: publicRemote,
          now: () => DateTime.now().millisecondsSinceEpoch,
        ),
        closeRemote: publicRemote.close,
      );
      publicState = AppState(
        currentUserId: 'public',
        bathrooms: [],
        reviews: [],
        visits: [],
        activities: [],
      )..attachCommunity(community!, anonymous: true);
      community!.refresh();
      scope = AccountStateScope.device(
        community: community,
        auth: auth!,
        openStore: widget.openStore ?? (n) => openLocalStore(namespace: n),
      );
      auth!.addListener(select);
      await auth!.restore();
      if (!mounted) return;
      setState(() => loading = false);
      await select();
    } catch (_) {
      if (mounted) {
        setState(() {
          error =
              'Não foi possível preparar a conta. Os ficheiros foram preservados.';
          loading = false;
        });
      }
    }
  }

  Future<void> select() async {
    if (selecting || loading || auth!.busy || !mounted) return;
    selecting = true;
    try {
      while (mounted && !auth!.busy) {
        final target = auth!.current?.namespace;
        if (target == null) {
          error = null;
          break; // Preserve guest and account files; expose no writable guest.
        }
        if (scope!.state?.repository?.store.namespace == target) {
          error = null;
          break;
        }
        final generation = auth!.generation;
        try {
          if (await scope!.select(target)) {
            error = null;
          }
        } catch (_) {
          error = scope!.state?.hasUncommittedWork == true
              ? 'Entra na conta original para terminar ou cancelar o editor e tentar guardar novamente. Os dados continuam na origem.'
              : 'Não foi possível abrir os dados locais. Os ficheiros foram preservados. Tenta novamente ou termina a sessão.';
          if (generation == auth!.generation) break;
        }
        if (generation == auth!.generation) break;
        // A session event overtook even a failed open. Follow the latest
        // identity rather than dropping its notification while selecting.
      }
    } finally {
      selecting = false;
      if (mounted) setState(() {});
    }
  }

  Widget recovery() => ListenableBuilder(
    listenable: auth!,
    builder: (context, _) => MaterialApp(
      key: ValueKey(auth!.current?.namespace),
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: scope?.state?.darkMode == false
          ? ThemeMode.light
          : ThemeMode.dark,
      home: auth!.current == null && error == null
          ? WelcomePage(canTransition: true, catalogue: publicState)
          : AuthenticationPage(
              canTransition:
                  auth!.current == null ||
                  scope?.state?.hasUncommittedWork != true,
              problem: error,
              retry: error != null && !auth!.busy && !selecting ? select : null,
            ),
    ),
  );

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    community?.foreground(state == AppLifecycleState.resumed);
    scope?.state?.synchronization?.foreground(
      state == AppLifecycleState.resumed,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    auth?.removeListener(select);
    // Process teardown cannot persist memory-only drafts.
    if (scope?.state?.hasUncommittedWork != true) scope?.dispose();
    publicState?.dispose();
    community?.dispose();
    auth?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!loading && auth != null && scope != null && scope!.state == null) {
      return ChangeNotifierProvider.value(value: auth!, child: recovery());
    }
    if (loading || scope?.state == null) {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: loading
                ? const CircularProgressIndicator()
                : const AuthenticationUnavailablePage(),
          ),
        ),
      );
    }
    return ChangeNotifierProvider.value(
      value: auth!,
      child: ListenableBuilder(
        listenable: scope!,
        builder: (context, _) => Stack(
          textDirection: TextDirection.ltr,
          children: [
            AccountStateProvider.device(scope: scope!, child: const MainApp()),
            if (!scope!.isAccessible || error != null) recovery(),
          ],
        ),
      ),
    );
  }
}
