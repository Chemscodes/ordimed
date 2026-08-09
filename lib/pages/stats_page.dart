import 'package:flutter/material.dart';
import '../services/stats_service.dart';
import '../ui/fluent_card.dart';
import '../ui/fluent_theme.dart';
import '../core/coerce.dart';

class StatsPage extends StatelessWidget {
  final String parentUid;
  final String title;

  const StatsPage({
    super.key,
    required this.parentUid,
    this.title = 'Stats',
  });

  String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  String _dayKey(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  double _toDouble(dynamic value) => asDouble(value);

  DateTime _asDate(dynamic value, String dayKey) =>
      asDateOrNull(value) ?? dateFromDayKey(dayKey) ?? DateTime.now();

  String _formatMoney(double value) {
    final isInt = value.truncateToDouble() == value;
    return value.toStringAsFixed(isInt ? 0 : 2);
  }

  Widget _buildInfoBanner(BuildContext context, String note) {
    final scheme = Theme.of(context).colorScheme;
    final textMuted = scheme.onSurface.withOpacity(0.7);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.secondary.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.secondary.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: scheme.secondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              note,
              style: TextStyle(color: textMuted, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroCard(BuildContext context, _DailyStatsRow row) {
    final versementsTotal = row.versementsTotal;
    final achatsTotal = row.achatsTotal;
    final versementsCount = row.versementsCount;
    final achatsCount = row.achatsCount;
    final net = versementsTotal - achatsTotal;
    final netIcon = net >= 0 ? Icons.trending_up : Icons.trending_down;
    final subtitle =
        '${versementsCount == 1 ? "1 versement" : "$versementsCount versements"} - ${achatsCount == 1 ? "1 achat" : "$achatsCount achats"}';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: FluentTheme.appBarGradient(context),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [FluentTheme.softShadow(context)],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Resume du jour',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.92),
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'DA ${_formatMoney(net)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 26,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: TextStyle(color: Colors.white.withOpacity(0.86), fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  'Versements: DA ${_formatMoney(versementsTotal)}   Achats: DA ${_formatMoney(achatsTotal)}',
                  style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.16),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.2)),
            ),
            child: Icon(netIcon, color: Colors.white, size: 24),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
    required Color tint,
    String? caption,
  }) {
    final textMuted = Theme.of(context).colorScheme.onSurface.withOpacity(0.6);
    return FluentCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: tint.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: tint.withOpacity(0.3)),
            ),
            child: Icon(icon, color: tint, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: tint,
                    fontSize: 16,
                  ),
                ),
                if (caption != null) ...[
                  const SizedBox(height: 2),
                  Text(caption, style: TextStyle(color: textMuted, fontSize: 12)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDatePill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(fontWeight: FontWeight.w700, color: color),
      ),
    );
  }

  Widget _buildDailyCard(BuildContext context, _DailyStatsRow row) {
    final scheme = Theme.of(context).colorScheme;
    final textMuted = scheme.onSurface.withOpacity(0.7);
    final textFaint = scheme.onSurface.withOpacity(0.5);
    final versements = row.versementsTotal;
    final achats = row.achatsTotal;
    final netDay = versements - achats;
    final accent = netDay >= 0 ? scheme.primary : scheme.error;
    final label =
        '${row.date.day.toString().padLeft(2, '0')}/${row.date.month.toString().padLeft(2, '0')}';

    final metrics = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Versements: DA ${_formatMoney(versements)}', style: TextStyle(color: textMuted)),
        const SizedBox(height: 4),
        Text('Achats: DA ${_formatMoney(achats)}', style: TextStyle(color: textFaint)),
      ],
    );

    final netWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text('Net', style: TextStyle(color: textFaint, fontSize: 12)),
        const SizedBox(height: 4),
        Text(
          'DA ${_formatMoney(netDay)}',
          style: TextStyle(fontWeight: FontWeight.w700, color: accent),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 520;
        return FluentCard(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          child: isNarrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDatePill(label, accent),
                    const SizedBox(height: 10),
                    metrics,
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: netWidget,
                    ),
                  ],
                )
              : Row(
                  children: [
                    _buildDatePill(label, accent),
                    const SizedBox(width: 12),
                    Expanded(child: metrics),
                    const SizedBox(width: 12),
                    netWidget,
                  ],
                ),
        );
      },
    );
  }

  Widget _buildStatsContent(
    BuildContext context,
    List<_DailyStatsRow> rows, {
    String? note,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final textFaint = scheme.onSurface.withOpacity(0.5);

    if (rows.isEmpty) {
      return const Center(child: Text('Aucune statistique disponible'));
    }

    rows.sort((a, b) => b.date.compareTo(a.date));
    final todayKey = _todayKey();
    final todayRow = rows.firstWhere(
      (r) => _dayKey(r.date) == todayKey,
      orElse: () => rows.first,
    );

    final versementsTotal = todayRow.versementsTotal;
    final achatsTotal = todayRow.achatsTotal;
    final versementsCount = todayRow.versementsCount;
    final achatsCount = todayRow.achatsCount;
    final net = versementsTotal - achatsTotal;
    final netColor = net >= 0 ? scheme.primary : scheme.error;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      children: [
        if (note != null) ...[
          _buildInfoBanner(context, note),
          const SizedBox(height: 12),
        ],
        _buildHeroCard(context, todayRow),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final spacing = 12.0;
            final columns = width >= 920 ? 3 : (width >= 600 ? 2 : 1);
            final itemWidth = (width - (columns - 1) * spacing) / columns;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                SizedBox(
                  width: itemWidth,
                  child: _buildStatCard(
                    context,
                    label: 'Versements',
                    value: 'DA ${_formatMoney(versementsTotal)}',
                    caption: versementsCount == 1 ? '1 operation' : '$versementsCount operations',
                    icon: Icons.payments_outlined,
                    tint: scheme.primary,
                  ),
                ),
                SizedBox(
                  width: itemWidth,
                  child: _buildStatCard(
                    context,
                    label: 'Achats',
                    value: 'DA ${_formatMoney(achatsTotal)}',
                    caption: achatsCount == 1 ? '1 operation' : '$achatsCount operations',
                    icon: Icons.shopping_bag_outlined,
                    tint: scheme.secondary,
                  ),
                ),
                SizedBox(
                  width: itemWidth,
                  child: _buildStatCard(
                    context,
                    label: 'Net du jour',
                    value: 'DA ${_formatMoney(net)}',
                    caption: 'Versements - achats',
                    icon: net >= 0 ? Icons.trending_up : Icons.trending_down,
                    tint: netColor,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            const Text(
              'Derniers 7 jours',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const Spacer(),
            Text('Valeurs journalieres', style: TextStyle(color: textFaint, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 10),
        ...rows.map((row) => _buildDailyCard(context, row)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final statsStream = StatsService().recentDailyStats(parentUid: parentUid, limit: 7);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w700,
            ),
        iconTheme: IconThemeData(color: scheme.primary),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: statsStream,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Text(
                'Erreur de chargement des stats',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data!;
          if (docs.isEmpty) {
            return const Center(
              child: Text('Aucune statistique disponible'),
            );
          }
          final rows = docs.map((doc) {
            final data = doc;
            final dayKey = (data['dayKey'] ?? doc['id'].toString()).toString();
            final date = _asDate(data['date'], dayKey);
            return _DailyStatsRow(
              date: date,
              versementsTotal: _toDouble(data['versementsTotal']),
              versementsCount: (data['versementsCount'] as num?)?.toInt() ?? 0,
              achatsTotal: _toDouble(data['achatsTotal']),
              achatsCount: (data['achatsCount'] as num?)?.toInt() ?? 0,
            );
          }).toList();

          return _buildStatsContent(context, rows);
        },
      ),
    );
  }
}

class _DailyStatsRow {
  final DateTime date;
  final double versementsTotal;
  final int versementsCount;
  final double achatsTotal;
  final int achatsCount;

  const _DailyStatsRow({
    required this.date,
    required this.versementsTotal,
    required this.versementsCount,
    required this.achatsTotal,
    required this.achatsCount,
  });
}

