import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth/production_auth.dart';
import '../sync/auth_session.dart';

/// Dedicated private flow, also used as the unauthenticated application gate.
class AuthenticationPage extends StatelessWidget {
  final bool canTransition;
  final String? problem;
  final VoidCallback? retry;
  const AuthenticationPage({
    super.key,
    this.canTransition = true,
    this.problem,
    this.retry,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Bath Royale · Conta')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Icon(Icons.wc, size: 56),
              const SizedBox(height: 12),
              Text(
                'O teu lugar no trono',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              if (problem != null) ...[
                const SizedBox(height: 12),
                Text(problem!),
              ],
              if (retry != null)
                TextButton(
                  onPressed: retry,
                  child: const Text('Tentar novamente'),
                ),
              AuthenticationPanel(canTransition: canTransition),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Public previews carry no backend credentials or writable guest identity.
class AuthenticationUnavailablePage extends StatelessWidget {
  const AuthenticationUnavailablePage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Bath Royale')),
    body: const SafeArea(
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Esta versão não tem um serviço de contas configurado. Usa a versão privada de teste para entrar. Os dados anteriores continuam guardados neste dispositivo, sem serem associados a uma conta. A consulta do catálogo sem conta ficará disponível quando existir um catálogo partilhado.',
          ),
        ),
      ),
    ),
  );
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
    context.read<ProductionAuth>().clearMessage();
    setState(() {
      flow = next;
      visible = false;
      validation = null;
    });
    Scrollable.maybeOf(context)?.position.jumpTo(0);
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
    } else if (requireEmail &&
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.text.trim())) {
      problem = 'Introduz um endereço de email válido.';
    } else if (password.text.length < passwordMinimum) {
      problem = passwordMinimum == 1
          ? 'Introduz a palavra-passe.'
          : 'Usa pelo menos 8 caracteres.';
    } else if (requireCode && code.text.trim().isEmpty) {
      problem = 'Introduz o código ou a ligação do email.';
    }
    setState(() => validation = problem);
    Scrollable.maybeOf(context)?.position.jumpTo(0);
    if (problem != null) return;
    FocusScope.of(context).unfocus();
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
        signedIn ? 'Conta neste dispositivo' : 'Entrar na conta',
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
            if (signedIn)
              const Text(
                'As visitas, avaliações e favoritos continuam apenas neste dispositivo, sem cópia de segurança.',
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
                child: const Text('Terminar sessão'),
              ),
            ] else
              const Text(
                'Entra para criar casas de banho, registar visitas, avaliar e guardar favoritos.',
              ),
            if (validation != null || auth.message != null)
              Semantics(
                liveRegion: true,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    validation ?? auth.message!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ),
            if (showForm) ...[
              const SizedBox(height: 12),
              if (activeFlow == _AuthFlow.registration)
                Text(
                  auth.configuration.emailConfirmationRequired
                      ? 'Usa pelo menos 8 caracteres. Depois, confirma o email para entrar.'
                      : 'Usa pelo menos 8 caracteres. Nesta alfa local, entras logo após criar a conta, sem confirmar o email.',
                ),
              if (activeFlow == _AuthFlow.recovery &&
                  auth.configuration.passwordRecoveryAvailable)
                const Text(
                  'Enviamos instruções para o teu email. Depois, valida o código para escolher uma nova palavra-passe.',
                ),
              if (codeFlow)
                const Text(
                  'Copia o código ou a ligação original do email para aqui.',
                ),
              if (!signedIn &&
                  (activeFlow != _AuthFlow.recovery ||
                      auth.configuration.passwordRecoveryAvailable))
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
                      onPressed: auth.busy
                          ? null
                          : () => setState(() => visible = !visible),
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
              if (activeFlow == _AuthFlow.recovery &&
                  !auth.configuration.passwordRecoveryAvailable)
                const Text(
                  'A recuperação da palavra-passe não está disponível nesta alfa local. Guarda a tua palavra-passe; se a perderes, contacta quem gere o teste. Não precisas de criar outra conta para voltar a tentar entrar.',
                ),
              if (activeFlow != _AuthFlow.recovery ||
                  auth.configuration.passwordRecoveryAvailable)
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
                if (auth.configuration.emailConfirmationRequired)
                  link(
                    'Já tenho um código de confirmação',
                    _AuthFlow.confirmation,
                  ),
              ],
              if (activeFlow == _AuthFlow.registration &&
                  auth.configuration.emailConfirmationRequired)
                link(
                  'Já recebi o email de confirmação',
                  _AuthFlow.confirmation,
                ),
              if (activeFlow == _AuthFlow.recovery &&
                  auth.configuration.passwordRecoveryAvailable)
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
            if (auth.busy)
              const LinearProgressIndicator(semanticsLabel: 'A autenticar'),
            if (!signedIn) ...[
              const SizedBox(height: 12),
              const Text(
                'Os dados anteriores estão preservados em separado: não são apagados, enviados nem associados à conta.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              const Text(
                'O catálogo partilhado ainda não está disponível. Quando existir, poderás consultá-lo sem conta.',
                style: TextStyle(fontSize: 12),
              ),
            ],
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
