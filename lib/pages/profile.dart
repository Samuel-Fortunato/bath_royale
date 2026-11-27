import '../widgets/alpha_feedback.dart';
import 'private_synchronization.dart';
import 'community_controls.dart';
import '../auth/production_auth.dart';
import 'privacy.dart';
import '../sync/http_remote_data_source.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import 'authentication.dart';
import '../widgets/wc_card.dart';
import 'collection.dart';
import '../models/ranking.dart';
import '../models/bathroom.dart';
import '../widgets/bathroom_identity.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  Widget _highlight(
    BuildContext context,
    AppState state,
    Bathroom bathroom,
    String title,
    String detail,
  ) => Card(
    color: BathroomIdentity.colors(
      context,
      bathroom,
    ).secondaryContainer.withValues(alpha: .3),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => openCollectedBathroom(context, state, bathroom.id),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BathroomIdentity(bathroom: bathroom, size: 36),
            const SizedBox(height: 8),
            Text(title, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(
              bathroom.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(detail, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final visited =
        state.entries.where((e) => e.activity.visitCount > 0).toList()..sort((
          a,
          b,
        ) {
          final count = b.activity.visitCount.compareTo(a.activity.visitCount);
          if (count != 0) return count;
          final name = a.bathroom.name.toLowerCase().compareTo(
            b.bathroom.name.toLowerCase(),
          );
          return name != 0 ? name : a.bathroom.id.compareTo(b.bathroom.id);
        });
    final rated = rankBathrooms(
      state.visibleBathrooms,
      state.visibleReviews,
      RankingMetric.overall,
      userId: state.currentUserId,
    );
    void open(String title, Widget page) => Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ChangeNotifierProvider.value(
          value: state,
          child: Scaffold(
            appBar: AppBar(title: Text(title)),
            body: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: page,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const CircleAvatar(
                          radius: 22,
                          child: Icon(Icons.person_outline, size: 30),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'O teu perfil',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              Text(
                                context
                                        .watch<ProductionAuth?>()
                                        ?.privateEmail ??
                                    'Explorador local',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 16),
                    const LocalStatistics(includeDiscoveries: true),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                final sideBySide =
                    constraints.maxWidth >= 340 &&
                    MediaQuery.textScalerOf(context).scale(14) <= 18;
                final highlights = <Widget>[
                  if (visited.isNotEmpty)
                    _highlight(
                      context,
                      state,
                      visited.first.bathroom,
                      'O teu trono habitual',
                      '${visited.first.activity.visitCount} visitas',
                    ),
                  if (rated.isNotEmpty)
                    _highlight(
                      context,
                      state,
                      rated.first.bathroom,
                      'Mais bem avaliado',
                      '★ ${rated.first.score.toStringAsFixed(1).replaceAll('.', ',')} · ${rated.first.count} avaliações',
                    ),
                ];
                return sideBySide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final card in highlights) Expanded(child: card),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: highlights,
                      );
              },
            ),
            if (visited.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'A próxima visita pode revelar o teu trono habitual.',
                ),
              ),
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(
                Icons.favorite,
                color: Theme.of(context).colorScheme.tertiary,
              ),
              title: const Text('Os meus favoritos'),
              subtitle: Text(
                '${state.entries.where((e) => e.activity.isFavorite).length} favoritos',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => open('Os meus favoritos', const FavouritesList()),
            ),
          ],
        ),
      ),
    );
  }
}

class FavouritesList extends StatelessWidget {
  const FavouritesList({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final entries = state.entries.where((e) => e.activity.isFavorite).toList();
    if (entries.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Guarda os teus tronos preferidos com o coração. ♥'),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: entries.length,
      itemBuilder: (context, index) => WcCard(
        entry: entries[index],
        toggleFavorite: state.readOnly
            ? null
            : () => state.toggleFavorite(entries[index].bathroom.id),
        onTap: () =>
            openCollectedBathroom(context, state, entries[index].bathroom.id),
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Definições')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Aparência',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Modo escuro'),

                  value: state.darkMode,
                  onChanged: state.readOnly ? null : (_) => state.toggleTheme(),
                ),
                const Divider(height: 32),
                if (!state.hasUncommittedWork) ...[
                  if (context.watch<AccountEntryExtras?>()?.builder
                      case final builder?)
                    builder(context),
                ],
                if (context.watch<ProductionAuth?>() != null)
                  Card(
                    child: ListTile(
                      title: const Text('Conta e segurança'),
                      subtitle: Text(
                        context.watch<ProductionAuth?>()?.privateEmail ?? '',
                      ),
                      leading: const Icon(Icons.manage_accounts_outlined),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          settings: const RouteSettings(name: 'authentication'),
                          builder: (_) => AuthenticationPage(
                            canTransition: !state.hasUncommittedWork,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (state.synchronization case final sync?)
                  ListenableBuilder(
                    listenable: sync,
                    builder: (context, _) => sync.store.archives.isEmpty
                        ? const SizedBox.shrink()
                        : ListTile(
                            title: const Text('Alterações preservadas'),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                settings: const RouteSettings(
                                  name: 'diagnostics',
                                ),
                                builder: (_) =>
                                    PrivateSynchronizationPage(sync: sync),
                              ),
                            ),
                          ),
                  ),
                if (state.isModerator)
                  ListTile(
                    leading: const Icon(Icons.feedback_outlined),
                    title: const Text('Feedback da alfa'),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        settings: const RouteSettings(name: 'feedback_admin'),
                        builder: (_) => ChangeNotifierProvider.value(
                          value: state,
                          child: const AlphaFeedbackAdminPage(),
                        ),
                      ),
                    ),
                  ),
                if (state.isModerator)
                  TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        settings: const RouteSettings(name: 'moderation'),
                        builder: (_) => ChangeNotifierProvider.value(
                          value: state,
                          child: const CommunityModerationPage(),
                        ),
                      ),
                    ),
                    child: const Text('Moderação'),
                  ),
                if (state.isModerator)
                  TextButton(
                    onPressed: () => grantCreation(context, state),
                    child: const Text('Permitir criar casas de banho'),
                  ),
                if (state.legacyBathrooms.isNotEmpty)
                  ListTile(
                    title: const Text('Registos anteriores'),
                    subtitle: const Text(
                      'Histórico preservado, sem publicação automática',
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => ChangeNotifierProvider.value(
                          value: state,
                          child: const LegacyHistoryPage(),
                        ),
                      ),
                    ),
                  ),
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      settings: const RouteSettings(name: 'privacy'),
                      builder: (_) => const PrivacyPage(),
                    ),
                  ),
                  child: const Text('Política de privacidade'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> grantCreation(BuildContext context, AppState state) async {
  final email = await communityText(
    context,
    'Permitir criar casas de banho',
    'Email privado da conta a autorizar. A permissão mantém-se até ser retirada.',
  );
  if (email == null || !context.mounted) return;
  try {
    final sync = state.synchronization!;
    await (sync.coordinator.remote as HttpRemoteDataSource)
        .grantBathroomCreation(sync.coordinator.auth.current!, email, true);
    await sync.retry();
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Permissão atualizada.')));
    }
  } catch (_) {
    if (context.mounted) communityError(context);
  }
}

class LegacyHistoryPage extends StatelessWidget {
  const LegacyHistoryPage({super.key});
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Registos anteriores')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Estes registos foram guardados como privados. Continuam preservados, com as referências originais. Não foram publicados nem associados automaticamente a outros tronos. Podes consultar e copiar o texto para recuperação.',
          ),
          for (final b in state.legacyBathrooms)
            ExpansionTile(
              title: Text(b.name),
              children: [
                for (final v in state.visits.where(
                  (v) =>
                      v.bathroomId == b.id && v.userId == state.currentUserId,
                ))
                  ListTile(
                    title: Text(v.visitedAt.toLocal().toString()),
                    subtitle: SelectableText(
                      state.reviewForVisit(v.id)?.comment ??
                          'Visita sem avaliação',
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
