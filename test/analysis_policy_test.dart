import 'package:flutter_test/flutter_test.dart';

import '../tool/check_analysis.dart';

void main() {
  const root = '/project';
  const accepted =
      'INFO|HINT|DEPRECATED_MEMBER_USE|/project/lib/app.dart|2|1|39|'
      "'package:flutter/material.dart' is deprecated and shouldn't be used. "
      'Use package:material_ui/material_ui.dart instead. '
      'This feature was deprecated after v3.47.0-0.0.pre.';

  test('accepts the documented import and allows its line to move', () {
    expect(isAcceptedMaterialImport(accepted, root), isTrue);
    expect(
      isAcceptedMaterialImport(accepted.replaceFirst('|2|', '|3|'), root),
      isTrue,
    );
  });

  test('rejects other infos, deprecations, warnings and errors', () {
    for (final diagnostic in [
      accepted.replaceFirst('INFO', 'WARNING'),
      accepted.replaceFirst('INFO', 'ERROR'),
      accepted.replaceFirst('DEPRECATED_MEMBER_USE', 'UNUSED_IMPORT'),
      accepted.replaceFirst('material.dart', 'widgets.dart'),
      accepted.replaceFirst('|1|39|', '|10|39|'),
    ]) {
      expect(isAcceptedMaterialImport(diagnostic, root), isFalse);
    }
  });

  test('rejects new imports and files outside the repository', () {
    expect(
      isAcceptedMaterialImport(
        accepted.replaceFirst('lib/app.dart', 'lib/new_page.dart'),
        root,
      ),
      isFalse,
    );
    expect(isAcceptedMaterialImport(accepted, '/other'), isFalse);
  });

  test('rejects malformed diagnostics and tool failures', () {
    expect(isAcceptedMaterialImport('', root), isFalse);
    expect(isAcceptedMaterialImport('Analyzer crashed', root), isFalse);
    expect(isAcceptedMaterialImport('$accepted|extra', root), isFalse);
  });
}
