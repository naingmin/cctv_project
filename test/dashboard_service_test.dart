import 'package:flutter_test/flutter_test.dart';
import 'package:cctv_manager/data/models/dashboard_stats.dart';

void main() {
  group('DashboardStats', () {
    test('fromJson parses all fields', () {
      final json = {
        'total_cctv': 100,
        'active_cctv': 80,
        'inactive_cctv': 15,
        'maintenance_cctv': 5,
        'added_today': 3,
        'added_this_month': 20,
        'total_users': 10,
        'active_users': 8,
      };

      final stats = DashboardStats.fromJson(json);

      expect(stats.totalCctv, 100);
      expect(stats.activeCctv, 80);
      expect(stats.inactiveCctv, 15);
      expect(stats.maintenanceCctv, 5);
      expect(stats.addedToday, 3);
      expect(stats.addedThisMonth, 20);
      expect(stats.totalUsers, 10);
      expect(stats.activeUsers, 8);
    });

    test('operationalCount and inactiveCount are aliases', () {
      const stats = DashboardStats(
        totalCctv: 10,
        activeCctv: 7,
        inactiveCctv: 2,
        maintenanceCctv: 1,
        addedToday: 0,
        addedThisMonth: 5,
        totalUsers: 3,
        activeUsers: 2,
      );

      expect(stats.operationalCount, 7);
      expect(stats.inactiveCount, 2);
    });

    test('toJson round-trips', () {
      const stats = DashboardStats(
        totalCctv: 50,
        activeCctv: 40,
        inactiveCctv: 5,
        maintenanceCctv: 5,
        addedToday: 2,
        addedThisMonth: 10,
        totalUsers: 5,
        activeUsers: 4,
      );

      final json = stats.toJson();
      final restored = DashboardStats.fromJson(json);

      expect(restored.totalCctv, 50);
      expect(restored.activeCctv, 40);
      expect(restored.inactiveCctv, 5);
      expect(restored.maintenanceCctv, 5);
      expect(restored.addedToday, 2);
      expect(restored.addedThisMonth, 10);
      expect(restored.totalUsers, 5);
      expect(restored.activeUsers, 4);
    });
  });
}
