import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../auth/production_auth.dart';
import '../sync/auth_session.dart';
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
            Text(bathroom.name, style: Theme.of(context).textTheme.titleSmall),
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
      state.allBathrooms,
      state.reviews,
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
          padding: const EdgeInsets.all(16),
          children: [
            AuthenticationPanel(canTransition: !state.hasUncommittedWork),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const CircleAvatar(
                          radius: 30,
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
                              const Text('Explorador local'),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 28),
                    const LocalStatistics(includeDiscoveries: true),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
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
                      'O teu favorito nas avaliações',
                      '${rated.first.score.toStringAsFixed(1).replaceAll('.', ',')} / 5\nMédia das tuas ${rated.first.count} avaliações',
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
            const SizedBox(height: 12),
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
            const Divider(height: 1),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Dados locais, sem sincronização. O modo convidado inclui exemplos fictícios.',
              ),
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
        toggleFavorite: () => state.toggleFavorite(entries[index].bathroom.id),
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
                  subtitle: const Text(
                    'A tua escolha fica guardada neste dispositivo.',
                  ),
                  value: state.darkMode,
                  onChanged: (_) => state.toggleTheme(),
                ),
                const Divider(height: 32),
                Text(
                  'Dados locais',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Dados locais, sem sincronização. O modo convidado inclui exemplos fictícios.',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Private authentication controls; never creates public profile metadata.
class AuthenticationPanel extends StatefulWidget {
  final bool canTransition;
  const AuthenticationPanel({super.key, this.canTransition = true});
  @override
  State<AuthenticationPanel> createState() => _AuthenticationPanelState();
}

enum _AuthFlow {
  login,
  registration,
  confirmation,
  recovery,
  recoveryCode,
  password,
}

class _AuthenticationPanelState extends State<AuthenticationPanel> {
  final email = TextEditingController();
  final password = TextEditingController();
  final code = TextEditingController();
  _AuthFlow flow = _AuthFlow.login;
  bool visible = false;
  String? validation;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    code.dispose();
    super.dispose();
  }

  void navigate(_AuthFlow next) {
    password.clear();
    code.clear();
    setState(() {
      flow = next;
      visible = false;
      validation = null;
    });
  }

  Future<void> submit(
    Future<void> Function(ProductionAuth, String, String, String) action, {
    bool requireEmail = false,
    int passwordMinimum = 0,
    bool requireCode = false,
  }) async {
    final auth = context.read<ProductionAuth>();
    String? problem;
    if (!widget.canTransition) {
      problem =
          'Termina ou cancela o editor aberto e tenta guardar novamente antes de mudar de conta.';
    } else if (requireEmail && !email.text.contains('@')) {
      problem = 'Introduz um endereço de email válido.';
    } else if (password.text.length < passwordMinimum) {
      problem = passwordMinimum == 1
          ? 'Introduz a palavra-passe.'
          : 'Usa pelo menos 8 caracteres.';
    } else if (requireCode && code.text.trim().isEmpty) {
      problem = 'Introduz o código ou a ligação do email.';
    }
    setState(() => validation = problem);
    if (problem != null) return;
    final address = email.text;
    final secret = password.text;
    final verification = code.text;
    // Authentication can replace the entire Provider/Navigator tree. Clear
    // controllers before it starts; never touch them after the await.
    password.clear();
    code.clear();
    await action(auth, address, secret, verification);
    if (!mounted) return;
    if (auth.current != null && !auth.needsPasswordChange) {
      setState(() => flow = _AuthFlow.login);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<ProductionAuth?>();
    if (auth == null) return const SizedBox.shrink();
    final signedIn = auth.current != null;
    final activeFlow = signedIn && auth.needsPasswordChange
        ? _AuthFlow.password
        : flow;
    final showForm = !signedIn || activeFlow == _AuthFlow.password;
    final passwordFlow = {
      _AuthFlow.login,
      _AuthFlow.registration,
      _AuthFlow.password,
    }.contains(activeFlow);
    final codeFlow = {
      _AuthFlow.confirmation,
      _AuthFlow.recoveryCode,
    }.contains(activeFlow);
    final title = switch (activeFlow) {
      _AuthFlow.login =>
        signedIn ? 'Conta neste dispositivo' : 'Conta opcional',
      _AuthFlow.registration => 'Criar conta',
      _AuthFlow.confirmation => 'Confirmar email',
      _AuthFlow.recovery => 'Recuperar palavra-passe',
      _AuthFlow.recoveryCode => 'Validar recuperação',
      _AuthFlow.password => 'Alterar palavra-passe',
    };
    Widget link(String label, _AuthFlow next) => TextButton(
      onPressed: auth.busy ? null : () => navigate(next),
      child: Text(label),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text(
              'As visitas, avaliações e favoritos continuam apenas neste dispositivo. Criar uma conta ainda não faz uma cópia de segurança.',
            ),
            if (signedIn) ...[
              const SizedBox(height: 12),
              if (auth.privateEmail != null) Text(auth.privateEmail!),
              const Text('Email privado, sem perfil público.'),
              Text(
                auth.status == SessionStatus.authenticated
                    ? 'Sessão iniciada'
                    : 'Acesso local offline. A sessão remota precisa de renovação.',
              ),
              if (auth.status != SessionStatus.authenticated)
                TextButton(
                  onPressed: auth.busy ? null : auth.renew,
                  child: const Text('Tentar renovar sessão'),
                ),
              if (activeFlow != _AuthFlow.password)
                link('Alterar palavra-passe', _AuthFlow.password),
              TextButton(
                onPressed: auth.busy
                    ? null
                    : () => submit((a, _, _, _) => a.logout()),
                child: const Text('Terminar sessão e voltar a convidado'),
              ),
            ] else
              const Text(
                'Podes continuar como convidado, sem criar uma conta.',
              ),
            if (showForm) ...[
              const SizedBox(height: 12),
              if (activeFlow == _AuthFlow.registration)
                const Text(
                  'Usa pelo menos 8 caracteres. Depois, confirma o email para entrar.',
                ),
              if (activeFlow == _AuthFlow.recovery)
                const Text(
                  'Enviamos instruções para o teu email. Depois, valida o código para escolher uma nova palavra-passe.',
                ),
              if (codeFlow)
                const Text(
                  'Copia o código ou a ligação original do email para aqui.',
                ),
              if (!signedIn)
                TextField(
                  controller: email,
                  enabled: !auth.busy,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
              if (passwordFlow)
                TextField(
                  controller: password,
                  enabled: !auth.busy,
                  obscureText: !visible,
                  enableSuggestions: false,
                  autocorrect: false,
                  autofillHints: [
                    activeFlow == _AuthFlow.login
                        ? AutofillHints.password
                        : AutofillHints.newPassword,
                  ],
                  decoration: InputDecoration(
                    labelText: activeFlow == _AuthFlow.password
                        ? 'Nova palavra-passe'
                        : 'Palavra-passe',
                    suffixIcon: IconButton(
                      tooltip: visible
                          ? 'Ocultar palavra-passe'
                          : 'Mostrar palavra-passe',
                      onPressed: () => setState(() => visible = !visible),
                      icon: Icon(
                        visible ? Icons.visibility_off : Icons.visibility,
                      ),
                    ),
                  ),
                ),
              if (codeFlow)
                TextField(
                  controller: code,
                  enabled: !auth.busy,
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Código ou ligação do email',
                  ),
                ),
              FilledButton(
                onPressed: auth.busy
                    ? null
                    : () => submit(
                        (a, address, secret, verification) =>
                            switch (activeFlow) {
                              _AuthFlow.login => a.login(address, secret),
                              _AuthFlow.registration => a.register(
                                address,
                                secret,
                              ),
                              _AuthFlow.confirmation => a.confirm(
                                address,
                                verification,
                                recovery: false,
                              ),
                              _AuthFlow.recovery => a.recover(address),
                              _AuthFlow.recoveryCode => a.confirm(
                                address,
                                verification,
                                recovery: true,
                              ),
                              _AuthFlow.password => a.changePassword(secret),
                            },
                        requireEmail: !signedIn,
                        passwordMinimum: passwordFlow
                            ? (activeFlow == _AuthFlow.login ? 1 : 8)
                            : 0,
                        requireCode: codeFlow,
                      ),
                child: Text(switch (activeFlow) {
                  _AuthFlow.login => 'Entrar',
                  _AuthFlow.registration => 'Criar conta',
                  _AuthFlow.confirmation => 'Confirmar email',
                  _AuthFlow.recovery => 'Enviar instruções',
                  _AuthFlow.recoveryCode => 'Validar recuperação',
                  _AuthFlow.password => 'Guardar palavra-passe',
                }),
              ),
              if (activeFlow == _AuthFlow.login && !signedIn) ...[
                link('Criar conta', _AuthFlow.registration),
                link('Esqueci-me da palavra-passe', _AuthFlow.recovery),
                link(
                  'Já tenho um código de confirmação',
                  _AuthFlow.confirmation,
                ),
              ],
              if (activeFlow == _AuthFlow.registration)
                link(
                  'Já recebi o email de confirmação',
                  _AuthFlow.confirmation,
                ),
              if (activeFlow == _AuthFlow.recovery)
                link(
                  'Já tenho um código de recuperação',
                  _AuthFlow.recoveryCode,
                ),
              if (activeFlow != _AuthFlow.login && !auth.needsPasswordChange)
                link(
                  signedIn ? 'Voltar à conta' : 'Voltar a entrar',
                  _AuthFlow.login,
                ),
            ],
            if (auth.busy) const LinearProgressIndicator(),
            if (validation != null) Text(validation!),
            if (auth.message != null) Text(auth.message!),
            if (auth.storageBlocked)
              TextButton(
                onPressed: auth.busy ? null : auth.restore,
                child: const Text(
                  'Desbloquear armazenamento seguro e tentar novamente',
                ),
              ),
          ],
        ),
      ),
    );
  }
}
