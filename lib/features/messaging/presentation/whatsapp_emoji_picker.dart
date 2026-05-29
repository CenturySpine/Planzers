import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/foundation.dart' as foundation;
import 'package:flutter/material.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// WhatsApp-style [Config] for [EmojiPicker] (search bar on top, categories at bottom).
Config planerzWhatsAppEmojiPickerConfig(
  BuildContext context, {
  required String noRecentsLabel,
  double? height = 256,
}) {
  final scheme = Theme.of(context).colorScheme;
  final onSurfaceMuted = scheme.onSurface.withValues(alpha: 0.55);
  final emojiSizeMax = 28 *
      (foundation.defaultTargetPlatform == foundation.TargetPlatform.iOS
          ? 1.20
          : 1.0);

  return Config(
    height: height,
    locale: Localizations.localeOf(context),
    checkPlatformCompatibility: true,
    viewOrderConfig: const ViewOrderConfig(
      top: EmojiPickerItem.searchBar,
      middle: EmojiPickerItem.emojiView,
      bottom: EmojiPickerItem.categoryBar,
    ),
    emojiViewConfig: EmojiViewConfig(
      backgroundColor: scheme.surface,
      emojiSizeMax: emojiSizeMax,
      noRecents: Text(
        noRecentsLabel,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: onSurfaceMuted,
            ),
        textAlign: TextAlign.center,
      ),
    ),
    skinToneConfig: const SkinToneConfig(),
    categoryViewConfig: CategoryViewConfig(
      backgroundColor: scheme.surface,
      dividerColor: scheme.surface,
      indicatorColor: scheme.primary,
      iconColorSelected: scheme.onSurface,
      iconColor: onSurfaceMuted,
      customCategoryView: (
        config,
        state,
        tabController,
        pageController,
      ) {
        return PlanerzWhatsAppCategoryView(
          config,
          state,
          tabController,
          pageController,
        );
      },
      categoryIcons: const CategoryIcons(
        recentIcon: Icons.access_time_outlined,
        smileyIcon: Icons.emoji_emotions_outlined,
        animalIcon: Icons.cruelty_free_outlined,
        foodIcon: Icons.coffee_outlined,
        activityIcon: Icons.sports_soccer_outlined,
        travelIcon: Icons.directions_car_filled_outlined,
        objectIcon: Icons.lightbulb_outline,
        symbolIcon: Icons.emoji_symbols_outlined,
        flagIcon: Icons.flag_outlined,
      ),
    ),
    bottomActionBarConfig: BottomActionBarConfig(
      backgroundColor: scheme.surface,
      buttonColor: scheme.surface,
      buttonIconColor: onSurfaceMuted,
    ),
    searchViewConfig: SearchViewConfig(
      backgroundColor: scheme.surface,
      customSearchView: (config, state, showEmojiView) {
        return PlanerzWhatsAppSearchView(config, state, showEmojiView);
      },
    ),
  );
}

/// Embedded or sheet emoji picker with WhatsApp-like layout.
class PlanerzWhatsAppEmojiPicker extends StatelessWidget {
  const PlanerzWhatsAppEmojiPicker({
    super.key,
    this.textEditingController,
    this.scrollController,
    this.onEmojiSelected,
    this.onBackspacePressed,
    this.height = 256,
  });

  final TextEditingController? textEditingController;
  final ScrollController? scrollController;
  final OnEmojiSelected? onEmojiSelected;
  final VoidCallback? onBackspacePressed;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return EmojiPicker(
      textEditingController: textEditingController,
      scrollController: scrollController,
      onEmojiSelected: onEmojiSelected,
      onBackspacePressed: onBackspacePressed,
      config: planerzWhatsAppEmojiPickerConfig(
        context,
        noRecentsLabel: l10n.chatNoRecentEmoji,
        height: height,
      ),
    );
  }
}

/// Opens a bottom sheet to pick a single emoji (e.g. message reaction).
Future<String?> showPlanerzEmojiReactionPicker(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetCtx) {
      final sheetHeight =
          (MediaQuery.sizeOf(sheetCtx).height * 0.45).clamp(280.0, 420.0);
      return SizedBox(
        height: sheetHeight,
        child: PlanerzWhatsAppEmojiPicker(
          height: sheetHeight,
          onEmojiSelected: (_, emoji) =>
              Navigator.pop(sheetCtx, emoji.emoji),
        ),
      );
    },
  );
}

/// Category tabs styled like WhatsApp (circular selection indicator).
class PlanerzWhatsAppCategoryView extends CategoryView {
  const PlanerzWhatsAppCategoryView(
    super.config,
    super.state,
    super.tabController,
    super.pageController, {
    super.key,
  });

  @override
  PlanerzWhatsAppCategoryViewState createState() =>
      PlanerzWhatsAppCategoryViewState();
}

class PlanerzWhatsAppCategoryViewState extends State<PlanerzWhatsAppCategoryView>
    with SkinToneOverlayStateMixin {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: widget.config.categoryViewConfig.backgroundColor,
      child: Row(
        children: [
          Expanded(
            child: PlanerzWhatsAppTabBar(
              widget.config,
              widget.tabController,
              widget.pageController,
              widget.state.categoryEmoji,
              closeSkinToneOverlay,
            ),
          ),
          _buildExtraTab(widget.config.categoryViewConfig.extraTab),
        ],
      ),
    );
  }

  Widget _buildExtraTab(CategoryExtraTab? extraTab) {
    if (extraTab == CategoryExtraTab.BACKSPACE) {
      return BackspaceButton(
        widget.config,
        widget.state.onBackspacePressed,
        widget.state.onBackspaceLongPressed,
        widget.config.categoryViewConfig.backspaceColor,
      );
    }
    if (extraTab == CategoryExtraTab.SEARCH) {
      return SearchButton(
        widget.config,
        widget.state.onShowSearchView,
        widget.config.categoryViewConfig.iconColor,
      );
    }
    return const SizedBox.shrink();
  }
}

class PlanerzWhatsAppTabBar extends StatelessWidget {
  const PlanerzWhatsAppTabBar(
    this.config,
    this.tabController,
    this.pageController,
    this.categoryEmojis,
    this.closeSkinToneOverlay, {
    super.key,
  });

  final Config config;
  final TabController tabController;
  final PageController pageController;
  final List<CategoryEmoji> categoryEmojis;
  final VoidCallback closeSkinToneOverlay;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: config.categoryViewConfig.tabBarHeight,
      child: TabBar(
        labelColor: config.categoryViewConfig.iconColorSelected,
        indicatorColor: config.categoryViewConfig.indicatorColor,
        unselectedLabelColor: config.categoryViewConfig.iconColor,
        dividerColor: config.categoryViewConfig.dividerColor,
        controller: tabController,
        labelPadding: const EdgeInsets.only(top: 1),
        indicatorSize: TabBarIndicatorSize.label,
        indicator: BoxDecoration(
          shape: BoxShape.circle,
          color: config.categoryViewConfig.iconColorSelected
              .withValues(alpha: 0.12),
        ),
        onTap: (index) {
          closeSkinToneOverlay();
          pageController.jumpToPage(index);
        },
        tabs: categoryEmojis
            .asMap()
            .entries
            .map(
              (item) => _buildCategory(item.key, item.value.category),
            )
            .toList(),
      ),
    );
  }

  Widget _buildCategory(int index, Category category) {
    return Tab(
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(
          getIconForCategory(
            config.categoryViewConfig.categoryIcons,
            category,
          ),
          size: 20,
        ),
      ),
    );
  }
}

/// Search bar with horizontal emoji suggestions (WhatsApp-style).
class PlanerzWhatsAppSearchView extends SearchView {
  const PlanerzWhatsAppSearchView(
    super.config,
    super.state,
    super.showEmojiView, {
    super.key,
  });

  @override
  PlanerzWhatsAppSearchViewState createState() =>
      PlanerzWhatsAppSearchViewState();
}

class PlanerzWhatsAppSearchViewState extends SearchViewState {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final emojiSize =
            widget.config.emojiViewConfig.getEmojiSize(constraints.maxWidth);
        final emojiBoxSize = widget.config.emojiViewConfig
            .getEmojiBoxSize(constraints.maxWidth);
        final hintColor =
            widget.config.categoryViewConfig.iconColor.withValues(alpha: 0.7);
        return Container(
          color: widget.config.searchViewConfig.backgroundColor,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: emojiBoxSize + 8,
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  scrollDirection: Axis.horizontal,
                  itemCount: results.length,
                  itemBuilder: (context, index) {
                    return buildEmoji(
                      results[index],
                      emojiSize,
                      emojiBoxSize,
                    );
                  },
                ),
              ),
              Row(
                children: [
                  IconButton(
                    onPressed: widget.showEmojiView,
                    color: widget.config.searchViewConfig.buttonIconColor,
                    icon: const Icon(Icons.arrow_back, size: 20),
                  ),
                  Expanded(
                    child: TextField(
                      onChanged: onTextInputChanged,
                      focusNode: focusNode,
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: widget.config.searchViewConfig.hintText,
                        hintStyle: TextStyle(
                          color: hintColor,
                          fontWeight: FontWeight.normal,
                        ),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
