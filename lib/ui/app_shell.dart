import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'fluent_button.dart';
import '../widgets/theme_toggle.dart';

class AppShell extends StatelessWidget {
  final Widget child;
  final String title;
  final List<Widget> actions;
  final int currentIndex;
  final ValueChanged<int> onNav;
  final List<Widget> topActions;
  final List<String> navItems;

  const AppShell({
    super.key,
    required this.child,
    required this.title,
    required this.currentIndex,
    required this.onNav,
    this.actions = const [],
    this.topActions = const [],
    this.navItems = const ['Tableau', 'Patients', 'Rendez-vous'],
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.pageBg(context),
      body: Column(
        children: [
          _TopBar(title: title, actions: actions, topActions: topActions),
          if (navItems.isNotEmpty)
            _TabBarModern(
              items: navItems,
              currentIndex: currentIndex,
              onTap: onNav,
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final String title;
  final List<Widget> actions;
  final List<Widget> topActions;

  const _TopBar({
    required this.title,
    required this.actions,
    required this.topActions,
  });

  List<_TopActionItem> _parseTopActions({
    required bool compact,
  }) {
    final items = <_TopActionItem>[];
    for (final action in topActions) {
      if (action is SizedBox && action.child == null) continue;
      if (action is FluentButton) {
        final showLabel = !compact;
        final button = FluentButton(
          label: action.label,
          icon: action.icon,
          onPressed: action.onPressed,
          type: action.type,
          showLabel: showLabel,
          compact: compact,
        );
        items.add(
          _TopActionItem(
            widget: showLabel ? button : Tooltip(message: action.label, child: button),
            label: action.label,
            icon: action.icon,
            onPressed: action.onPressed,
            canOverflow: true,
          ),
        );
        continue;
      }
      items.add(_TopActionItem(widget: action));
    }
    return items;
  }

  Widget _buildOverflowMenu(
    BuildContext context,
    List<_TopActionItem> items, {
    required bool compact,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return PopupMenuButton<int>(
      tooltip: 'Plus d actions',
      onSelected: (index) => items[index].onPressed?.call(),
      itemBuilder: (context) {
        return List.generate(items.length, (i) {
          final item = items[i];
          return PopupMenuItem<int>(
            value: i,
            child: Row(
              children: [
                if (item.icon != null)
                  Icon(item.icon, size: 18, color: scheme.onSurface)
                else
                  const SizedBox(width: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(item.label ?? 'Action')),
              ],
            ),
          );
        });
      },
      child: Builder(
        builder: (context) {
          final scheme = Theme.of(context).colorScheme;
          final ink = AppTheme.ink1(context);
          return Container(
            padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 14, vertical: compact ? 10 : 12),
            decoration: BoxDecoration(
              color: AppTheme.raised(context),
              borderRadius: BorderRadius.circular(AppTheme.rButton),
              border: Border.all(color: scheme.outline),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.more_horiz, color: ink, size: 18),
                if (!compact) ...[
                  const SizedBox(width: 6),
                  Text('Plus', style: TextStyle(color: ink, fontWeight: FontWeight.w600)),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildNarrowActions(BuildContext context, double width) {
    final isCompact = width < 720;
    final maxVisible = width < 620 ? 2 : (width < 820 ? 3 : 4);
    final parsed = _parseTopActions(compact: isCompact);
    final visible = <Widget>[];
    final overflow = <_TopActionItem>[];
    var used = 0;

    for (final item in parsed) {
      if (!item.canOverflow) {
        visible.add(item.widget);
        continue;
      }
      if (used < maxVisible) {
        visible.add(item.widget);
        used += 1;
      } else {
        overflow.add(item);
      }
    }

    if (overflow.isNotEmpty) {
      visible.add(_buildOverflowMenu(context, overflow, compact: isCompact));
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: visible,
    );
  }

  Widget _buildWideActions(BuildContext context) {
    final parsed = _parseTopActions(compact: false);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ...parsed.map((item) => item.widget),
        const ThemeToggle(),
        ...actions,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ink = AppTheme.ink1(context);
    final titleStyle = Theme.of(context).textTheme.titleLarge?.copyWith(
          color: ink,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        );
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      decoration: BoxDecoration(
        color: AppTheme.panel(context),
        borderRadius: BorderRadius.circular(AppTheme.rCard),
        border: Border.all(color: scheme.outline),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 980;
          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: titleStyle,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const ThemeToggle(),
                        ...actions,
                      ],
                    ),
                  ],
                ),
                if (topActions.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _buildNarrowActions(context, constraints.maxWidth),
                ],
              ],
            );
          }
          return Row(
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.35),
                child: Text(
                  title,
                  style: titleStyle,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: _buildWideActions(context)),
            ],
          );
        },
      ),
    );
  }
}

class _TopActionItem {
  final Widget widget;
  final String? label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool canOverflow;

  const _TopActionItem({
    required this.widget,
    this.label,
    this.icon,
    this.onPressed,
    this.canOverflow = false,
  });
}

class _TabBarModern extends StatelessWidget {
  final List<String> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _TabBarModern({
    required this.items,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(items.length, (i) {
        final selected = i == currentIndex;
        return Padding(
          padding: EdgeInsets.only(right: i == items.length - 1 ? 0 : 6),
          child: _Tab(
            label: items[i],
            selected: selected,
            scheme: scheme,
            onTap: () => onTap(i),
          ),
        );
      }),
    );

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.panel(context),
        borderRadius: BorderRadius.circular(AppTheme.rPill),
        border: Border.all(color: scheme.outline),
      ),
      // Défilement horizontal : avec beaucoup d'onglets ou une fenêtre
      // étroite, la barre glisse au lieu de déborder.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        child: row,
      ),
    );
  }
}

class _Tab extends StatefulWidget {
  final String label;
  final bool selected;
  final ColorScheme scheme;
  final VoidCallback onTap;

  const _Tab({
    required this.label,
    required this.selected,
    required this.scheme,
    required this.onTap,
  });

  @override
  State<_Tab> createState() => _TabState();
}

class _TabState extends State<_Tab> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.scheme;
    final sel = widget.selected;
    final ink1 = AppTheme.ink1(context);
    final ink2 = AppTheme.ink2(context);
    final hover = AppTheme.hover(context);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppTheme.mid,
          curve: AppTheme.ease,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: sel
                ? s.primary.withValues(alpha: 0.15)
                : _hover ? hover : Colors.transparent,
            borderRadius: BorderRadius.circular(AppTheme.rPill),
            border: sel
                ? Border.all(color: s.primary.withValues(alpha: 0.40))
                : null,
          ),
          child: AnimatedDefaultTextStyle(
            duration: AppTheme.mid,
            curve: AppTheme.ease,
            style: TextStyle(
              color: sel ? s.primary : (_hover ? ink1 : ink2),
              fontWeight: sel ? FontWeight.w600 : FontWeight.w500,
              fontSize: 13,
              letterSpacing: 0,
            ),
            child: Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}
