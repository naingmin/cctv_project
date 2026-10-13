import 'package:cctv_manager/core/utils/role_permissions.dart';
import 'package:cctv_manager/data/models/cctv_record_model.dart';
import 'package:cctv_manager/data/models/user_model.dart';

/// A CCTV record without images, so widgets never touch the network.
CctvRecord fakeRecord({
  String id = 'r1',
  String cctvId = 'CCTV-YGN-000001',
  String status = 'ACTIVE',
  String? region = 'Yangon',
  String? township = 'Bahan',
  String? street = 'Main St',
  String? description = 'Main intersection camera',
  List<String> tags = const [],
}) {
  final created = DateTime.utc(2024, 1, 1);
  return CctvRecord(
    id: id,
    cctvId: cctvId,
    latitude: 16.8409,
    longitude: 96.1561,
    region: region,
    township: township,
    street: street,
    status: status,
    description: description,
    tags: tags,
    createdAt: created,
    updatedAt: created,
  );
}

UserModel fakeUser({UserRole role = UserRole.user}) => UserModel(
      id: 'u1',
      username: role == UserRole.admin ? 'admin' : 'viewer',
      name: role == UserRole.admin ? 'Admin' : 'Viewer',
      email: 'someone@example.com',
      role: role,
      isActive: true,
      createdAt: DateTime.utc(2024, 1, 1),
    );
