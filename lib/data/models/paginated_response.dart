/// Generic paginated response wrapper.
class PaginatedResponse<T> {
  final List<T> items;
  final int page;
  final int limit;
  final int total;
  final bool hasNext;

  const PaginatedResponse({
    required this.items,
    required this.page,
    required this.limit,
    required this.total,
    required this.hasNext,
  });

  factory PaginatedResponse.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) fromJsonT,
  ) {
    final items = (json['items'] as List<dynamic>?)
            ?.map((e) => fromJsonT(e as Map<String, dynamic>))
            .toList() ??
        [];
    return PaginatedResponse<T>(
      items: items,
      page: json['page'] as int? ?? 1,
      limit: json['limit'] as int? ?? 20,
      total: json['total'] as int? ?? 0,
      hasNext: json['hasNext'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson(Map<String, dynamic> Function(T) toJsonT) {
    return {
      'items': items.map(toJsonT).toList(),
      'page': page,
      'limit': limit,
      'total': total,
      'hasNext': hasNext,
    };
  }
}
