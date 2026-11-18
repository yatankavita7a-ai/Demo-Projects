# CodeTrack

One place for a student's coding journey: connect **LeetCode, GeeksforGeeks, CodeChef, Codeforces and GitHub**,
and CodeTrack pulls real stats from each platform into a single dashboard, progress chart, public portfolio and
leaderboard. College accounts get a dashboard of their students; recruiter accounts can explore and filter
public student profiles.

```
CodeTrack/
├── API.md                 REST API reference
├── codetrack/             Spring Boot backend (Java, Spring Security + JWT, JPA, PostgreSQL)
└── codetrack-frontend/    HTML / CSS / JavaScript frontend (no build step)
```

## Run it

### 1. Backend (port 8080)

**With PostgreSQL** (default). Create the database once, then start the app; tables are created automatically.

```bash
createdb codetrack
```

```bash
cd codetrack
DB_USERNAME=postgres DB_PASSWORD=yourpassword ./mvnw spring-boot:run
```

**Without PostgreSQL** (H2 file database in `codetrack/data/`, handy for development):

```bash
cd codetrack
./mvnw spring-boot:run -Dspring-boot.run.profiles=dev
```

The `dev` profile also creates **demo accounts** on first start, so every page has data. All use the
password `demo1234`:

| Account | Email |
|---|---|
| 30 students (6 per institute, 120 to 2,000 problems solved each) | e.g. `aarav.sharma@codetrack.demo`, `arjun.reddy@codetrack.demo` |
| Institutes: IIT Delhi, NIT Trichy, BITS Pilani, DTU, VIT Vellore | `placements.iitdelhi@codetrack.demo`, `placements.nittrichy@codetrack.demo`, `placements.bitspilani@codetrack.demo`, `placements.dtu@codetrack.demo`, `placements.vit@codetrack.demo` |
| Recruiter | `recruiter@codetrack.demo` |

Demo stats are generated and are never synced against the real platforms. To start over, stop the
app and delete `codetrack/data/`.

If `java` isn't on your PATH (Homebrew OpenJDK), set `JAVA_HOME` first, e.g.
`export JAVA_HOME=$(/usr/libexec/java_home 2>/dev/null || echo /opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home)`.

### 2. Frontend (port 5500)

Open `codetrack-frontend/` with VS Code **Live Server**, or:

```bash
cd codetrack-frontend && python3 -m http.server 5500
```

Then visit <http://localhost:5500>.

### Tests

```bash
cd codetrack && ./mvnw test
```

## Configuration

| Env var | Default | Purpose |
|---|---|---|
| `DB_URL` | `jdbc:postgresql://localhost:5432/codetrack` | JDBC URL |
| `DB_USERNAME` / `DB_PASSWORD` | `postgres` / `postgres` | DB credentials |
| `JWT_SECRET` | dev-only value | **Set a random 32+ char secret in any shared/deployed environment** |
| `CORS_ORIGINS` | `http://localhost:5500,http://127.0.0.1:5500` | Allowed frontend origins |
| `GITHUB_TOKEN` | empty | Optional; raises GitHub API rate limit from 60 to 5000 requests/hour |
| `PORT` | `8080` | HTTP port |

Platform stats refresh automatically every day at 03:00 (`app.sync.cron`) and on demand from the UI
(at most once per 30 s per platform).

## How it works

- **Auth**: register/login return a JWT (24 h). `JwtAuthenticationFilter` validates it on every request, checks
  the account still exists and that the token hasn't been revoked (a per-user `tokenVersion`, bumped by
  "Sign out everywhere" and by password changes). Private endpoints always act on the user in the token —
  there's no way to pass another user's id. Passwords are hashed with BCrypt.
- **Roles**: `STUDENT` (connects platforms), `COLLEGE` (sees students whose profile college matches its own),
  `RECRUITER` (explores public profiles). Roles are self-selected at registration and not verified yet.
- **Platform data**: each platform has a fetcher in `service/platform/` — official APIs for Codeforces and GitHub,
  LeetCode's public GraphQL endpoint, and best-effort page parsing for CodeChef and GeeksforGeeks (these can
  break if the sites change their pages; the error is shown on the card instead of failing the dashboard).
- **Progress**: every sync stores one point per day of total problems solved, drawn as the progress chart.
- **Privacy**: profiles are public by default and can be made private in Profile. Private profiles are hidden
  from leaderboards, college dashboards and the public portfolio link. Emails are never shown publicly.

See [API.md](API.md) for every endpoint.

## Existing database

If you already have a `users` table from the first version, it keeps working: new columns are added
automatically and older rows are treated as public student accounts.

## Not done yet / ideas

- Verifying college and recruiter accounts (e.g. by email domain) before granting access.
- Email verification and password reset by email.
- Public deployment (Docker image, hosted PostgreSQL, HTTPS).
- More platforms (HackerRank, AtCoder, …) — add a `PlatformFetcher` bean and an enum value.
