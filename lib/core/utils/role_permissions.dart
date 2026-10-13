/// Role definitions and permission checks shared by the Flutter app.
///
/// These mirror the backend (`backend/app/core/rbac.py` and
/// `cctv_service.scope_filter`). They only decide what the UI offers; the
/// backend enforces every rule again and is the real authority.
///
/// | Role           | Sees                   | Can change                    |
/// |----------------|------------------------|-------------------------------|
/// | admin          | everything             | everything, incl. users       |
/// | regionalAdmin  | own region             | create/edit in own region     |
/// | supervisor     | own region + township  | nothing                       |
/// | user (Viewer)  | everything             | upload images only            |
enum UserRole {
  admin,
  regionalAdmin,
  supervisor,
  user,
}

extension UserRoleX on UserRole {
  String get displayName {
    switch (this) {
      case UserRole.admin:
        return 'Administrator';
      case UserRole.regionalAdmin:
        return 'Regional Admin';
      case UserRole.supervisor:
        return 'Supervisor';
      case UserRole.user:
        return 'Viewer';
    }
  }

  /// One-line explanation shown when choosing a role.
  String get description {
    switch (this) {
      case UserRole.admin:
        return 'Full access: manage cameras, uploads, users and audit logs.';
      case UserRole.regionalAdmin:
        return 'Add and edit cameras in one region. Sees only that region.';
      case UserRole.supervisor:
        return 'Read-only access to one township in one region.';
      case UserRole.user:
        return 'Read-only access to all cameras. Can add photos.';
    }
  }

  /// The account must be assigned a region.
  bool get requiresRegion =>
      this == UserRole.regionalAdmin || this == UserRole.supervisor;

  /// The account must also be assigned a township.
  bool get requiresTownship => this == UserRole.supervisor;
}

class RolePermissions {
  const RolePermissions._();

  static bool canManageUsers(UserRole role) => role == UserRole.admin;

  static bool canViewDashboard(UserRole role) => role == UserRole.admin;

  static bool canCreateCctv(UserRole role) =>
      role == UserRole.admin || role == UserRole.regionalAdmin;

  static bool canEditCctv(UserRole role) =>
      role == UserRole.admin || role == UserRole.regionalAdmin;

  static bool canDeleteCctv(UserRole role) => role == UserRole.admin;

  static bool canUploadImages(UserRole role) =>
      role == UserRole.admin || role == UserRole.user;

  static bool canDeleteImages(UserRole role) => role == UserRole.admin;
}

/// Parses a backend role string. Unknown or missing values map to the least
/// privileged role, never to a more powerful one.
UserRole roleFromString(String? value) {
  switch ((value ?? '').toUpperCase()) {
    case 'ADMIN':
    case 'OVERALL_ADMIN':
      return UserRole.admin;
    case 'REGIONAL_ADMIN':
      return UserRole.regionalAdmin;
    case 'SUPERVISOR':
      return UserRole.supervisor;
    case 'USER':
    case 'OPERATOR':
    default:
      return UserRole.user;
  }
}

/// Backend value for [role]. Admin and Viewer keep the names existing
/// accounts already use (`ADMIN`, `USER`).
String roleToString(UserRole role) {
  switch (role) {
    case UserRole.admin:
      return 'ADMIN';
    case UserRole.regionalAdmin:
      return 'REGIONAL_ADMIN';
    case UserRole.supervisor:
      return 'SUPERVISOR';
    case UserRole.user:
      return 'USER';
  }
}
