import 'dart:io';

// Accepted Phase 1 debt. New files and all other diagnostics must pass review.
const materialImportBaseline = {
  // A4 shared Material 3 inputs, reviewed with existing exact baseline.
  'lib/widgets/emoji_input.dart',
  'lib/widgets/accent_picker.dart',
  'test/experience_test.dart',
  'lib/widgets/bathroom_identity.dart',
  'lib/pages/experience_details.dart',
  'lib/app.dart',
  'lib/main.dart',
  'lib/models/bathroom_descriptions.dart',
  'lib/pages/bathroom_details.dart',
  'lib/pages/bathroom_form.dart',
  'lib/pages/collection.dart',
  'lib/pages/explore.dart',
  'lib/pages/home.dart',
  'lib/pages/profile.dart',
  // Reviewed A2 view uses the existing bundled Material 3 widgets.
  'lib/pages/private_synchronization.dart',
  // Reviewed A3 controls use the same bundled Material 3 widgets.
  'lib/pages/community_controls.dart',
  'lib/pages/privacy.dart',
  'tool/local_development.dart',
  'test/community_test.dart',
  'lib/pages/authentication.dart',
  'lib/pages/rankings.dart',
  'lib/pages/review_form.dart',
  'lib/theme/custom_color_roles.dart',
  'lib/theme/theme.dart',
  'lib/widgets/wc_card.dart',
  'test/details_test.dart',
  // Redesign regressions use the same bundled widgets as production.
  'test/redesign_test.dart',
  'test/review_wizard_test.dart',
  'test/collection_profile_test.dart',
  'test/explore_creation_test.dart',
  'test/phase1_audit_test.dart',
  'test/prototype_test.dart',
  'test/rankings_test.dart',
  'test/storage_ui_test.dart',
};

bool isAcceptedMaterialImport(String diagnostic, String projectRoot) {
  final fields = diagnostic.split('|');
  if (fields.length != 8 ||
      fields[0] != 'INFO' ||
      fields[1] != 'HINT' ||
      fields[2] != 'DEPRECATED_MEMBER_USE' ||
      fields[5] != '1' ||
      fields[6] != '39' ||
      fields[7] !=
          "'package:flutter/material.dart' is deprecated and shouldn't be used. "
              'Use package:material_ui/material_ui.dart instead. '
              'This feature was deprecated after v3.47.0-0.0.pre.') {
    return false;
  }
  final prefix = '$projectRoot${Platform.pathSeparator}';
  return fields[3].startsWith(prefix) &&
      materialImportBaseline.contains(fields[3].substring(prefix.length));
}

Future<void> main() async {
  final result = await Process.run(Platform.resolvedExecutable, [
    'analyze',
    '--format=machine',
  ]);
  // Machine diagnostics can appear on either stream across SDK versions.
  final output = '${result.stdout}\n${result.stderr}'.trim();
  if (output.isNotEmpty) stdout.writeln(output);
  final diagnostics = output
      .split('\n')
      .where((line) => line.trim().isNotEmpty);
  if (result.exitCode != 0 ||
      diagnostics.any(
        (line) => !isAcceptedMaterialImport(line, Directory.current.path),
      )) {
    stderr.writeln(
      'Analysis failed: only documented Material imports are accepted.',
    );
    exitCode = 1;
  }
}
