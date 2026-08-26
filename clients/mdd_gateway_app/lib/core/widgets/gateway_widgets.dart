import 'dart:convert';

import 'package:flutter/material.dart';

import '../api/gateway_api.dart';
import '../theme/app_theme.dart';

class SectionCard extends StatelessWidget {
  const SectionCard({
    required this.child,
    this.title,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.all(20),
    super.key,
  });

  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null || trailing != null)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title!,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              subtitle!,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ?trailing,
                ],
              ),
            if (title != null || trailing != null) const SizedBox(height: 18),
            child,
          ],
        ),
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.label, {this.kind = StatusKind.neutral, super.key});

  final String label;
  final StatusKind kind;

  @override
  Widget build(BuildContext context) {
    final color = switch (kind) {
      StatusKind.success => AppTheme.success,
      StatusKind.warning => AppTheme.warning,
      StatusKind.danger => AppTheme.danger,
      StatusKind.neutral => Theme.of(context).colorScheme.onSurfaceVariant,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum StatusKind { success, warning, danger, neutral }

StatusKind statusKind(Object? value) {
  final text = value?.toString().toLowerCase() ?? '';
  if ([
    'ok',
    'on',
    'online',
    'working',
    'registered',
    'success',
    'enabled',
  ].any(text.contains)) {
    return StatusKind.success;
  }
  if ([
    'error',
    'failed',
    'critical',
    'missing',
    'no_card',
    'pin_problem',
  ].any(text.contains)) {
    return StatusKind.danger;
  }
  if ([
    'starting',
    'pending',
    'warning',
    'degraded',
    'discovering',
  ].any(text.contains)) {
    return StatusKind.warning;
  }
  return StatusKind.neutral;
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 42, horizontal: 24),
          child: Column(
            children: [
              Icon(
                icon,
                size: 42,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 7),
              Text(
                message,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              if (action != null) ...[const SizedBox(height: 20), action!],
            ],
          ),
        ),
      ),
    );
  }
}

class LinePicker extends StatelessWidget {
  const LinePicker({
    required this.lines,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final List<JsonMap> lines;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: lines.any((line) => line['id']?.toString() == value)
          ? value
          : null,
      decoration: const InputDecoration(
        labelText: '线路',
        prefixIcon: Icon(Icons.sim_card_outlined),
      ),
      items: [
        for (final line in lines)
          DropdownMenuItem(
            value: line['id']?.toString(),
            child: Text(
              (line['name'] ?? line['carrier'] ?? line['id'] ?? 'SIM')
                  .toString(),
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = '确认',
  bool dangerous = false,
}) async {
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: dangerous
                  ? FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                    )
                  : null,
              onPressed: () => Navigator.pop(context, true),
              child: Text(confirmLabel),
            ),
          ],
        ),
      ) ??
      false;
}

Future<JsonMap?> showJsonEditor(
  BuildContext context, {
  required String title,
  required JsonMap value,
  String description = '高级设置会直接提交给网关，请确认字段含义。',
}) async {
  final controller = TextEditingController(
    text: const JsonEncoder.withIndent('  ').convert(value),
  );
  String? error;
  final result = await showDialog<JsonMap>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 680,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(description),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                minLines: 12,
                maxLines: 22,
                keyboardType: TextInputType.multiline,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: InputDecoration(errorText: error),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              try {
                final decoded = jsonDecode(controller.text);
                if (decoded is! Map) {
                  throw const FormatException('根节点必须是 JSON 对象');
                }
                Navigator.pop(context, Map<String, dynamic>.from(decoded));
              } on Object catch (caught) {
                setState(() => error = caught.toString());
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
  controller.dispose();
  return result;
}

String displayValue(Object? value, {String fallback = '—'}) {
  if (value == null || value == '') return fallback;
  if (value is bool) return value ? '已开启' : '已关闭';
  return value.toString();
}
