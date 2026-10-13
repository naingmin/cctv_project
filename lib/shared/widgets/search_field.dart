import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Reusable search field with clear button.
class SearchField extends StatefulWidget {
  final String hintText;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;
  final Duration debounceDelay;

  const SearchField({
    super.key,
    this.hintText = 'Search...',
    required this.onChanged,
    this.controller,
    this.debounceDelay = const Duration(milliseconds: 500),
  });

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  late TextEditingController _controller;
  bool _showClear = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    final show = _controller.text.isNotEmpty;
    if (show != _showClear) setState(() => _showClear = show);
  }

  /// Reports the text only after typing pauses, so each keystroke does not
  /// fire its own request.
  void _onChangedDebounced(String value) {
    _debounce?.cancel();
    _debounce = Timer(widget.debounceDelay, () => widget.onChanged(value));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.removeListener(_onTextChanged);
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      onChanged: _onChangedDebounced,
      decoration: InputDecoration(
        hintText: widget.hintText,
        prefixIcon: const Icon(Icons.search, color: AppColors.textTertiary),
        suffixIcon: _showClear
            ? IconButton(
                icon: const Icon(Icons.clear, color: AppColors.textTertiary),
                onPressed: () {
                  // Clearing applies immediately.
                  _debounce?.cancel();
                  _controller.clear();
                  widget.onChanged('');
                },
              )
            : null,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }
}
