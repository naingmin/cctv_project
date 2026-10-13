import 'package:flutter_test/flutter_test.dart';
import 'package:cctv_manager/core/utils/role_permissions.dart';

void main() {
  group('RolePermissions (mirrors backend rules)', () {
    Set<UserRole> allowed(bool Function(UserRole) check) =>
        UserRole.values.where(check).toSet();

    test('only admins manage users, see the dashboard and delete', () {
      expect(allowed(RolePermissions.canManageUsers), {UserRole.admin});
      expect(allowed(RolePermissions.canViewDashboard), {UserRole.admin});
      expect(allowed(RolePermissions.canDeleteCctv), {UserRole.admin});
      expect(allowed(RolePermissions.canDeleteImages), {UserRole.admin});
    });

    test('admins and regional admins create and edit cameras', () {
      const editors = {UserRole.admin, UserRole.regionalAdmin};
      expect(allowed(RolePermissions.canCreateCctv), editors);
      expect(allowed(RolePermissions.canEditCctv), editors);
    });

    test('admins and viewers upload images', () {
      expect(
        allowed(RolePermissions.canUploadImages),
        {UserRole.admin, UserRole.user},
      );
    });

    test('scoped roles require an area', () {
      expect(
        UserRole.values.where((r) => r.requiresRegion).toSet(),
        {UserRole.regionalAdmin, UserRole.supervisor},
      );
      expect(
        UserRole.values.where((r) => r.requiresTownship).toSet(),
        {UserRole.supervisor},
      );
    });
  });

  group('role strings', () {
    test('parse backend values case-insensitively', () {
      expect(roleFromString('ADMIN'), UserRole.admin);
      expect(roleFromString('admin'), UserRole.admin);
      expect(roleFromString('USER'), UserRole.user);
    });

    test('both admin names are administrators', () {
      // OVERALL_ADMIN used to be shown as a Viewer.
      expect(roleFromString('OVERALL_ADMIN'), UserRole.admin);
    });

    test('hierarchical roles parse', () {
      expect(roleFromString('REGIONAL_ADMIN'), UserRole.regionalAdmin);
      expect(roleFromString('SUPERVISOR'), UserRole.supervisor);
      expect(roleFromString('OPERATOR'), UserRole.user);
    });

    test('unknown or missing values fall back to the least privileged role', () {
      expect(roleFromString('unknown'), UserRole.user);
      expect(roleFromString(''), UserRole.user);
      expect(roleFromString(null), UserRole.user);
    });

    test('round-trip to backend values', () {
      for (final role in UserRole.values) {
        expect(roleFromString(roleToString(role)), role);
      }
    });

    test('display names', () {
      expect(UserRole.admin.displayName, 'Administrator');
      expect(UserRole.regionalAdmin.displayName, 'Regional Admin');
      expect(UserRole.supervisor.displayName, 'Supervisor');
      expect(UserRole.user.displayName, 'Viewer');
    });
  });
}
