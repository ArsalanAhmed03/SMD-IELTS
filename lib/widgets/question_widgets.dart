import 'package:flutter/material.dart';

class McqOptions extends StatelessWidget {
  final List<String> options;
  final int? selectedIndex;
  final ValueChanged<int> onSelected;
  const McqOptions({super.key, required this.options, required this.selectedIndex, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        for (var i = 0; i < options.length; i++)
          _McqTile(
            label: options[i],
            selected: selectedIndex == i,
            onTap: () => onSelected(i),
            theme: theme,
          ),
      ],
    );
  }
}

class _McqTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final ThemeData theme;

  const _McqTile({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = selected ? theme.colorScheme.primary : Colors.grey.shade300;
    final fillColor = selected ? theme.colorScheme.primary.withOpacity(0.06) : Colors.white;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: Material(
        color: fillColor,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor, width: 1.4),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            child: Row(
              children: [
                Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class EssayInput extends StatelessWidget {
  final TextEditingController controller;
  const EssayInput({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: 12,
      decoration: const InputDecoration(
        hintText: 'Write your response here…',
        border: OutlineInputBorder(),
      ),
    );
  }
}

class ShortTextInput extends StatelessWidget {
  final TextEditingController controller;
  const ShortTextInput({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: const InputDecoration(
        hintText: 'Type your answer…',
        border: OutlineInputBorder(),
      ),
    );
  }
}

