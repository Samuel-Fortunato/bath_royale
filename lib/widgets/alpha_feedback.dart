import 'dart:convert';
import '../storage/local_store.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../sync/http_remote_data_source.dart';

abstract final class AlphaFeedbackConfig {
  static const enabled = bool.fromEnvironment(
    'BATH_ALPHA_FEEDBACK',
    defaultValue:
        kDebugMode || bool.fromEnvironment('BATH_ISOLATED_DEVELOPMENT'),
  );
  static const onLeft = bool.fromEnvironment('BATH_FEEDBACK_ON_LEFT');
}

/// Only predefined labels leave the device. Never inspect route arguments/URLs.
abstract final class FeedbackLocation {
  static String _home = 'explore';
  static int _reviewStep = 0;
  static final changes = ValueNotifier<int>(0);
  static bool _queued = false;
  static void _changed() {
    if (_queued) return;
    _queued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _queued = false;
      changes.value++;
    });
  }

  static String get home => _home;
  static set home(String value) {
    if (value != _home) {
      _home = value;
      _changed();
    }
  }

  static int get reviewStep => _reviewStep;
  static set reviewStep(int value) {
    if (value != _reviewStep) {
      _reviewStep = value;
      _changed();
    }
  }

  static const screens = {
    'explore',
    'bathroom',
    'collection',
    'diary',
    'rankings',
    'profile',
    'settings',
    'bathroom_form',
    'review_global',
    'review_details',
    'review_tags',
    'experience',
    'privacy',
    'authentication',
    'diagnostics',
    'moderation',
    'feedback_admin',
    'other',
  };
}

class FeedbackNavigatorObserver extends NavigatorObserver with ChangeNotifier {
  final _routes = <Route<dynamic>>[];
  bool _scheduled = false, _disposed = false;
  bool get hasPopup => _routes.lastOrNull is PopupRoute;
  void _changed() {
    if (_scheduled || _disposed) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  String get screen {
    final route = _routes.whereType<PageRoute<dynamic>>().lastOrNull;
    final name = route?.settings.name;
    if (name == '/' || name == null) return FeedbackLocation.home;
    if (name == 'review') {
      return ['review_global', 'review_details', 'review_tags'][FeedbackLocation
          .reviewStep
          .clamp(0, 2)];
    }
    return FeedbackLocation.screens.contains(name) ? name : 'other';
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
    _changed();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _changed();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _changed();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = _routes.indexOf(oldRoute!);
    _changed();
    if (index >= 0) {
      if (newRoute == null) {
        _routes.removeAt(index);
      } else {
        _routes[index] = newRoute;
      }
    }
  }
}

class FeedbackDraft {
  final String id, retryKey;
  FeedbackDraft({String? id, String? retryKey})
    : id = id ?? AppState.newEntityId(),
      retryKey = retryKey ?? AppState.newEntityId();
  factory FeedbackDraft.fromJson(Map<String, dynamic> json) =>
      FeedbackDraft(
          id: json['id'] as String,
          retryKey: json['retryKey'] as String,
        )
        ..category = json['category'] as String
        ..description = json['description'] as String
        ..attempted = (json['attempted'] as Map?)?.cast<String, Object?>();
  Map<String, Object?> toJson() => {
    'id': id,
    'retryKey': retryKey,
    'category': category,
    'description': description,
    'attempted': attempted,
  };
  String category = 'problem', description = '';
  Map<String, Object?>? attempted;
}

typedef FeedbackSender = Future<void> Function(Map<String, Object?> payload);

/// A true floating overlay: leaves the application's viewport and navigation
/// unchanged and stays above bottom actions/keyboard. Modal controls take priority.
class _FeedbackPlacement extends InheritedWidget {
  const _FeedbackPlacement({required super.child});
  @override
  bool updateShouldNotify(_FeedbackPlacement oldWidget) => false;
}

class AlphaFeedbackHost extends StatefulWidget {
  static bool isEnabledIn(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_FeedbackPlacement>() != null;
  const AlphaFeedbackHost({
    super.key,
    required this.child,
    required this.navigatorKey,
    required this.observer,
    this.enabled = AlphaFeedbackConfig.enabled,
    this.send,
    this.metadata,
  });
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;
  final FeedbackNavigatorObserver observer;
  final bool enabled;
  final FeedbackSender? send;
  final Future<Map<String, String>> Function()? metadata;
  @override
  State<AlphaFeedbackHost> createState() => _AlphaFeedbackHostState();
}

class _AlphaFeedbackHostState extends State<AlphaFeedbackHost> {
  FeedbackDraft draft = FeedbackDraft();
  bool opening = false, restored = false, corruptDraft = false;
  LocalStore? local;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (restored) return;
    restored = true;
    local = context.read<AppState>().community?.local;
    final encoded =
        local?.database
                .select('SELECT feedback_draft FROM settings')
                .single['feedback_draft']
            as String?;
    if (encoded != null) {
      try {
        draft = FeedbackDraft.fromJson(
          jsonDecode(encoded) as Map<String, dynamic>,
        );
      } catch (_) {
        corruptDraft = true;
      } // Preserve the original for protected recovery.
    }
  }

  bool persist(FeedbackDraft? next) {
    if (corruptDraft) return false;
    try {
      local?.database.execute('UPDATE settings SET feedback_draft=?', [
        next == null ? null : jsonEncode(next.toJson()),
      ]);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, String>> metadata() async {
    try {
      final values = await const MethodChannel(
        'bath_royale/technical_context',
      ).invokeMapMethod<String, String>('versions');
      if (values != null) return values;
    } on PlatformException {
      /* Unsupported platform uses bounded version below. */
    } on MissingPluginException {
      /* Desktop/test fallback. */
    }
    final version = Platform.operatingSystemVersion.replaceAll(
      RegExp(r'[\x00-\x1f\x7f]'),
      ' ',
    );
    return {
      'app_version': const String.fromEnvironment(
        'BATH_APP_VERSION',
        defaultValue: 'desconhecida',
      ),
      'platform_version':
          '${Platform.operatingSystem} ${version.substring(0, version.length.clamp(0, 70))}',
    };
  }

  Future<void> open() async {
    if (opening) return;
    if (corruptDraft) {
      ScaffoldMessenger.of(
        widget.navigatorKey.currentState!.overlay!.context,
      ).showSnackBar(
        const SnackBar(
          content: Text(
            'O rascunho de feedback precisa de recuperação. Os dados foram preservados.',
          ),
        ),
      );
      return;
    }
    setState(() => opening = true);
    final screen = widget.observer.screen;
    try {
      final info = await (widget.metadata?.call() ?? metadata());
      if (!mounted) return;
      final navContext = widget.navigatorKey.currentState?.overlay?.context;
      if (navContext == null || !navContext.mounted) return;
      final state = context.read<AppState>();
      final remote = state.community?.coordinator.remote;
      final sender =
          widget.send ??
          (Map<String, Object?> payload) async {
            if (remote is! HttpRemoteDataSource) {
              throw StateError('Feedback unavailable');
            }
            await remote.submitFeedback(payload);
          };
      final result = await showDialog<bool>(
        context: navContext,
        barrierDismissible: false,
        routeSettings: const RouteSettings(name: 'feedback_form'),
        builder: (_) => _FeedbackForm(
          draft: draft,
          send: sender,
          persist: persist,
          contextFields: {
            'app_version': info['app_version'] ?? 'desconhecida',
            'platform_version':
                info['platform_version'] ?? Platform.operatingSystem,
            'screen_id': screen,
          },
        ),
      );
      if (result == true && mounted) setState(() => draft = FeedbackDraft());
    } finally {
      if (mounted) setState(() => opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return _FeedbackPlacement(
      child: ListenableBuilder(
        listenable: Listenable.merge([
          widget.observer,
          FeedbackLocation.changes,
        ]),
        builder: (context, _) {
          final media = MediaQuery.of(context);
          final screen = widget.observer.screen;
          final formMargin =
              (screen.startsWith('review_') || screen == 'bathroom_form')
              ? 16.0
              : 96.0;
          return Stack(
            fit: StackFit.expand,
            children: [
              widget.child,
              if (!opening && !widget.observer.hasPopup)
                Positioned(
                  right: AlphaFeedbackConfig.onLeft ? null : 16,
                  left: AlphaFeedbackConfig.onLeft ? 16 : null,
                  bottom:
                      media.viewInsets.bottom +
                      media.padding.bottom +
                      formMargin,
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Semantics(
                      container: true,
                      label: 'Enviar feedback',
                      button: true,
                      excludeSemantics: true,
                      onTap: open,
                      child: FloatingActionButton.small(
                        key: const ValueKey('alpha-feedback-button'),
                        heroTag: null,
                        elevation: 2,
                        focusElevation: 2,
                        hoverElevation: 2,
                        highlightElevation: 2,
                        onPressed: open,
                        child: const Icon(Icons.feedback_outlined),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _FeedbackForm extends StatefulWidget {
  const _FeedbackForm({
    required this.draft,
    required this.send,
    required this.contextFields,
    required this.persist,
  });
  final FeedbackDraft draft;
  final FeedbackSender send;
  final Map<String, String> contextFields;
  final bool Function(FeedbackDraft?) persist;
  @override
  State<_FeedbackForm> createState() => _FeedbackFormState();
}

class _FeedbackFormState extends State<_FeedbackForm> {
  final form = GlobalKey<FormState>();
  late final description = TextEditingController(
    text: widget.draft.description,
  );
  bool sending = false, success = false;
  String? error;
  @override
  void dispose() {
    description.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (sending || !form.currentState!.validate()) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final draft = widget.draft;
    draft.attempted ??= Map.unmodifiable({
      'report_id': draft.id,
      'retry_key': draft.retryKey,
      'category': draft.category,
      'description': draft.description.trim(),
      ...widget.contextFields,
    });
    setState(() {
      sending = true;
      error = null;
    });
    try {
      if (!widget.persist(draft)) {
        throw StateError('Feedback draft could not be saved');
      }
      await widget.send(draft.attempted!);
      if (!widget.persist(null)) {
        throw StateError('Feedback receipt could not be saved');
      }
      if (mounted) setState(() => success = true);
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Não foi possível enviar. O texto está guardado aqui. Tenta novamente mais tarde.',
        );
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !sending,
    child: AlertDialog(
      title: Text(success ? 'Obrigado!' : 'Enviar feedback'),
      content: success
          ? const Text('O teu feedback foi enviado à equipa.')
          : SingleChildScrollView(
              child: Form(
                key: form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: widget.draft.category,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Tipo'),
                      items: const [
                        DropdownMenuItem(
                          value: 'problem',
                          child: Text('Problema'),
                        ),
                        DropdownMenuItem(
                          value: 'suggestion',
                          child: Text('Sugestão'),
                        ),
                        DropdownMenuItem(
                          value: 'other',
                          child: Text('Outro feedback'),
                        ),
                      ],
                      onChanged: sending || widget.draft.attempted != null
                          ? null
                          : (v) => setState(() {
                              widget.draft.category = v!;
                              widget.persist(widget.draft);
                            }),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: description,
                      enabled: !sending && widget.draft.attempted == null,
                      minLines: 3,
                      maxLines: 6,
                      maxLength: 2000,
                      decoration: const InputDecoration(
                        labelText: 'O que aconteceu?',
                        hintText: 'Conta-nos o problema ou a tua ideia.',
                      ),
                      onChanged: (v) {
                        widget.draft.description = v;
                        widget.persist(widget.draft);
                      },
                      validator: (v) =>
                          v == null ||
                              v.trim().characters.length < 5 ||
                              v.trim().characters.length > 2000 ||
                              v.contains('\u0000')
                          ? 'Escreve entre 5 e 2000 caracteres.'
                          : null,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Incluímos a versão da aplicação, do sistema e o nome deste ecrã. Evita dados pessoais.',
                    ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
      actions: success
          ? [
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Fechar'),
              ),
            ]
          : [
              TextButton(
                onPressed: sending ? null : () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: sending ? null : submit,
                child: Text(
                  sending
                      ? 'A enviar…'
                      : error == null && widget.draft.attempted == null
                      ? 'Enviar'
                      : 'Tentar novamente',
                ),
              ),
            ],
    ),
  );
}

class AlphaFeedbackAdminPage extends StatefulWidget {
  const AlphaFeedbackAdminPage({super.key});
  @override
  State<AlphaFeedbackAdminPage> createState() => _AlphaFeedbackAdminPageState();
}

class _AlphaFeedbackAdminPageState extends State<AlphaFeedbackAdminPage> {
  List<Map<String, dynamic>> rows = [];
  bool busy = false, loaded = false;
  String? error;
  int page = 0;
  Future<void> load() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final sync = context.read<AppState>().synchronization!;
      final data = await (sync.coordinator.remote as HttpRemoteDataSource)
          .feedbackReports(sync.coordinator.auth.current!, page);
      if (mounted) {
        setState(() {
          rows = data;
          loaded = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Não foi possível carregar. Confirma a sessão de administrador e a ligação.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!loaded && !busy) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) load();
      });
    }
  }

  Future<void> status(String id, String value) async {
    setState(() => busy = true);
    try {
      final sync = context.read<AppState>().synchronization!;
      await (sync.coordinator.remote as HttpRemoteDataSource).setFeedbackStatus(
        sync.coordinator.auth.current!,
        id,
        value,
      );
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Não foi possível atualizar. Tenta novamente.');
      }
      return;
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (mounted) await load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Feedback da alfa'),
      actions: [
        IconButton(
          tooltip: 'Atualizar feedback',
          onPressed: busy ? null : load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (busy) const LinearProgressIndicator(),
        if (error != null) Text(error!),
        if (loaded && rows.isEmpty)
          const Text('Ainda não há feedback nesta página.'),
        for (final r in rows)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${{'problem': 'Problema', 'suggestion': 'Sugestão', 'other': 'Outro feedback'}[r['category']]} · ${DateTime.parse(r['submitted_at'] as String).toLocal()}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  SelectableText(r['description'] as String),
                  const SizedBox(height: 8),
                  Text(
                    '${r['app_version']} · ${r['platform_version']} · ${r['screen_id']}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  DropdownButton<String>(
                    value: r['status'] as String,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(value: 'new', child: Text('Por ler')),
                      DropdownMenuItem(
                        value: 'reviewed',
                        child: Text('Revisto'),
                      ),
                      DropdownMenuItem(
                        value: 'resolved',
                        child: Text('Resolvido'),
                      ),
                    ],
                    onChanged: busy
                        ? null
                        : (v) => status(r['id'] as String, v!),
                  ),
                ],
              ),
            ),
          ),
        Wrap(
          spacing: 12,
          children: [
            TextButton(
              onPressed: page == 0 || busy
                  ? null
                  : () {
                      page--;
                      load();
                    },
              child: const Text('Anterior'),
            ),
            TextButton(
              onPressed: rows.length < 50 || busy
                  ? null
                  : () {
                      page++;
                      load();
                    },
              child: const Text('Seguinte'),
            ),
          ],
        ),
      ],
    ),
  );
}
