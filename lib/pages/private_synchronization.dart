import 'dart:convert';
import 'package:flutter/material.dart';
import '../sync/private_sync_controller.dart';
import 'privacy.dart';

class PrivateSynchronizationCard extends StatelessWidget {
  final PrivateSyncController sync;
  const PrivateSynchronizationCard({super.key, required this.sync});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: sync,
    builder: (context, _) => Card(
      child: ListTile(
        leading: const Icon(Icons.cloud_sync_outlined),
        title: const Text('Estado dos dados'),
        subtitle: Text(sync.status),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => PrivateSynchronizationPage(sync: sync),
          ),
        ),
      ),
    ),
  );
}

class PrivateSynchronizationPage extends StatelessWidget {
  final PrivateSyncController sync;
  const PrivateSynchronizationPage({super.key, required this.sync});

  String description(Map<String, Object?> row) {
    final p = jsonDecode(row['payload'] as String) as Map;
    final review = p['review'] as Map?;
    if (review != null) {
      final tags = jsonDecode(review['tags'] as String) as List;
      return 'Avaliação: ${review['rating']} ★\nPapel: ${review['paper']} · Higiene: ${review['hygiene']} · Conforto: ${review['comfort']} · Estética: ${review['aesthetics']}\n'
          '${tags.map((t) => '${t['emoji']} ${t['label']}').join(' · ')}\n${review['comment'] ?? ''}';
    }
    if (p['username'] != null) return 'Nome público: ${p['username']}';
    if (p['shared_id'] != null) {
      return 'Associação privada a um trono do catálogo';
    }
    if (p['review_id'] != null) {
      return p['published'] == true
          ? 'Publicar avaliação na comunidade'
          : 'Retirar avaliação da comunidade';
    }
    if (p['reason'] != null) return 'Denúncia: ${p['reason']}';
    if (p['name'] != null) return '${p['emoji']} ${p['name']}';
    if (p['value'] != null) {
      return p['value'] == true ? 'Adicionar favorito' : 'Remover favorito';
    }
    if (row['operation_type'] == 'deleteVisit') {
      return 'Remover visita e a avaliação associada, se existir.';
    }
    if (p['at'] is int) {
      return 'Visita: ${DateTime.fromMicrosecondsSinceEpoch(p['at'] as int).toLocal()}';
    }
    return 'Alteração guardada neste dispositivo';
  }

  Future<void> resolve(BuildContext context, String id, bool resend) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          resend
              ? 'Voltar a enviar esta alteração?'
              : 'Usar os dados da conta?',
        ),
        content: Text(
          resend
              ? 'A tua alteração substituirá a versão apresentada da conta, se entretanto não tiver mudado. A cópia original fica preservada.'
              : 'Os dados recebidos da conta serão usados quando disponíveis. Esta alteração e as alterações que dela dependem ficam no arquivo local abaixo, sem novo envio automático. Podes consultar e copiar o texto para o corrigir num novo registo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    try {
      if (resend) {
        sync.resend(id);
      } else {
        sync.useAccountVersion(id);
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível recuperar. A alteração continua guardada.',
            ),
          ),
        );
      }
    }
  }

  Future<void> correctText(
    BuildContext context,
    Map<String, Object?> issue,
  ) async {
    final p = jsonDecode(issue['payload'] as String) as Map;
    final bathroom = p['name'] != null;
    var edited =
        (bathroom ? p['name'] : (p['review'] as Map)['comment']) as String? ??
        '';
    final key = GlobalKey<FormState>();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(bathroom ? 'Corrigir nome' : 'Corrigir comentário'),
        content: SingleChildScrollView(
          child: Form(
            key: key,
            child: TextFormField(
              initialValue: edited,
              onChanged: (value) => edited = value,
              minLines: bathroom ? 1 : 3,
              maxLines: bathroom ? 2 : 8,
              decoration: InputDecoration(
                labelText: bathroom ? 'Nome da casa de banho' : 'Comentário',
              ),
              validator: (v) {
                final value = (v ?? '').trim();
                if (bathroom && value.isEmpty) {
                  return 'Dá um nome a este trono.';
                }
                if (value.characters.length > (bathroom ? 100 : 500)) {
                  return bathroom
                      ? 'Usa até 100 caracteres.'
                      : 'Usa até 500 caracteres.';
                }
                if (value.contains('\u0000') ||
                    bathroom && value.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
                  return 'Remove os caracteres de controlo.';
                }
                return null;
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (key.currentState!.validate()) {
                Navigator.pop(context, edited);
              }
            },
            child: const Text('Guardar e voltar a enviar'),
          ),
        ],
      ),
    );
    if (value != null) {
      try {
        sync.resend(issue['operation_id'] as String, correctedText: value);
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Não foi possível corrigir. A alteração continua guardada.',
              ),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Estado dos dados')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListenableBuilder(
            listenable: sync,
            builder: (context, _) => ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Semantics(
                  liveRegion: true,
                  child: Text(
                    sync.status,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'As visitas e os favoritos ficam privados. As novas avaliações são públicas e anónimas. O histórico privado anterior fica preservado.',
                ),
                const SizedBox(height: 12),
                if (sync.enabled) ...[
                  FilledButton(
                    onPressed: sync.running ? null : sync.retry,
                    child: const Text('Tentar novamente'),
                  ),
                  TextButton(
                    onPressed: sync.running ? null : sync.replay,
                    child: const Text('Recarregar dados da conta'),
                  ),
                ],
                for (final issue in sync.store.problems)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            issue['state'] == 'conflict'
                                ? 'Alteração em conflito'
                                : 'Alteração recusada',
                          ),
                          Text(
                            issue['error'] == 'authorization'
                                ? 'A conta não tem permissão para esta alteração. A cópia local foi preservada.'
                                : issue['state'] == 'conflict'
                                ? 'Outro dispositivo alterou ou removeu este registo. Escolhe como continuar.'
                                : 'O serviço não aceitou os dados. Guarda o texto abaixo e corrige-o num novo registo, ou volta a tentar.',
                          ),
                          const SizedBox(height: 8),
                          SelectableText(description(issue)),
                          if (issue['remote_payload'] != null)
                            ExpansionTile(
                              title: const Text('Versão da conta'),
                              children: [
                                SelectableText(
                                  issue['remote_deleted'] == 1
                                      ? 'Registo removido na conta.'
                                      : _remoteDescription(issue),
                                ),
                              ],
                            ),
                          TextButton(
                            onPressed: () => resolve(
                              context,
                              issue['operation_id'] as String,
                              false,
                            ),
                            child: const Text(
                              'Usar dados da conta e arquivar alteração',
                            ),
                          ),
                          if (issue['state'] == 'rejected' &&
                              sync.enabled &&
                              ((jsonDecode(issue['payload'] as String)
                                          as Map)['name'] !=
                                      null ||
                                  (jsonDecode(issue['payload'] as String)
                                          as Map)['review'] !=
                                      null))
                            TextButton(
                              onPressed: () => correctText(context, issue),
                              child: const Text(
                                'Corrigir texto e voltar a enviar',
                              ),
                            ),
                          if (issue['remote_deleted'] != 1 && sync.enabled)
                            TextButton(
                              onPressed: () => resolve(
                                context,
                                issue['operation_id'] as String,
                                true,
                              ),
                              child: const Text(
                                'Voltar a enviar a minha alteração',
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                if (sync.store.archives.isNotEmpty)
                  ExpansionTile(
                    title: const Text(
                      'Alterações preservadas neste dispositivo',
                    ),
                    children: [
                      for (final row in sync.store.archives)
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: SelectableText(description(row)),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  String _remoteDescription(Map<String, Object?> issue) {
    final p = jsonDecode(issue['remote_payload'] as String) as Map;
    if (p['comment'] != null || p['rating'] != null) {
      return '${p['rating']} ★\nPapel: ${p['paper']} · Higiene: ${p['hygiene']} · Conforto: ${p['comfort']} · Estética: ${p['aesthetics']}\n${(p['tags'] as List? ?? []).map((t) => '${t['emoji']} ${t['label']}').join(' · ')}\n${p['comment'] ?? ''}';
    }
    if (p['username'] != null) return 'Nome público: ${p['username']}';
    if (p['shared_id'] != null) {
      return 'Associação privada a um trono do catálogo';
    }
    if (p['review_id'] != null) {
      return p['published'] == true
          ? 'Publicar avaliação na comunidade'
          : 'Retirar avaliação da comunidade';
    }
    if (p['reason'] != null) return 'Denúncia: ${p['reason']}';
    if (p['name'] != null) return '${p['emoji']} ${p['name']}';
    if (p['visited_at'] != null) return 'Visita: ${p['visited_at']}';
    if (p['value'] != null) {
      return p['value'] == true ? 'Favorito' : 'Sem favorito';
    }
    return 'Registo privado da conta';
  }
}

/// First-use disclosure also gates existing A2 accounts without upload consent.
/// Acceptance commits locally before any transfer; failure never bypasses it.
class AccountStorageAcceptance extends StatefulWidget {
  final PrivateSyncController sync;
  final VoidCallback logout;
  const AccountStorageAcceptance({
    super.key,
    required this.sync,
    required this.logout,
  });
  @override
  State<AccountStorageAcceptance> createState() =>
      _AccountStorageAcceptanceState();
}

class _AccountStorageAcceptanceState extends State<AccountStorageAcceptance> {
  String? error;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Os dados da tua conta')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              const Icon(Icons.cloud_outlined, size: 48),
              const SizedBox(height: 16),
              const Text(
                'Guardamos os dados da tua conta, incluindo os registos existentes, para os teres nos teus dispositivos. Podes usá-los offline; as alterações são enviadas automaticamente quando há ligação.',
              ),
              const SizedBox(height: 12),
              const Text(
                'As novas avaliações são públicas e anónimas. Visitas, datas exatas, favoritos e email ficam privados. O histórico privado anterior não é publicado.',
              ),
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => const PrivacyPage()),
                ),
                child: const Text('Como tratamos os teus dados'),
              ),
              if (error != null) Text(error!),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  try {
                    // Do not await networking: acceptance and offline access are local.
                    widget.sync.acceptStorage();
                  } catch (_) {
                    setState(
                      () => error =
                          'Não foi possível guardar a aceitação. Os dados continuam preservados. Tenta novamente.',
                    );
                  }
                },
                child: const Text('Aceitar e continuar'),
              ),
              TextButton(
                onPressed: widget.logout,
                child: const Text('Terminar sessão'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
