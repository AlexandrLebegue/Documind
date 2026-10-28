import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';

class DocTypeBadge extends StatelessWidget {
  const DocTypeBadge({super.key, this.type});

  final String? type;

  @override
  Widget build(BuildContext context) {
    final style = docTypeStyle(type);
    return _Pill(
      label: style.label,
      color: style.color,
      background: style.background,
    );
  }
}

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'processing' => ('En cours…', AppColors.warning),
      'queued' => ('En file', AppColors.warning),
      'ready' => ('Prêt', AppColors.success),
      'error' => ('Erreur', AppColors.danger),
      _ => (status, AppColors.muted),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PulseDot(color: color, active: status == 'processing'),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class AlertBadge extends StatelessWidget {
  const AlertBadge({super.key, required this.urgency, this.label});

  final String urgency;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final color = urgencyColor(urgency);
    return _Pill(
      label: label ?? urgencyLabel(urgency),
      color: color,
      background: urgencyBackground(urgency),
      dot: true,
    );
  }
}

class ProcedureTypeBadge extends StatelessWidget {
  const ProcedureTypeBadge({super.key, this.type});

  final String? type;

  @override
  Widget build(BuildContext context) {
    final colors =
        procedureTypeColors[type] ?? (AppColors.muted, const Color(0xFFF3F4F6));
    return _Pill(
      label: procedureTypeLabels[type] ?? (type ?? 'Autre'),
      color: colors.$1,
      background: colors.$2,
    );
  }
}

class VerdictBadge extends StatelessWidget {
  const VerdictBadge({super.key, required this.verdict});

  final String verdict;

  @override
  Widget build(BuildContext context) {
    final (label, color, background) = switch (verdict) {
      'pending' => ('À valider', AppColors.warning, AppColors.warningBg),
      'accepted' => ('Accepté', AppColors.success, AppColors.successBg),
      'rejected' => ('Refusé', AppColors.danger, AppColors.dangerBg),
      _ => ('Erreur', AppColors.muted, const Color(0xFFF3F4F6)),
    };
    return _Pill(label: label, color: color, background: background);
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.color,
    required this.background,
    this.dot = false,
  });

  final String label;
  final Color color;
  final Color background;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dot ? 8 : 10, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.color, required this.active});

  final Color color;
  final bool active;

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    if (widget.active) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _PulseDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.active && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.4, end: 1.0).animate(_controller),
      child: Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}
