import 'package:flutter_test/flutter_test.dart';
import 'package:cctv_manager/core/utils/validators.dart';

void main() {
  group('Validators', () {
    group('email', () {
      test('returns error for null', () {
        expect(Validators.email(null), 'Email is required');
      });

      test('returns error for empty', () {
        expect(Validators.email(''), 'Email is required');
      });

      test('returns error for invalid email', () {
        expect(Validators.email('invalid'), 'Enter a valid email');
      });

      test('returns null for valid email', () {
        expect(Validators.email('test@example.com'), null);
      });
    });

    group('password', () {
      test('returns error for null', () {
        expect(Validators.password(null), 'Password is required');
      });

      test('returns error for short password', () {
        expect(Validators.password('12345'), 'Password must be at least 6 characters');
      });

      test('returns null for valid password', () {
        expect(Validators.password('password123'), null);
      });
    });

    group('usernameOrEmail', () {
      test('returns error for null and empty', () {
        expect(
          Validators.usernameOrEmail(null),
          'Username or email is required',
        );
        expect(Validators.usernameOrEmail(''), 'Username or email is required');
        expect(Validators.usernameOrEmail('   '), 'Username or email is required');
      });

      test('accepts a bare username', () {
        // Regression: the login field used Validators.email, which rejected
        // "admin" even though the backend resolves usernames too.
        expect(Validators.usernameOrEmail('admin'), null);
        expect(Validators.usernameOrEmail('field.agent_01'), null);
      });

      test('rejects a malformed username', () {
        expect(
          Validators.usernameOrEmail('bad user'),
          'Use letters, numbers, dot, dash or underscore only',
        );
        expect(Validators.usernameOrEmail('ab'), 'Username must be 3-64 characters');
      });

      test('accepts an email address', () {
        expect(Validators.usernameOrEmail('admin@example.com'), null);
      });

      test('rejects a malformed email', () {
        expect(Validators.usernameOrEmail('admin@'), 'Enter a valid email');
        expect(
          Validators.usernameOrEmail('admin@example'),
          'Enter a valid email',
        );
      });

      test('tolerates surrounding whitespace', () {
        // _handleLogin trims, and the backend lookup strips too.
        expect(Validators.usernameOrEmail('  admin  '), null);
        expect(
          Validators.usernameOrEmail(' admin@example.com '),
          null,
        );
      });
    });

    group('username', () {
      test('returns error for null', () {
        expect(Validators.username(null), 'Username is required');
      });

      test('returns error for empty', () {
        expect(Validators.username(''), 'Username is required');
      });

      test('returns error for disallowed characters', () {
        // Backend pattern is ^[A-Za-z0-9_.-]+$
        expect(
          Validators.username('bad user'),
          'Use letters, numbers, dot, dash or underscore only',
        );
        expect(
          Validators.username('bad@user'),
          'Use letters, numbers, dot, dash or underscore only',
        );
      });

      test('returns error when too short', () {
        expect(Validators.username('ab'), 'Username must be 3-64 characters');
      });

      test('returns error when too long', () {
        expect(
          Validators.username('a' * 65),
          'Username must be 3-64 characters',
        );
      });

      test('returns null for valid username', () {
        expect(Validators.username('field.agent_01'), null);
        expect(Validators.username('a-b.c_d'), null);
        expect(Validators.username('a' * 64), null);
      });
    });

    group('strongPassword', () {
      test('returns error for null', () {
        expect(Validators.strongPassword(null), 'Password is required');
      });

      test('enforces the 8-character minimum, unlike password()', () {
        // Validators.password accepts 6; account creation does not.
        expect(Validators.password('abc123'), null);
        expect(
          Validators.strongPassword('abc123'),
          'Password must be at least 8 characters',
        );
      });

      test('returns error for surrounding whitespace', () {
        expect(
          Validators.strongPassword(' pass1234'),
          'Password must not start or end with a space',
        );
        expect(
          Validators.strongPassword('pass1234 '),
          'Password must not start or end with a space',
        );
      });

      test('returns error when no letter', () {
        expect(
          Validators.strongPassword('12345678'),
          'Password must contain at least one letter',
        );
      });

      test('returns error when no digit', () {
        expect(
          Validators.strongPassword('abcdefgh'),
          'Password must contain at least one number',
        );
      });

      test('returns null for a valid password', () {
        expect(Validators.strongPassword('Str0ngPass!'), null);
      });
    });

    group('cctvId', () {
      test('returns error for null', () {
        expect(Validators.cctvId(null), 'CCTV ID is required');
      });

      test('returns error for invalid format', () {
        expect(Validators.cctvId('invalid'), 'Format: CCTV-000001');
      });

      test('returns null for valid ID', () {
        expect(Validators.cctvId('CCTV-000001'), null);
      });
    });

    group('latitude', () {
      test('returns error for null', () {
        expect(Validators.latitude(null), 'Latitude is required');
      });

      test('returns error for out of range', () {
        expect(Validators.latitude('91'), 'Latitude must be between -90 and 90');
      });

      test('returns null for valid latitude', () {
        expect(Validators.latitude('19.7633'), null);
      });
    });

    group('longitude', () {
      test('returns error for null', () {
        expect(Validators.longitude(null), 'Longitude is required');
      });

      test('returns error for out of range', () {
        expect(Validators.longitude('181'), 'Longitude must be between -180 and 180');
      });

      test('returns null for valid longitude', () {
        expect(Validators.longitude('96.0781'), null);
      });
    });
  });
}
