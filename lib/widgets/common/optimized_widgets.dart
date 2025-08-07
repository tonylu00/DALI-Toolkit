import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 优化的滑块组件，减少重建次数和提升性能
class OptimizedSlider extends StatefulWidget {
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;
  final String? label;
  final Color? activeColor;
  final Color? inactiveColor;
  final SliderThemeData? sliderTheme;

  const OptimizedSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    this.onChanged,
    this.onChangeEnd,
    this.label,
    this.activeColor,
    this.inactiveColor,
    this.sliderTheme,
  });

  @override
  State<OptimizedSlider> createState() => _OptimizedSliderState();
}

class _OptimizedSliderState extends State<OptimizedSlider> {
  late double _currentValue;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _currentValue = widget.value;
  }

  @override
  void didUpdateWidget(OptimizedSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isDragging && widget.value != oldWidget.value) {
      _currentValue = widget.value;
    }
  }

  void _handleChanged(double value) {
    setState(() {
      _currentValue = value;
      _isDragging = true;
    });

    // 添加触觉反馈
    if (widget.divisions != null) {
      HapticFeedback.selectionClick();
    }

    widget.onChanged?.call(value);
  }

  void _handleChangeEnd(double value) {
    setState(() {
      _isDragging = false;
    });
    widget.onChangeEnd?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.sliderTheme ?? SliderTheme.of(context);

    return SliderTheme(
      data: theme,
      child: Slider(
        value: _currentValue.clamp(widget.min, widget.max),
        min: widget.min,
        max: widget.max,
        divisions: widget.divisions,
        label: widget.label ?? _currentValue.round().toString(),
        activeColor: widget.activeColor,
        inactiveColor: widget.inactiveColor,
        onChanged: widget.onChanged != null ? _handleChanged : null,
        onChangeEnd: _handleChangeEnd,
      ),
    );
  }
}

/// 带缓存的颜色预览组件
class CachedColorPreview extends StatelessWidget {
  final Color color;
  final double size;
  final double borderRadius;
  final VoidCallback? onTap;

  const CachedColorPreview({
    super.key,
    required this.color,
    this.size = 50,
    this.borderRadius = 8,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.3),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
      ),
    );
  }
}

/// 性能优化的网格组件
class OptimizedCheckboxGrid extends StatelessWidget {
  final List<bool> values;
  final ValueChanged<int> onChanged;
  final int crossAxisCount;
  final double spacing;

  const OptimizedCheckboxGrid({
    super.key,
    required this.values,
    required this.onChanged,
    this.crossAxisCount = 8,
    this.spacing = 4.0,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: values.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: spacing,
        crossAxisSpacing: spacing,
        childAspectRatio: 0.8,
      ),
      itemBuilder: (context, index) {
        return _CheckboxGridItem(
          index: index,
          isSelected: values[index],
          onChanged: () => onChanged(index),
        );
      },
    );
  }
}

class _CheckboxGridItem extends StatelessWidget {
  final int index;
  final bool isSelected;
  final VoidCallback onChanged;

  const _CheckboxGridItem({
    required this.index,
    required this.isSelected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onChanged,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.outline.withValues(alpha: 0.3),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$index',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: isSelected
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            Transform.scale(
              scale: 1.2,
              child: Checkbox(
                value: isSelected,
                onChanged: (_) => onChanged(),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                activeColor: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 防抖动的文本输入框
class DebouncedTextField extends StatefulWidget {
  final String? initialValue;
  final ValueChanged<String>? onChanged;
  final Duration debounceDuration;
  final InputDecoration? decoration;
  final TextInputType? keyboardType;

  const DebouncedTextField({
    super.key,
    this.initialValue,
    this.onChanged,
    this.debounceDuration = const Duration(milliseconds: 300),
    this.decoration,
    this.keyboardType,
  });

  @override
  State<DebouncedTextField> createState() => _DebouncedTextFieldState();
}

class _DebouncedTextFieldState extends State<DebouncedTextField> {
  late TextEditingController _controller;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(widget.debounceDuration, () {
      widget.onChanged?.call(_controller.text);
    });
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      decoration: widget.decoration,
      keyboardType: widget.keyboardType,
    );
  }
}
