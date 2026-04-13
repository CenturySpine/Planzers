import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planzers/features/account/presentation/account_menu_button.dart';
import 'package:planzers/features/account/presentation/palette_picker_button.dart';

class AccountAppBarActions extends ConsumerWidget {
  const AccountAppBarActions({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PalettePickerButton(),
        AccountMenuButton(),
      ],
    );
  }
}
