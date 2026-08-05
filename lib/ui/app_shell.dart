import 'dart:ui';

import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'fluent_theme.dart';
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
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      body: Stack(
        children: [
          // Fond : dégradé de marque, profond et saturé.
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(scheme.primary, Colors.black, 0.34)!,
                  Color.lerp(scheme.primary, Colors.black, 0.62)!,
                  const Color(0xFF04141A),
                ],
                stops: const [0, 0.45, 1],
              ),
            ),
          ),
          // Halo chaud en haut à droite : donne une source de lumière.
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0.85, -0.9),
                    radius: 1.15,
                    colors: [
                      scheme.secondary.withValues(alpha: 0.34),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: -70,
            right: -50,
            child: IgnorePointer(
              child: _blurCircle(
                scheme.primary.withValues(alpha: 0.42),
                260,
              ),
            ),
          ),
          Positioned(
            bottom: -60,
            left: -70,
            child: IgnorePointer(
              child: _blurCircle(
                scheme.tertiary.withValues(alpha: 0.26),
                220,
              ),
            ),
          ),
          Column(
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
        ],
      ),
    );
  }
}

Widget _blurCircle(Color color, double size) {
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: color,
      boxShadow: [
        BoxShadow(color: color, blurRadius: size / 2, spreadRadius: size / 4),
      ],
    ),
  );
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
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 14, vertical: compact ? 10 : 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.12),
          borderRadius: BorderRadius.circular(FluentTheme.buttonRadius),
          border: Border.all(color: Colors.white.withOpacity(0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.more_horiz, color: Colors.white, size: 18),
            if (!compact) ...[
              const SizedBox(width: 6),
              const Text('Plus', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ],
          ],
        ),
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
    final titleStyle = Theme.of(context).textTheme.titleLarge?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        );
    final shell = Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withOpacity(0.14),
                  Colors.white.withOpacity(0.06),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.18)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.18),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
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
          ),
        ),
      ),
    );
    return shell;
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
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppTheme.rPill),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
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

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppTheme.mid,
          curve: AppTheme.ease,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          decoration: BoxDecoration(
            gradient: sel
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [s.primary, Color.lerp(s.primary, s.secondary, 0.6)!],
                  )
                : null,
            color: sel
                ? null
                : Colors.white.withValues(alpha: _hover ? 0.12 : 0.0),
            borderRadius: BorderRadius.circular(AppTheme.rPill),
            boxShadow: sel
                ? [
                    BoxShadow(
                      color: s.primary.withValues(alpha: 0.45),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : const [],
          ),
          child: AnimatedDefaultTextStyle(
            duration: AppTheme.mid,
            curve: AppTheme.ease,
            style: TextStyle(
              color: sel
                  ? Colors.white
                  : Colors.white.withValues(alpha: _hover ? 0.95 : 0.72),
              fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
              fontSize: 14.5,
              letterSpacing: sel ? 0.1 : 0,
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
