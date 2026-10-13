import 'package:flutter_test/flutter_test.dart';
import 'package:cctv_manager/core/utils/role_permissions.dart';
import 'package:cctv_manager/data/models/user_model.dart';

void main() {
  group('UserModel', () {
    final user = UserModel(
      id: '2',
      username: 'johndoe',
      name: 'John Doe',
      email: 'john@example.com',
      role: UserRole.user,
      isActive: true,
      createdAt: DateTime.utc(2024, 1, 1),
    );

    // Exactly what the backend's /auth/me and /users endpoints return.
    final backendJson = {
      'id': '1',
      'username': 'admin',
      'full_name': 'Admin User',
      'email': 'admin@example.com',
      'role': 'ADMIN',
      'is_active': true,
      'created_at': '2024-01-01T00:00:00Z',
      'updated_at': '2024-06-01T00:00:00Z',
      'last_login_at': '2024-06-15T12:00:00Z',
    };

    test('fromJson parses the backend snake_case payload', () {
      final model = UserModel.fromJson(backendJson);

      expect(model.id, '1');
      expect(model.username, 'admin');
      expect(model.name, 'Admin User');
      expect(model.email, 'admin@example.com');
      expect(model.role, UserRole.admin);
      expect(model.isActive, isTrue);
      expect(model.createdAt, DateTime.utc(2024, 1, 1));
      expect(model.updatedAt, DateTime.utc(2024, 6, 1));
      expect(model.lastSignIn, DateTime.utc(2024, 6, 15, 12));
    });

    test('fromJson tolerates missing optional fields and extra keys', () {
      final model = UserModel.fromJson({
        ...backendJson,
        'updated_at': null,
        'last_login_at': null,
        'permissions': ['cctv.read'],
      });
      expect(model.updatedAt, isNull);
      expect(model.lastSignIn, isNull);
    });

    test('toJson round-trips through fromJson', () {
      final copy = UserModel.fromJson(UserModel.fromJson(backendJson).toJson());
      expect(copy.name, 'Admin User');
      expect(copy.role, UserRole.admin);
      expect(copy.lastSignIn, DateTime.utc(2024, 6, 15, 12));
    });

    test('copyWith updates isActive and keeps everything else', () {
      final updated = user.copyWith(isActive: false);

      expect(updated.isActive, isFalse);
      expect(updated.id, user.id);
      expect(updated.name, user.name);
      expect(updated.role, UserRole.user);
    });

    test('copyWith updates role', () {
      final updated = user.copyWith(role: UserRole.admin);

      expect(updated.role, UserRole.admin);
      expect(updated.isActive, isTrue);
    });
  });
}
