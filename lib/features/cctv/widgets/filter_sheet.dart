import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Filter sheet for CCTV list.
class FilterSheet extends StatefulWidget {
  final String? currentStatus;
  final String? currentType;
  final String? currentRegion;
  final String? currentTownship;
  final String? currentDateFrom;
  final String? currentDateTo;
  final Function(String? status, String? type, String? region, String? township,
      String? dateFrom, String? dateTo) onApply;

  const FilterSheet({
    super.key,
    this.currentStatus,
    this.currentType,
    this.currentRegion,
    this.currentTownship,
    this.currentDateFrom,
    this.currentDateTo,
    required this.onApply,
  });

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  Set<String> _statuses = {};
  Set<String> _types = {};
  Set<String> _regions = {};
  Set<String> _townships = {};
  DateTime? _dateFrom;
  DateTime? _dateTo;

  @override
  void initState() {
    super.initState();
    if (widget.currentStatus != null && widget.currentStatus!.isNotEmpty) {
      _statuses = widget.currentStatus!.split(',').where((s) => s.isNotEmpty).toSet();
    }
    if (widget.currentType != null && widget.currentType!.isNotEmpty) {
      _types = widget.currentType!.split(',').where((s) => s.isNotEmpty).toSet();
    }
    if (widget.currentRegion != null && widget.currentRegion!.isNotEmpty) {
      _regions = widget.currentRegion!.split(',').where((s) => s.isNotEmpty).toSet();
    }
    if (widget.currentTownship != null && widget.currentTownship!.isNotEmpty) {
      _townships = widget.currentTownship!.split(',').where((s) => s.isNotEmpty).toSet();
    }
    if (widget.currentDateFrom != null) {
      _dateFrom = DateTime.tryParse(widget.currentDateFrom!);
    }
    if (widget.currentDateTo != null) {
      _dateTo = DateTime.tryParse(widget.currentDateTo!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Filters',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _statuses.clear();
                    _types.clear();
                    _regions.clear();
                    _townships.clear();
                  });
                },
                child: const Text('Clear All'),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Status
          Text('Status', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              _FilterChip(
                label: 'Active',
                isSelected: _statuses.contains('ACTIVE'),
                onTap: () => setState(() {
                  if (_statuses.contains('ACTIVE')) {
                    _statuses.remove('ACTIVE');
                  } else {
                    _statuses.add('ACTIVE');
                  }
                }),
              ),
              _FilterChip(
                label: 'Inactive',
                isSelected: _statuses.contains('INACTIVE'),
                onTap: () => setState(() {
                  if (_statuses.contains('INACTIVE')) {
                    _statuses.remove('INACTIVE');
                  } else {
                    _statuses.add('INACTIVE');
                  }
                }),
              ),
              _FilterChip(
                label: 'Maintenance',
                isSelected: _statuses.contains('MAINTENANCE'),
                onTap: () => setState(() {
                  if (_statuses.contains('MAINTENANCE')) {
                    _statuses.remove('MAINTENANCE');
                  } else {
                    _statuses.add('MAINTENANCE');
                  }
                }),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Type
          Text('Type', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              _FilterChip(
                label: 'Dome',
                isSelected: _types.contains('Dome'),
                onTap: () => setState(() {
                  if (_types.contains('Dome')) {
                    _types.remove('Dome');
                  } else {
                    _types.add('Dome');
                  }
                }),
              ),
              _FilterChip(
                label: 'Bullet',
                isSelected: _types.contains('Bullet'),
                onTap: () => setState(() {
                  if (_types.contains('Bullet')) {
                    _types.remove('Bullet');
                  } else {
                    _types.add('Bullet');
                  }
                }),
              ),
              _FilterChip(
                label: 'PTZ',
                isSelected: _types.contains('PTZ'),
                onTap: () => setState(() {
                  if (_types.contains('PTZ')) {
                    _types.remove('PTZ');
                  } else {
                    _types.add('PTZ');
                  }
                }),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Date Range
          Text('Date Added', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text(
                    _dateFrom != null
                        ? '${_dateFrom!.day}/${_dateFrom!.month}/${_dateFrom!.year}'
                        : 'From',
                  ),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _dateFrom ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) setState(() => _dateFrom = picked);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text(
                    _dateTo != null
                        ? '${_dateTo!.day}/${_dateTo!.month}/${_dateTo!.year}'
                        : 'To',
                  ),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _dateTo ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) setState(() => _dateTo = picked);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    final now = DateTime.now();
                    setState(() {
                      _dateFrom = DateTime(now.year, now.month, now.day);
                      _dateTo = DateTime(now.year, now.month, now.day + 1);
                    });
                  },
                  child: const Text('Today'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    final now = DateTime.now();
                    setState(() {
                      _dateFrom = DateTime(now.year, now.month, 1);
                      _dateTo = DateTime(now.year, now.month + 1, 1);
                    });
                  },
                  child: const Text('This Month'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Apply
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                widget.onApply(
                  _statuses.isEmpty ? null : _statuses.join(','),
                  _types.isEmpty ? null : _types.join(','),
                  _regions.isEmpty ? null : _regions.join(','),
                  _townships.isEmpty ? null : _townships.join(','),
                  _dateFrom?.toIso8601String(),
                  _dateTo?.toIso8601String(),
                );
                Navigator.pop(context);
              },
              child: const Text('Apply Filters'),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            color: isSelected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
