import '../auth/alpha_policy.dart';
import 'package:flutter/material.dart';

class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Política de privacidade')),
    body: const SingleChildScrollView(
      padding: EdgeInsets.all(24),
      child: Text(
        'Nesta alfa, os dados da tua conta são guardados no serviço e nos teus dispositivos para permitir sincronização e utilização offline.\n\n'
        'As novas avaliações — notas, etiquetas e comentário — são públicas e anónimas. Não divulgamos o email, identificadores da conta, visitas, datas exatas ou favoritos. Evita escrever dados pessoais no comentário. A equipa pode moderar conteúdo e receber denúncias.\n\n'
        'O feedback da alfa é privado e acessível apenas à equipa administradora. Enviamos o texto que escreves e apenas a versão da aplicação, do sistema e o nome genérico do ecrã. Não capturamos imagens, histórico, rascunhos ou dados de autenticação. Evita incluir dados pessoais no texto.\n\n'
        'O email desta alfa não é verificado e não comprova a identidade de ninguém. Não usamos o acesso a esse email como prova para recuperar uma conta. Guarda um código de recuperação antes de perderes o acesso.\n\n'
        'Suporte e pedidos de eliminação: $alphaSupportContact. Nunca envies a palavra-passe. A recuperação exige uma prova da conta, não apenas o endereço de email. A eliminação inclui os dados privados e as avaliações públicas; cópias offline e backups podem persistir até serem atualizados ou expirarem.\n\n'
        'O histórico criado como privado mantém-se privado. Os dados antigos de convidado e exemplos locais não são importados automaticamente.\n\n'
        'Podes editar ou remover as tuas avaliações. Dispositivos sem ligação podem conservar a última cópia recebida até atualizarem. As alterações offline ficam guardadas para envio posterior.\n\n'
        'Conservamos os dados da conta até um pedido de eliminação com prova de controlo da conta. A pessoa responsável pela alfa faz e verifica cópias de segurança cifradas diariamente, conserva-as durante sete dias e elimina as expiradas. Esta manutenção é manual. O registo mínimo de uma eliminação (identificador da conta e data) mantém-se até expirarem as cópias afetadas, para impedir que uma recuperação reponha esses dados.\n\n'
        'O feedback revisto é eliminado após 90 dias e os registos de pedidos de suporte resolvidos após 30 dias. A pessoa responsável regista estas datas e executa a limpeza. Não prometemos eliminação imediata das cópias offline.\n\n'
        'Este texto explica o funcionamento da alfa e não constitui uma declaração de conformidade legal. O contacto pessoal de suporte aplica-se apenas à alfa inicial. Antes do lançamento público, será substituído por um contacto do projeto e serão implementadas a verificação do email e a recuperação adequadas.',
      ),
    ),
  );
}
