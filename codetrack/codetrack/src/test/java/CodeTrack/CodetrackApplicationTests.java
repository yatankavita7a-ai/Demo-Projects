package CodeTrack;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.util.UUID;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * End-to-end API tests against a real server on a random port with an in-memory H2 database.
 * Platform syncing is disabled (app.sync.on-link=false) so no network access is needed.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@ActiveProfiles("test")
class CodetrackApplicationTests {

    @Value("${local.server.port}")
    int port;

    private final HttpClient http = HttpClient.newHttpClient();

    record Res(int status, String body) {}

    Res call(String method, String path, String token, String json) throws Exception {
        HttpRequest.Builder b = HttpRequest.newBuilder(URI.create("http://localhost:" + port + "/api" + path))
                .header("Content-Type", "application/json")
                .method(method, json == null ? HttpRequest.BodyPublishers.noBody() : HttpRequest.BodyPublishers.ofString(json));
        if (token != null) b.header("Authorization", "Bearer " + token);
        HttpResponse<String> r = http.send(b.build(), HttpResponse.BodyHandlers.ofString());
        return new Res(r.statusCode(), r.body());
    }

    static String field(String json, String name) {
        Matcher m = Pattern.compile("\"" + name + "\":\"?([^\",}]*)").matcher(json);
        return m.find() ? m.group(1) : null;
    }

    String register(String email, String role) throws Exception {
        Res r = call("POST", "/auth/register", null, """
                {"name":"Test User","email":"%s","password":"secret123","college":"Test College","role":"%s"}
                """.formatted(email, role));
        assertThat(r.status()).as(r.body()).isEqualTo(201);
        return field(r.body(), "token");
    }

    static String email() {
        return "u" + UUID.randomUUID().toString().substring(0, 8) + "@example.com";
    }

    @Test
    void registerLoginAndAccessProtectedEndpoints() throws Exception {
        String email = email();
        String token = register(email, "STUDENT");

        assertThat(call("GET", "/users/me", null, null).status()).isEqualTo(401);
        assertThat(call("GET", "/users/me", "not.a.jwt", null).status()).isEqualTo(401);

        Res me = call("GET", "/users/me", token, null);
        assertThat(me.status()).isEqualTo(200);
        assertThat(me.body()).contains(email).doesNotContain("password");

        Res login = call("POST", "/auth/login", null, "{\"email\":\"" + email.toUpperCase() + "\",\"password\":\"secret123\"}");
        assertThat(login.status()).isEqualTo(200);
        assertThat(call("POST", "/auth/login", null, "{\"email\":\"" + email + "\",\"password\":\"wrong-pass\"}").status())
                .isEqualTo(401);
    }

    @Test
    void validationAndDuplicateEmail() throws Exception {
        Res bad = call("POST", "/auth/register", null, "{\"name\":\"\",\"email\":\"nope\",\"password\":\"123\"}");
        assertThat(bad.status()).isEqualTo(400);
        assertThat(bad.body()).contains("\"fields\"").contains("email").contains("password");

        String email = email();
        register(email, "STUDENT");
        Res dup = call("POST", "/auth/register", null,
                "{\"name\":\"X\",\"email\":\"" + email + "\",\"password\":\"secret123\"}");
        assertThat(dup.status()).isEqualTo(409);
    }

    @Test
    void logoutEverywhereAndPasswordChangeRevokeTokens() throws Exception {
        String token = register(email(), "STUDENT");
        assertThat(call("POST", "/auth/logout-all", token, null).status()).isEqualTo(204);
        assertThat(call("GET", "/users/me", token, null).status()).isEqualTo(401);

        String email = email();
        String t1 = register(email, "STUDENT");
        Res changed = call("PUT", "/users/me/password", t1,
                "{\"currentPassword\":\"secret123\",\"newPassword\":\"newsecret456\"}");
        assertThat(changed.status()).isEqualTo(200);
        String t2 = field(changed.body(), "token");
        assertThat(call("GET", "/users/me", t1, null).status()).isEqualTo(401);
        assertThat(call("GET", "/users/me", t2, null).status()).isEqualTo(200);
    }

    @Test
    void platformLinkingAndRoleRestrictions() throws Exception {
        String student = register(email(), "STUDENT");
        Res linked = call("PUT", "/platforms/codeforces", student, "{\"input\":\"https://codeforces.com/profile/tourist\"}");
        assertThat(linked.status()).as(linked.body()).isEqualTo(200);
        assertThat(field(linked.body(), "username")).isEqualTo("tourist");

        Res wrongHost = call("PUT", "/platforms/leetcode", student, "{\"input\":\"https://github.com/someone\"}");
        assertThat(wrongHost.status()).isEqualTo(400);

        Res dash = call("GET", "/dashboard", student, null);
        assertThat(dash.status()).isEqualTo(200);
        assertThat(dash.body()).contains("\"platformsConnected\":1");

        String recruiter = register(email(), "RECRUITER");
        assertThat(call("GET", "/platforms", recruiter, null).status()).isEqualTo(403);
        assertThat(call("GET", "/college/overview", recruiter, null).status()).isEqualTo(403);
        assertThat(call("GET", "/leaderboard", recruiter, null).status()).isEqualTo(200);

        String college = register(email(), "COLLEGE");
        Res overview = call("GET", "/college/overview", college, null);
        assertThat(overview.status()).as(overview.body()).isEqualTo(200);
        assertThat(overview.body()).contains("Test College");
    }

    @Test
    void publicProfileRespectsPrivacy() throws Exception {
        String token = register(email(), "STUDENT");
        String id = field(call("GET", "/users/me", token, null).body(), "id");

        Res pub = call("GET", "/public/users/" + id, null, null);
        assertThat(pub.status()).isEqualTo(200);
        assertThat(pub.body()).doesNotContain("@example.com");

        Res upd = call("PUT", "/users/me", token, "{\"name\":\"Private\",\"publicProfile\":false}");
        assertThat(upd.status()).as(upd.body()).isEqualTo(200);
        assertThat(call("GET", "/public/users/" + id, null, null).status()).isEqualTo(404);
    }

    @Test
    void deleteAccountRequiresPassword() throws Exception {
        String token = register(email(), "STUDENT");
        assertThat(call("DELETE", "/users/me", token, "{\"password\":\"wrong\"}").status()).isEqualTo(400);
        assertThat(call("DELETE", "/users/me", token, "{\"password\":\"secret123\"}").status()).isEqualTo(204);
        assertThat(call("GET", "/users/me", token, null).status()).isEqualTo(401);
    }
}
