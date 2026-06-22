import 'package:flutter/material.dart';
import 'package:planerz/app/theme/neon_palette.dart';

class InviteJoinHead extends StatelessWidget {
  const InviteJoinHead({
    super.key,
    required this.title,
    this.tripName,
    this.stepLabel,
  });

  final String title;
  final String? tripName;
  final String? stepLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 4),
      child: Column(
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              height: 1.15,
              color: NeonPalette.deep,
            ),
          ),
          if (tripName != null && tripName!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '« ${tripName!.trim()} »',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: NeonPalette.text700,
              ),
            ),
          ],
          if (stepLabel != null) ...[
            const SizedBox(height: 6),
            Text(
              stepLabel!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: NeonPalette.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class InviteJoinInfoBanner extends StatelessWidget {
  const InviteJoinInfoBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final bg = Color.lerp(NeonPalette.surface, NeonPalette.success, 0.14)!;
    final border = Color.lerp(NeonPalette.surface, NeonPalette.success, 0.28)!;
    final iconColor = Color.lerp(NeonPalette.deep, NeonPalette.success, 0.80)!;
    final textColor = Color.lerp(NeonPalette.deep, NeonPalette.success, 0.72)!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 22, color: iconColor),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    fontWeight: FontWeight.w500,
                    color: textColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class InviteJoinParticipantTile extends StatelessWidget {
  const InviteJoinParticipantTile({
    super.key,
    required this.displayName,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final String displayName;
  final bool selected;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final trimmed = displayName.trim();
    final initial = trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();

    return Material(
      color: selected
          ? NeonPalette.nameOptionActiveBackground
          : NeonPalette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? NeonPalette.primary : NeonPalette.divider,
          width: selected ? 2 : 1.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: NeonPalette.secondaryTint,
                ),
                child: SizedBox(
                  width: 38,
                  height: 38,
                  child: Center(
                    child: Text(
                      initial,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color.lerp(
                          NeonPalette.deep,
                          NeonPalette.secondary,
                          0.65,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  displayName,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: NeonPalette.deep,
                  ),
                ),
              ),
              _InviteJoinRadio(selected: selected),
            ],
          ),
        ),
      ),
    );
  }
}

class _InviteJoinRadio extends StatelessWidget {
  const _InviteJoinRadio({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? NeonPalette.primary : Colors.transparent,
        border: Border.all(
          color: selected ? NeonPalette.primary : NeonPalette.outline,
          width: 2,
        ),
      ),
      child: selected
          ? const Icon(Icons.circle, size: 10, color: Colors.white)
          : null,
    );
  }
}

class InviteJoinSearchField extends StatefulWidget {
  const InviteJoinSearchField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onChanged,
    this.onClear,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;
  final VoidCallback? onClear;

  @override
  State<InviteJoinSearchField> createState() => _InviteJoinSearchFieldState();
}

class _InviteJoinSearchFieldState extends State<InviteJoinSearchField> {
  late final FocusNode _focusNode = FocusNode()..addListener(_onFocus);

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onText);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    _focusNode
      ..removeListener(_onFocus)
      ..dispose();
    super.dispose();
  }

  void _onFocus() => setState(() {});

  void _onText() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final focused = _focusNode.hasFocus;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: NeonPalette.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: focused ? NeonPalette.primary : NeonPalette.divider,
            width: focused ? 2 : 1.5,
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.search,
              size: 22,
              color: NeonPalette.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: widget.controller,
                focusNode: _focusNode,
                style: const TextStyle(
                  fontSize: 15,
                  color: NeonPalette.deep,
                ),
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  hintStyle: const TextStyle(color: NeonPalette.outline),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                textInputAction: TextInputAction.search,
                onChanged: widget.onChanged,
              ),
            ),
            if (widget.controller.text.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.clear, size: 20),
                color: NeonPalette.onSurfaceVariant,
                onPressed: () {
                  widget.controller.clear();
                  widget.onChanged('');
                  widget.onClear?.call();
                },
              ),
          ],
        ),
      ),
    );
  }
}

class InviteJoinNameRow extends StatelessWidget {
  const InviteJoinNameRow({
    super.key,
    required this.displayName,
    this.editLabel,
    this.onEdit,
  });

  final String displayName;
  final String? editLabel;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              '« $displayName »',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: NeonPalette.deep,
              ),
            ),
          ),
          if (editLabel != null && onEdit != null)
            TextButton.icon(
              onPressed: onEdit,
              style: TextButton.styleFrom(
                foregroundColor: NeonPalette.primary,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: Text(
                editLabel!,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class InviteJoinDualCtaBar extends StatelessWidget {
  const InviteJoinDualCtaBar({
    super.key,
    required this.secondaryLabel,
    required this.primaryLabel,
    required this.onSecondary,
    required this.onPrimary,
    this.secondaryEnabled = true,
    this.primaryEnabled = true,
    this.primaryIcon = Icons.check,
    this.busy = false,
  });

  final String secondaryLabel;
  final String primaryLabel;
  final VoidCallback? onSecondary;
  final VoidCallback? onPrimary;
  final bool secondaryEnabled;
  final bool primaryEnabled;
  final IconData primaryIcon;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: NeonPalette.scaffoldBackground,
        border: Border(top: BorderSide(color: NeonPalette.divider)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 52,
                child: OutlinedButton(
                  onPressed: secondaryEnabled ? onSecondary : null,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: NeonPalette.primary,
                    side: const BorderSide(color: NeonPalette.outline, width: 1.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    secondaryLabel,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 52,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: primaryEnabled && !busy ? [NeonPalette.ctaShadow] : null,
                  ),
                  child: FilledButton.icon(
                    onPressed: primaryEnabled && !busy ? onPrimary : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: NeonPalette.primary,
                      disabledBackgroundColor:
                          Color.lerp(NeonPalette.surface, NeonPalette.outline, 0.18),
                      disabledForegroundColor: NeonPalette.outline,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    icon: busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Icon(primaryIcon, size: 20),
                    label: Text(
                      primaryLabel,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class InviteJoinLoadingStatus extends StatelessWidget {
  const InviteJoinLoadingStatus({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 46,
              height: 46,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: NeonPalette.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                color: NeonPalette.text700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class InviteJoinSuccessStatus extends StatelessWidget {
  const InviteJoinSuccessStatus({
    super.key,
    required this.title,
    required this.subtitle,
    required this.primaryLabel,
    required this.secondaryLabel,
    required this.onPrimary,
    required this.onSecondary,
  });

  final String title;
  final String subtitle;
  final String primaryLabel;
  final String secondaryLabel;
  final VoidCallback onPrimary;
  final VoidCallback onSecondary;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: NeonPalette.success,
              ),
              child: const SizedBox(
                width: 76,
                height: 76,
                child: Icon(Icons.check, size: 44, color: Colors.white),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: NeonPalette.deep,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                height: 1.5,
                color: NeonPalette.text700,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: 300,
              height: 52,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [NeonPalette.ctaShadow],
                ),
                child: FilledButton(
                  onPressed: onPrimary,
                  style: FilledButton.styleFrom(
                    backgroundColor: NeonPalette.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    primaryLabel,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: onSecondary,
              child: Text(
                secondaryLabel,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: NeonPalette.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
