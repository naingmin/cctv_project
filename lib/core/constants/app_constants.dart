import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Application-wide constants.
class AppConstants {
  AppConstants._();

  // App Info
  static const String appName = 'CCTV Manager';
  static const String appVersion = '1.0.0';

  // Environment
  static String get environment => dotenv.env['ENVIRONMENT'] ?? 'development';

  // Pagination
  static const int defaultPageSize = 20;
  static const int maxPageSize = 100;

  // Timeouts
  static const Duration connectionTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 60);
  static const Duration uploadTimeout = Duration(minutes: 5);

  // Image
  static const int maxImageWidth = 1920;
  static const int maxImageHeight = 1920;
  static const int imageQuality = 80;
  static const int thumbnailSize = 300;
  static const int maxEnvironmentImages = 10;

  // Map
  static const double defaultLatitude = 19.7633;
  static const double defaultLongitude = 96.0781;
  static const double defaultZoom = 12.0;
  static const double minZoomForMarkers = 10.0;

  // Storage Keys
  static const String keyAccessToken = 'access_token';
  static const String keyRefreshToken = 'refresh_token';
  static const String keyUserRole = 'user_role';
  static const String keyUserId = 'user_id';
  static const String keyUserName = 'user_name';
  static const String keyUserEmail = 'user_email';

  // Hive Boxes
  static const String hiveBoxUploadQueue = 'upload_queue';
  static const String hiveBoxDrafts = 'drafts';
  static const String hiveBoxSettings = 'settings';
  static const String hiveBoxCctvRecords = 'cctv_records';
  static const String hiveBoxUsers = 'users';
}
