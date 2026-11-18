# CodeTrack REST API

Base URL: `http://localhost:8080/api`

All request/response bodies are JSON. Private endpoints need the header
`Authorization: Bearer <token>`. Tokens last 24 hours.

## Errors

Every error has the same shape:

```json
{ "status": 400, "error": "Bad Request", "message": "Human readable message",
  "fields": { "email": "must be a well-formed email address" }, "timestamp": "2026-11-18T10:00:00Z" }
```

`fields` is present only for validation errors. `401` = missing/invalid/expired/revoked token
(the frontend should log out). `403` = logged in but not allowed (wrong role).

## Shared objects

**User**
```json
{ "id": 1, "name": "Asha", "email": "asha@x.com", "college": "IIT Delhi", "course": "B.Tech",
  "branch": "CSE", "graduationYear": 2027, "bio": "...", "location": "Delhi",
  "role": "STUDENT", "publicProfile": true, "createdAt": "2026-11-01T09:00:00Z" }
```
`role` is one of `STUDENT`, `COLLEGE`, `RECRUITER`.

**PlatformProfile** (any numeric stat may be `null` when the platform doesn't provide it)
```json
{ "platform": "LEETCODE", "displayName": "LeetCode", "username": "asha", "profileUrl": "https://leetcode.com/u/asha/",
  "totalSolved": 412, "easySolved": 150, "mediumSolved": 210, "hardSolved": 52,
  "rating": 1820, "maxRating": 1850, "rankTitle": "Knight", "globalRank": 40213, "contests": 31,
  "score": null, "repos": null, "followers": null, "stars": null,
  "syncStatus": "OK", "syncMessage": null, "lastSyncedAt": "2026-11-18T09:58:00Z" }
```
`platform` values: `LEETCODE`, `GEEKSFORGEEKS`, `CODECHEF`, `CODEFORCES`, `GITHUB`.
`syncStatus`: `PENDING` (never synced), `OK`, `ERROR` (`syncMessage` explains).
GitHub uses `repos`, `followers`, `stars`; GfG uses `score`; CP platforms use rating fields.

**Summary**
```json
{ "totalSolved": 900, "easySolved": 300, "mediumSolved": 450, "hardSolved": 150,
  "platformsConnected": 4, "contests": 55, "githubRepos": 18, "githubStars": 40,
  "bestRatings": { "CODEFORCES": 1540, "LEETCODE": 1820, "CODECHEF": 1700 },
  "lastSyncedAt": "2026-11-18T09:58:00Z", "collegeRank": 3, "collegeSize": 42 }
```
`collegeRank`/`collegeSize` are null if the user has no college or isn't public.

**ProgressPoint**: `{ "date": "2026-11-18", "totalSolved": 900 }` (one per day the user synced)

**LeaderboardEntry**
```json
{ "rank": 1, "userId": 7, "name": "Asha", "college": "IIT Delhi", "branch": "CSE", "graduationYear": 2027,
  "totalSolved": 900, "hardSolved": 150, "platforms": ["LEETCODE","CODEFORCES"],
  "codeforcesRating": 1540, "leetcodeRating": 1820, "codechefRating": null, "me": false }
```

## Auth

| Method | Path | Body | Response |
|---|---|---|---|
| POST | `/auth/register` | `{name, email, password (8-72 chars), college?, role?}` | `201 {token, user}` |
| POST | `/auth/login` | `{email, password}` | `200 {token, user}` |
| POST | `/auth/logout-all` | – | `204` — revokes every token issued to this user (sign out everywhere) |

Registration logs the user in (returns a token). Duplicate email → `409`. Bad credentials → `401`.

## Current user (private)

| Method | Path | Body | Response |
|---|---|---|---|
| GET | `/users/me` | – | `User` |
| PUT | `/users/me` | `{name, college?, course?, branch?, graduationYear?, bio?, location?, publicProfile}` | `User` |
| PUT | `/users/me/password` | `{currentPassword, newPassword}` | `{token, user}` — old tokens are revoked, use the new one |
| DELETE | `/users/me` | `{password}` | `204` |

## Platforms (private, STUDENT data)

| Method | Path | Body | Response |
|---|---|---|---|
| GET | `/platforms` | – | `PlatformProfile[]` (only connected ones) |
| PUT | `/platforms/{platform}` | `{input}` — a profile URL **or** a username | `PlatformProfile` (synced immediately) |
| DELETE | `/platforms/{platform}` | – | `204` |
| POST | `/platforms/{platform}/sync` | – | `PlatformProfile` |
| POST | `/platforms/sync` | – | `PlatformProfile[]` |

`{platform}` is case-insensitive; `gfg` also works. Re-syncing the same profile within 30 seconds
returns the cached data. Invalid URL/username → `400` with a helpful message.

## Dashboard (private)

`GET /dashboard` →
```json
{ "user": User, "summary": Summary, "platforms": PlatformProfile[], "progress": ProgressPoint[] }
```

## Leaderboard / explore (private, any role)

`GET /leaderboard?q=&college=&platform=&minSolved=&sort=solved|hard|codeforces|leetcode|codechef&limit=50`
→ `LeaderboardEntry[]`. Only students with a public profile appear. `q` matches name or college.

## College dashboard (private, role COLLEGE)

`GET /college/overview` →
```json
{ "college": "IIT Delhi", "studentCount": 42, "activeCount": 30, "totalSolved": 12000, "averageSolved": 285,
  "platformAdoption": { "LEETCODE": 35, "CODEFORCES": 20, "CODECHEF": 10, "GEEKSFORGEEKS": 25, "GITHUB": 28 },
  "distribution": { "0": 12, "1-50": 5, "51-200": 10, "201-500": 9, "500+": 6 },
  "topStudents": LeaderboardEntry[] }
```
Returns `400` if the college account hasn't set a college name.

## Public (no token needed)

| Method | Path | Response |
|---|---|---|
| GET | `/public/users/{id}` | `{ id, name, college, course, branch, graduationYear, bio, location, memberSince, summary, platforms, progress }` — `404` unless the student made their profile public |
| GET | `/health` | `{ "status": "UP" }` |
