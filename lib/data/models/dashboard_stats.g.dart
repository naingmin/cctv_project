// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dashboard_stats.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DashboardStats _$DashboardStatsFromJson(Map<String, dynamic> json) =>
    DashboardStats(
      totalCctv: (json['total_cctv'] as num).toInt(),
      activeCctv: (json['active_cctv'] as num).toInt(),
      inactiveCctv: (json['inactive_cctv'] as num).toInt(),
      maintenanceCctv: (json['maintenance_cctv'] as num).toInt(),
      addedToday: (json['added_today'] as num).toInt(),
      addedThisMonth: (json['added_this_month'] as num).toInt(),
      totalUsers: (json['total_users'] as num).toInt(),
      activeUsers: (json['active_users'] as num).toInt(),
    );

Map<String, dynamic> _$DashboardStatsToJson(DashboardStats instance) =>
    <String, dynamic>{
      'total_cctv': instance.totalCctv,
      'active_cctv': instance.activeCctv,
      'inactive_cctv': instance.inactiveCctv,
      'maintenance_cctv': instance.maintenanceCctv,
      'added_today': instance.addedToday,
      'added_this_month': instance.addedThisMonth,
      'total_users': instance.totalUsers,
      'active_users': instance.activeUsers,
    };
