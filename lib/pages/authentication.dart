import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import '../auth/production_auth.dart';
import '../sync/auth_session.dart';
import '../state/app_state.dart';
import '../app.dart';

/// Optional host-owned content; ordinary builds provide no implementation/data.
class AccountEntryExtras {
  final WidgetBuilder? builder;
  const AccountEntryExtras(this.builder);
}

/// Dedicated private flow, also used as the unauthenticated application gate.
class AuthenticationPage extends StatelessWidget {
  final AuthFlow initialFlow;
  final bool canTransition;
  final String? problem;
  final VoidCallback? retry;
  const AuthenticationPage({
    super.key,
    this.initialFlow = AuthFlow.login,
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
              AuthenticationPanel(
                canTransition: canTransition,
                initialFlow: initialFlow,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class WelcomePage extends StatelessWidget {
  final AppState? catalogue;
  final bool canTransition;
  const WelcomePage({super.key, this.canTransition = true, this.catalogue});
  @override
  Widget build(BuildContext context) {
    void open(AuthFlow flow) {
      context.read<ProductionAuth>().clearMessage();
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AuthenticationPage(
            initialFlow: flow,
            canTransition: canTransition,
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Bath Royale')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(24),
              children: [
                const Icon(Icons.wc, size: 64),
                Text(
                  'O teu lugar no trono',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => open(AuthFlow.login),
                  child: const Text('Entrar'),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => open(AuthFlow.registration),
                  child: const Text('Criar conta'),
                ),
                if (canTransition) ...[
                  if (context.watch<AccountEntryExtras?>()?.builder
                      case final builder?)
                    builder(context),
                ],
                if (catalogue != null)
                  TextButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => ChangeNotifierProvider.value(
                          value: catalogue!,
                          child: const MainApp(),
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.explore_outlined),
                    label: const Text('Explorar catálogo sem conta'),
                  ),
                const SizedBox(height: 24),
                const Text(
                  'Os dados anteriores continuam guardados em separado.',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
            'Esta versão não tem um serviço de contas configurado. Usa a versão privada de teste para entrar. Os dados anteriores continuam guardados neste dispositivo, sem serem associados a uma conta. A versão privada configurada permite consultar o catálogo sem conta.',
          ),
        ),
      ),
    ),
  );
}

/// Private authentication controls; never creates public profile metadata.
class AuthenticationPanel extends StatefulWidget {
  final bool canTransition;
  final AuthFlow initialFlow;
  const AuthenticationPanel({
    super.key,
    this.canTransition = true,
    this.initialFlow = AuthFlow.login,
  });
  @override
  State<AuthenticationPanel> createState() => _AuthenticationPanelState();
}

enum AuthFlow {
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
  late AuthFlow flow;
  @override
  void initState() {
    super.initState();
    flow = widget.initialFlow;
  }

  final formKey = GlobalKey<FormState>();
  final passwordFocus = FocusNode();
  bool visible = false;
  String? validation;

  @override
  void dispose() {
    passwordFocus.dispose();
    email.dispose();
    password.dispose();
    code.dispose();
    super.dispose();
  }

  void navigate(AuthFlow next) {
    context.read<ProductionAuth>().clearMessage();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AuthenticationPage(
          initialFlow: next,
          canTransition: widget.canTransition,
        ),
      ),
    );
  }

  Future<void> submit(
    Future<void> Function(ProductionAuth, String, String, String) action, {
    bool requireEmail = false,
    int passwordMinimum = 0,
    bool requireCode = false,
  }) async {
    final auth = context.read<ProductionAuth>();
    final fieldsValid = formKey.currentState?.validate() ?? true;
    String? problem;
    if (!widget.canTransition) {
      problem =
          'Termina ou cancela o editor aberto e tenta guardar novamente antes de mudar de conta.';
    }
    setState(() => validation = problem);
    Scrollable.maybeOf(context)?.position.jumpTo(0);
    if (problem != null || !fieldsValid) return;
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
    if (auth.current != null) TextInput.finishAutofillContext(shouldSave: true);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<ProductionAuth?>();
    if (auth == null) return const SizedBox.shrink();
    final signedIn = auth.current != null;
    final activeFlow = signedIn && auth.needsPasswordChange
        ? AuthFlow.password
        : flow;
    final showForm = !signedIn || activeFlow == AuthFlow.password;
    final passwordFlow = {
      AuthFlow.login,
      AuthFlow.registration,
      AuthFlow.password,
    }.contains(activeFlow);
    final codeFlow = {
      AuthFlow.confirmation,
      AuthFlow.recoveryCode,
    }.contains(activeFlow);
    final title = switch (activeFlow) {
      AuthFlow.login =>
        signedIn ? 'Conta neste dispositivo' : 'Entrar na conta',
      AuthFlow.registration => 'Criar conta',
      AuthFlow.confirmation => 'Confirmar email',
      AuthFlow.recovery => 'Recuperar palavra-passe',
      AuthFlow.recoveryCode => 'Validar recuperação',
      AuthFlow.password => 'Alterar palavra-passe',
    };
    Widget link(String label, AuthFlow next) => TextButton(
      onPressed: auth.busy ? null : () => navigate(next),
      child: Text(label),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: AutofillGroup(
          child: Form(
            key: formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (signedIn)
                  const Text(
                    'Gere a tua sessão. Os dados da conta são guardados automaticamente após a tua aceitação.',
                  ),
                if (signedIn) ...[
                  const SizedBox(height: 12),
                  if (auth.privateEmail != null) Text(auth.privateEmail!),
                  const Text(
                    'Email privado. O nome público é escolhido em separado.',
                  ),
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
                  if (activeFlow != AuthFlow.password)
                    link('Alterar palavra-passe', AuthFlow.password),
                  if (activeFlow != AuthFlow.password)
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
                  if (activeFlow == AuthFlow.registration)
                    Text(
                      auth.configuration.emailConfirmationRequired
                          ? 'Usa pelo menos 8 caracteres. Depois, confirma o email para entrar.'
                          : 'Usa pelo menos 8 caracteres. Nesta alfa local, entras logo após criar a conta, sem confirmar o email.',
                    ),
                  if (activeFlow == AuthFlow.recovery &&
                      auth.configuration.passwordRecoveryAvailable)
                    const Text(
                      'Enviamos instruções para o teu email. Depois, valida o código para escolher uma nova palavra-passe.',
                    ),
                  if (codeFlow)
                    const Text(
                      'Copia o código ou a ligação original do email para aqui.',
                    ),
                  if (!signedIn &&
                      (activeFlow != AuthFlow.recovery ||
                          auth.configuration.passwordRecoveryAvailable))
                    TextFormField(
                      controller: email,
                      validator: (_) =>
                          !signedIn &&
                              !RegExp(
                                r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                              ).hasMatch(email.text.trim())
                          ? 'Introduz um endereço de email válido.'
                          : null,
                      textInputAction: passwordFlow || codeFlow
                          ? TextInputAction.next
                          : TextInputAction.done,
                      onFieldSubmitted: (_) => passwordFocus.requestFocus(),
                      autocorrect: false,
                      enableSuggestions: true,
                      enabled: !auth.busy,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [
                        AutofillHints.username,
                        AutofillHints.email,
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        errorMaxLines: 3,
                      ),
                    ),
                  if (passwordFlow)
                    TextFormField(
                      controller: password,
                      focusNode: passwordFocus,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) {
                        if (!auth.busy) {
                          if (activeFlow == AuthFlow.login) {
                            submit(
                              (a, e, p, _) => a.login(e, p),
                              requireEmail: true,
                              passwordMinimum: 1,
                            );
                          } else if (activeFlow == AuthFlow.registration) {
                            submit(
                              (a, e, p, _) => a.register(e, p),
                              requireEmail: true,
                              passwordMinimum: 8,
                            );
                          }
                        }
                      },
                      validator: (_) => password.text.isEmpty
                          ? 'Introduz a palavra-passe.'
                          : activeFlow != AuthFlow.login &&
                                password.text.length < 8
                          ? 'Usa pelo menos 8 caracteres.'
                          : null,
                      enabled: !auth.busy,
                      obscureText: !visible,
                      enableSuggestions: false,
                      autocorrect: false,
                      autofillHints: [
                        activeFlow == AuthFlow.login
                            ? AutofillHints.password
                            : AutofillHints.newPassword,
                      ],
                      decoration: InputDecoration(
                        errorMaxLines: 3,
                        labelText: activeFlow == AuthFlow.password
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
                    TextFormField(
                      controller: code,
                      validator: (_) => code.text.trim().isEmpty
                          ? 'Introduz o código ou a ligação do email.'
                          : null,
                      enabled: !auth.busy,
                      enableSuggestions: false,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Código ou ligação do email',
                      ),
                    ),
                  if (activeFlow == AuthFlow.recovery &&
                      !auth.configuration.passwordRecoveryAvailable)
                    const Text(
                      'A recuperação da palavra-passe não está disponível nesta alfa local. Guarda a tua palavra-passe; se a perderes, contacta quem gere o teste. Não precisas de criar outra conta para voltar a tentar entrar.',
                    ),
                  if (activeFlow != AuthFlow.recovery ||
                      auth.configuration.passwordRecoveryAvailable)
                    FilledButton(
                      onPressed: auth.busy
                          ? null
                          : () => submit(
                              (a, address, secret, verification) =>
                                  switch (activeFlow) {
                                    AuthFlow.login => a.login(address, secret),
                                    AuthFlow.registration => a.register(
                                      address,
                                      secret,
                                    ),
                                    AuthFlow.confirmation => a.confirm(
                                      address,
                                      verification,
                                      recovery: false,
                                    ),
                                    AuthFlow.recovery => a.recover(address),
                                    AuthFlow.recoveryCode => a.confirm(
                                      address,
                                      verification,
                                      recovery: true,
                                    ),
                                    AuthFlow.password => a.changePassword(
                                      secret,
                                    ),
                                  },
                              requireEmail: !signedIn,
                              passwordMinimum: passwordFlow
                                  ? (activeFlow == AuthFlow.login ? 1 : 8)
                                  : 0,
                              requireCode: codeFlow,
                            ),
                      child: Text(switch (activeFlow) {
                        AuthFlow.login => 'Entrar',
                        AuthFlow.registration => 'Criar conta',
                        AuthFlow.confirmation => 'Confirmar email',
                        AuthFlow.recovery => 'Enviar instruções',
                        AuthFlow.recoveryCode => 'Validar recuperação',
                        AuthFlow.password => 'Guardar palavra-passe',
                      }),
                    ),
                  if (activeFlow == AuthFlow.login && !signedIn) ...[
                    link('Criar conta', AuthFlow.registration),
                    link('Esqueci-me da palavra-passe', AuthFlow.recovery),
                    if (auth.configuration.emailConfirmationRequired)
                      link(
                        'Já tenho um código de confirmação',
                        AuthFlow.confirmation,
                      ),
                  ],
                  if (activeFlow == AuthFlow.registration &&
                      auth.configuration.emailConfirmationRequired)
                    link(
                      'Já recebi o email de confirmação',
                      AuthFlow.confirmation,
                    ),
                  if (activeFlow == AuthFlow.recovery &&
                      auth.configuration.passwordRecoveryAvailable)
                    link(
                      'Já tenho um código de recuperação',
                      AuthFlow.recoveryCode,
                    ),
                  if (activeFlow != AuthFlow.login && !auth.needsPasswordChange)
                    link(
                      signedIn ? 'Voltar à conta' : 'Voltar a entrar',
                      AuthFlow.login,
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
                    'Podes explorar e consultar os rankings sem conta.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
                if (!signedIn && widget.canTransition) ...[
                  if (context.watch<AccountEntryExtras?>()?.builder
                      case final builder?)
                    builder(context),
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
        ),
      ),
    );
  }
}
