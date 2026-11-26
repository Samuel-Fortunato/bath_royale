import 'package:bath_royale/app.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'state/app_state.dart';
import 'storage/local_store.dart';
import 'storage/open_store.dart';
import 'auth/production_auth.dart';
import 'state/account_state_scope.dart';
import 'widgets/account_state_provider.dart';
import 'sync/namespace.dart';
import 'pages/profile.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  const endpoint = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  runApp(
    endpoint.isEmpty && key.isEmpty
        ? const StorageBootstrap()
        : const AuthenticatedBootstrap(),
  );
}

class StorageBootstrap extends StatefulWidget {
  final Future<LocalStore> Function() openStore;
  const StorageBootstrap({super.key, this.openStore = openLocalStore});
  @override
  State<StorageBootstrap> createState() => _StorageBootstrapState();
}

class _StorageBootstrapState extends State<StorageBootstrap> {
  AppState? _state;
  LocalStore? _store;
  Object? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    LocalStore? store;
    try {
      store = await widget.openStore();
      final state = AppState.restore(store);
      if (!mounted) {
        state.dispose();
        store.close();
        return;
      }
      setState(() {
        _store = store;
        _state = state;
      });
    } catch (error) {
      store?.close();
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  void dispose() {
    _state?.dispose();
    _store?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_state != null) {
      return ChangeNotifierProvider.value(
        value: _state!,
        child: const MainApp(),
      );
    }
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: _error == null
              ? const CircularProgressIndicator()
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Não foi possível abrir os dados locais. Os ficheiros foram preservados. Verifica o armazenamento e tenta novamente.',
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _load,
                        child: const Text('Tentar novamente'),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class AuthenticatedBootstrap extends StatefulWidget {
  const AuthenticatedBootstrap({super.key});
  @override
  State<AuthenticatedBootstrap> createState() => _AuthenticatedBootstrapState();
}

class _AuthenticatedBootstrapState extends State<AuthenticatedBootstrap> {
  ProductionAuth? auth;
  AccountStateScope? scope;
  String? error;
  bool loading = true;
  bool selecting = false;
  bool guestOnly = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final configuration = AuthConfiguration(
        const String.fromEnvironment('SUPABASE_URL'),
        const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
      );
      auth = ProductionAuth(configuration, const PlatformCredentialVault());
      scope = AccountStateScope.device(
        auth: auth!,
        openStore: (n) => openLocalStore(namespace: n),
      );
      await auth!.restore();
      await scope!.select(
        auth!.current?.namespace ?? const DataNamespace.guest(),
      );
      auth!.addListener(select);
      if (mounted) setState(() => loading = false);
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
    if (selecting || auth!.busy || !mounted) return;
    final target = auth!.current?.namespace ?? const DataNamespace.guest();
    if (scope!.state?.repository?.store.namespace == target) return;
    selecting = true;
    try {
      final selected = await scope!.select(target);
      error = null;
      if (!selected) {
        // A session event overtook the open; select the latest identity next.
        Future<void>.delayed(Duration.zero, select);
      }
    } catch (_) {
      error =
          'Volta ao modo convidado ou entra na conta original para terminar ou cancelar o editor e tentar guardar novamente. Os dados continuam na origem.';
    } finally {
      selecting = false;
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    auth?.removeListener(select);
    // Process teardown cannot persist memory-only drafts.
    if (scope?.state?.hasUncommittedWork != true) scope?.dispose();
    auth?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (guestOnly) return const StorageBootstrap();
    if (loading || scope?.state == null) {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: loading
                ? const CircularProgressIndicator()
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(error ?? 'Conta indisponível.'),
                      FilledButton(
                        onPressed: () => setState(() => guestOnly = true),
                        child: const Text('Continuar como convidado'),
                      ),
                    ],
                  ),
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
            if (!scope!.isAccessible)
              MaterialApp(
                home: Scaffold(
                  body: SafeArea(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (error != null) Text(error!),
                        const AuthenticationPanel(),
                        TextButton(
                          onPressed: auth!.busy ? null : auth!.logout,
                          child: const Text('Voltar a convidado'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
