import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import '../state/account_state_scope.dart';

/// Test-only Provider lifecycle. The caller owns and disposes the scope.
/// A replacement remounts the entire subtree (including Navigator/routes).
/// Auth loss hides but retains the tree so draft controllers survive renewal.
class AccountStateProvider extends StatelessWidget {
  final AccountStateScope scope;
  final Widget child;
  const AccountStateProvider.forTesting({
    super.key,
    required this.scope,
    required this.child,
  });

  const AccountStateProvider.device({
    super.key,
    required this.scope,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: scope,
    builder: (context, _) {
      final state = scope.state;
      if (state == null) return const SizedBox.shrink();
      return KeyedSubtree(
        key: ObjectKey(state),
        child: ChangeNotifierProvider.value(
          value: state,
          child: Visibility(
            visible: scope.isAccessible,
            maintainState: true,
            child: ExcludeFocus(excluding: !scope.isAccessible, child: child),
          ),
        ),
      );
    },
  );
}
