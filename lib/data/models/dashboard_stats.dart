import 'package:json_annotation/json_annotation.dart';

part 'dashboard_stats.g.dart';

/// Dashboard statistics data model, matching the FastAPI `/cctvs/stats` response.
@JsonSerializable()
class DashboardStats {
  @JsonKey(name: 'total_cctv')
  final int totalCctv;
  @JsonKey(name: 'active_cctv')
  final int activeCctv;
  @JsonKey(name: 'inactive_cctv')
  final int inactiveCctv;
  @JsonKey(name: 'maintenance_cctv')
  final int maintenanceCctv;
  @JsonKey(name: 'added_today')
  final int addedToday;
  @JsonKey(name: 'added_this_month')
  final int addedThisMonth;
  @JsonKey(name: 'total_users')
  final int totalUsers;
  @JsonKey(name: 'active_users')
  final int activeUsers;

  const DashboardStats({
    required this.totalCctv,
    required this.activeCctv,
    required this.inactiveCctv,
    required this.maintenanceCctv,
    required this.addedToday,
    required this.addedThisMonth,
    required this.totalUsers,
    required this.activeUsers,
  });

  factory DashboardStats.fromJson(Map<String, dynamic> json) =>
      _$DashboardStatsFromJson(json);

  Map<String, dynamic> toJson() => _$DashboardStatsToJson(this);

  int get operationalCount => activeCctv;
  int get inactiveCount => inactiveCctv;
}
