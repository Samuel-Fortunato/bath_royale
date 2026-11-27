import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../models/community_review.dart';
import '../models/bathroom_descriptions.dart';
import '../sync/http_remote_data_source.dart';

Future<String?> communityText(
  BuildContext context,
  String title,
  String help, {
  String initial = '',
}) async {
  var value = initial;
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: TextFormField(
          initialValue: initial,
          onChanged: (v) => value = v,
          maxLength: 500,
          decoration: InputDecoration(helperText: help, helperMaxLines: 5),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, value),
          child: const Text('Guardar'),
        ),
      ],
    ),
  );
}

void communityError(
  BuildContext context,
) => ScaffoldMessenger.of(context).showSnackBar(
  const SnackBar(
    content: Text(
      'Não foi possível guardar esta ação. Confirma os dados e tenta novamente.',
    ),
  ),
);
Future<void> reportCommunityContent(
  BuildContext context,
  String kind,
  String id,
) async {
  final state = context.read<AppState>();
  final value = await communityText(
    context,
    'Denunciar conteúdo',
    'Explica o problema à equipa de teste. A denúncia é privada.',
  );
  if (value == null || !context.mounted) return;
  try {
    state.reportContent(kind, id, value);
    await state.persistenceComplete;
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Denúncia guardada para envio.')),
      );
    }
  } catch (_) {
    if (context.mounted) communityError(context);
  }
}

class CommunityReviewCard extends StatelessWidget {
  final CommunityReview review;
  const CommunityReviewCard({super.key, required this.review});
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Avaliação anónima',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text('★ ${ratingNumber(review.rating)} / 5'),
          Text(
            'Higiene: ${review.hygiene}/4 · Conforto: ${review.comfort}/4\nEstética: ${review.aesthetics}/4 · Papel: ${review.paperAvailability}/2',
          ),
          if (review.comment != null) Text(review.comment!),
          Wrap(
            spacing: 8,
            children: [
              for (final tag in review.tags)
                Chip(label: Text('${tag.emoji} ${tag.label}')),
            ],
          ),
          if (context.read<AppState>().canContribute)
            TextButton(
              onPressed: () =>
                  reportCommunityContent(context, 'review', review.id),
              child: const Text('Denunciar avaliação'),
            ),
        ],
      ),
    ),
  );
}

class CommunityModerationPage extends StatefulWidget {
  const CommunityModerationPage({super.key});
  @override
  State<CommunityModerationPage> createState() =>
      _CommunityModerationPageState();
}

class _CommunityModerationPageState extends State<CommunityModerationPage> {
  List<Map<String, dynamic>>? reports;
  String? error;
  bool busy = false;
  Future<void> load() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final sync = context.read<AppState>().synchronization!;
      final remote = sync.coordinator.remote as HttpRemoteDataSource;
      final rows = await remote.moderationReports(
        sync.coordinator.auth.current!,
      );
      if (mounted) setState(() => reports = rows);
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Apenas a equipa de teste tem acesso. Confirma a sessão e a ligação.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Moderação')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Oculta ou repõe conteúdo público. Os registos privados ficam preservados.',
        ),
        FilledButton(
          onPressed: busy ? null : load,
          child: const Text('Carregar denúncias'),
        ),
        if (error != null) Text(error!),
        if (busy) const LinearProgressIndicator(),
        if (reports?.isEmpty == true) const Text('Sem denúncias.'),
        for (final r in reports ?? <Map<String, dynamic>>[])
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${r['kind']} · ${r['reason']}'),
                  if (r['resolved'] == true) const Text('Resolvida'),
                  Wrap(
                    children: [
                      for (final hide in [true, false])
                        TextButton(
                          onPressed: busy
                              ? null
                              : () async {
                                  setState(() => busy = true);
                                  try {
                                    final sync = context
                                        .read<AppState>()
                                        .synchronization!;
                                    await (sync.coordinator.remote
                                            as HttpRemoteDataSource)
                                        .moderateContent(
                                          sync.coordinator.auth.current!,
                                          r['kind'] as String,
                                          r['target'] as String,
                                          hide,
                                          r['id'] as String,
                                        );
                                    if (!mounted || !context.mounted) return;
                                    context
                                        .read<AppState>()
                                        .community!
                                        .refresh();
                                    await load();
                                  } catch (_) {
                                    if (mounted) {
                                      setState(
                                        () => error =
                                            'Não foi possível moderar. Tenta novamente.',
                                      );
                                    }
                                  } finally {
                                    if (mounted) setState(() => busy = false);
                                  }
                                },
                          child: Text(hide ? 'Ocultar' : 'Repor'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}
