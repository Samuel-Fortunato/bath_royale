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
        'O histórico criado como privado mantém-se privado. Os dados antigos de convidado e exemplos locais não são importados automaticamente.\n\n'
        'Podes editar ou remover as tuas avaliações. Dispositivos sem ligação podem conservar a última cópia recebida até atualizarem. As alterações offline ficam guardadas para envio posterior.\n\n'
        'Este texto explica o funcionamento da alfa. É uma informação provisória de produto; não constitui uma declaração de conformidade legal. As regras definitivas de retenção e eliminação têm de ser definidas antes da abertura a utilizadores reais.',
      ),
    ),
  );
}
