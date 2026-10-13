# Authentication & Authorization

## Tokens

- **Access token** — short-lived (default 15 min) JWT. Signed with
  `JWT_SECRET_KEY` (HS256). Claims:
  ```json
  { "sub": "<user_id>", "role": "ADMIN", "token_version": 1,
    "type": "access", "jti": "...", "exp": 0, "iat": 0 }
  ```
- **Refresh token** — long-lived (default 30 days) opaque random string.
  Stored **hashed** (Argon2id) in `refresh_tokens`. Raw tokens are never stored.

## Session invalidation

`users.token_version` is embedded in every access token. Incrementing it (on
role change, status change, or password change) instantly invalidates all
existing access tokens for that user. Refresh tokens can also be revoked
individually or all at once.

## Rotation

`POST /auth/refresh` validates the presented refresh token, revokes it, and
issues a new one. A leaked refresh token is therefore single-use.

## Password hashing

Argon2id via `argon2-cffi` (`PasswordHasher` defaults). Plaintext passwords are
never logged or stored. Strength rules: ≥8 chars, at least one letter and one
digit, no leading/trailing whitespace.

## Roles & permissions

The **server** derives permissions from the role — the client cannot request
scopes. See `app/core/rbac.py`.

| Permission | ADMIN | USER |
|-----------|:-----:|:----:|
| cctv.read | ✓ | ✓ |
| cctv.create | ✓ | |
| cctv.update | ✓ | |
| cctv.delete | ✓ | |
| cctv.image.upload | ✓ | |
| cctv.image.delete | ✓ | |
| user.read/create/update/delete | ✓ | |
| audit.read | ✓ | |

Enforcement happens in FastAPI via the `require_permission(...)` dependency.
Hiding a button in Flutter is **not** authorization; the API returns `403` for
any attempt by a USER to mutate data.

## Brute-force protection

`/auth/login`, `/auth/refresh`, and `/auth/change-password` are rate limited (a
token-bucket per client IP). Behind multiple replicas, move this to Redis or an
API gateway.
