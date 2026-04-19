import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planzers/features/account/presentation/account_menu_button.dart';

class AccountAppBarActions extends ConsumerWidget {
  const AccountAppBarActions({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const AccountMenuButton();
  }
}
