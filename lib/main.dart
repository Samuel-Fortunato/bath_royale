import 'package:bath_royale/app.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'state/app_state.dart';
import 'storage/local_store.dart';
import 'storage/open_store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const StorageBootstrap());
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
