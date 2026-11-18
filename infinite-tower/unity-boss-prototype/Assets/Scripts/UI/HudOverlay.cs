using UnityEngine;

namespace BossPrototype
{
    /// <summary>IMGUI HUD: player bars, Focus pips, Immobilize, boss bars, lock-on marker, messages, help (H).</summary>
    public class HudOverlay : MonoBehaviour
    {
        public static HudOverlay Instance { get; private set; }

        public bool showHelp = true;

        string message;
        Color messageColor = Color.white;
        float messageUntil;

        GUIStyle label, small, smallRight, smallCenter, centered, big;
        const float RefHeight = 1080f;

        void OnEnable() { Instance = this; }
        void OnDisable() { if (Instance == this) Instance = null; }

        public static void Flash(string text, Color color, float seconds)
        {
            if (Instance == null) return;
            Instance.message = text;
            Instance.messageColor = color;
            Instance.messageUntil = Time.unscaledTime + seconds;
        }

        void Update()
        {
            if (GameInput.KeyDown(KeyCode.H)) showHelp = !showHelp;
        }

        void EnsureStyles()
        {
            if (label != null) return;
            label = new GUIStyle(GUI.skin.label) { fontSize = 20, fontStyle = FontStyle.Bold };
            label.normal.textColor = Color.white;
            small = new GUIStyle(GUI.skin.label) { fontSize = 17, wordWrap = true };
            small.normal.textColor = new Color(0.92f, 0.92f, 0.92f);
            smallRight = new GUIStyle(small) { alignment = TextAnchor.UpperRight };
            smallCenter = new GUIStyle(small) { alignment = TextAnchor.UpperCenter };
            centered = new GUIStyle(label) { fontSize = 30, alignment = TextAnchor.MiddleCenter };
            big = new GUIStyle(label) { fontSize = 96, alignment = TextAnchor.MiddleCenter };
        }

        static void Fill(Rect r, Color c)
        {
            var old = GUI.color;
            GUI.color = c;
            GUI.DrawTexture(r, Texture2D.whiteTexture);
            GUI.color = old;
        }

        static void Bar(Rect r, float fraction, Color fill, Color back)
        {
            Fill(new Rect(r.x - 2, r.y - 2, r.width + 4, r.height + 4), new Color(0f, 0f, 0f, 0.6f));
            Fill(r, back);
            Fill(new Rect(r.x, r.y, r.width * Mathf.Clamp01(fraction), r.height), fill);
        }

        static void Shadowed(Rect r, string text, GUIStyle style, Color color)
        {
            var c = style.normal.textColor;
            style.normal.textColor = new Color(0f, 0f, 0f, 0.8f);
            GUI.Label(new Rect(r.x + 2, r.y + 2, r.width, r.height), text, style);
            style.normal.textColor = color;
            GUI.Label(r, text, style);
            style.normal.textColor = c;
        }

        void OnGUI()
        {
            EnsureStyles();
            float scale = Screen.height / RefHeight;
            if (scale <= 0f) return;
            GUI.matrix = Matrix4x4.TRS(Vector3.zero, Quaternion.identity, new Vector3(scale, scale, 1f));
            float w = Screen.width / scale;
            float h = RefHeight;

            var player = PlayerController.Instance;
            var boss = BossController.Instance;

            if (!GameInput.Available)
                Shadowed(new Rect(20, h - 60, w - 40, 40), GameInput.Problem, small, new Color(1f, 0.5f, 0.4f));

            if (player != null) DrawPlayer(player);
            if (boss != null && boss.Def != null) DrawBoss(boss, w, h, player, scale);

            if (message != null && Time.unscaledTime < messageUntil)
                Shadowed(new Rect(0, h * 0.24f, w, 50), message, centered, messageColor);

            if (player != null && !player.IsAlive)
            {
                Fill(new Rect(0, h * 0.38f, w, 200), new Color(0f, 0f, 0f, 0.55f));
                Shadowed(new Rect(0, h * 0.38f, w, 140), "YOU DIED", big, new Color(0.75f, 0.08f, 0.06f));
                Shadowed(new Rect(0, h * 0.38f + 130, w, 50), "Press R to restart", centered, Color.white);
            }
            else if (boss != null && boss.Def != null && !boss.IsAlive && boss.StateTime > 1f)
            {
                Fill(new Rect(0, h * 0.38f, w, 200), new Color(0f, 0f, 0f, 0.45f));
                Shadowed(new Rect(0, h * 0.38f, w, 140), "VICTORY", big, new Color(1f, 0.82f, 0.35f));
                Shadowed(new Rect(0, h * 0.38f + 130, w, 50), "Press R to fight again, or 1-4 to choose another boss", centered, Color.white);
            }

            if (showHelp) DrawHelp(w);
            else Shadowed(new Rect(w - 260, 16, 240, 30), "H: controls", small, Color.white);
        }

        void DrawPlayer(PlayerController p)
        {
            float x = 30f, y = 30f;
            Bar(new Rect(x, y, 380, 22), p.Health / p.maxHealth, new Color(0.78f, 0.12f, 0.1f), new Color(0.2f, 0.05f, 0.05f, 0.8f));
            Shadowed(new Rect(x + 8, y - 1, 300, 26), Mathf.CeilToInt(p.Health) + " / " + Mathf.CeilToInt(p.maxHealth), small, Color.white);
            y += 32f;
            Bar(new Rect(x, y, 300, 14), p.Stamina / p.maxStamina, new Color(0.25f, 0.75f, 0.3f), new Color(0.05f, 0.18f, 0.05f, 0.8f));
            y += 26f;
            Shadowed(new Rect(x, y, 80, 26), "Focus", small, Color.white);
            for (int i = 0; i < Tuning.MaxFocus; i++)
            {
                var r = new Rect(x + 70 + i * 34, y + 3, 26, 20);
                Fill(new Rect(r.x - 2, r.y - 2, r.width + 4, r.height + 4), new Color(0f, 0f, 0f, 0.6f));
                bool lit = i < p.Focus;
                Color c = lit ? new Color(0.5f, 0.82f, 1f) : new Color(0.15f, 0.2f, 0.28f, 0.9f);
                if (lit && p.IsChargingHeavy) c = Color.Lerp(c, Color.white, 0.5f + 0.5f * Mathf.Sin(Time.unscaledTime * 20f));
                Fill(r, c);
            }
            y += 32f;
            float cd = p.ImmobilizeCooldown;
            string imm = cd > 0f ? "Immobilize (V): " + Mathf.CeilToInt(cd) + "s" : "Immobilize (V): READY";
            Shadowed(new Rect(x, y, 300, 26), imm, small, cd > 0f ? Color.gray : new Color(1f, 0.85f, 0.35f));
            Bar(new Rect(x, y + 28, 200, 6), 1f - cd / Tuning.ImmobilizeCooldown, new Color(1f, 0.85f, 0.35f), new Color(0.1f, 0.1f, 0.1f, 0.8f));
            y += 44f;
            if (p.LockedOn) Shadowed(new Rect(x, y, 300, 26), "LOCKED ON", small, new Color(1f, 0.6f, 0.4f));
        }

        void DrawBoss(BossController b, float w, float h, PlayerController p, float scale)
        {
            float bw = Mathf.Min(900f, w - 80f);
            float x = (w - bw) * 0.5f;
            float y = h - 120f;
            string phase = b.Phase >= 2 ? "  -  Phase 2" : "";
            Shadowed(new Rect(x, y - 34, bw, 30), b.Def.name + phase, label, new Color(1f, 0.92f, 0.8f));
            string info = b.Scale.ToString("0.0") + "x";
            if (b.IsFrozen) info += "   IMMOBILIZED";
            else if (b.ImmobilizeImmunity > 0f) info += "   immune to Immobilize " + Mathf.CeilToInt(b.ImmobilizeImmunity) + "s";
            if (b.State == BossState.Staggered) info += "   STAGGERED";
            if (b.State == BossState.Roar) info += "   ROARING (invulnerable)";
            Shadowed(new Rect(x, y - 30, bw, 26), info, smallRight, new Color(0.85f, 0.85f, 0.85f));
            Bar(new Rect(x, y, bw, 18), b.Health / b.Def.maxHealth, new Color(0.7f, 0.1f, 0.08f), new Color(0.15f, 0.04f, 0.04f, 0.85f));

            // Posture bar grows from the centre outward (Sekiro style).
            float pf = Mathf.Clamp01(b.Posture / b.Def.maxPosture);
            var pr = new Rect(x + bw * 0.2f, y + 28, bw * 0.6f, 10);
            Fill(new Rect(pr.x - 2, pr.y - 2, pr.width + 4, pr.height + 4), new Color(0f, 0f, 0f, 0.6f));
            Fill(pr, new Color(0.12f, 0.1f, 0.05f, 0.85f));
            float half = pr.width * 0.5f * pf;
            Color postureColor = b.State == BossState.Staggered ? new Color(1f, 0.95f, 0.6f) : Color.Lerp(new Color(1f, 0.7f, 0.2f), new Color(1f, 0.3f, 0.1f), pf);
            Fill(new Rect(pr.center.x - half, pr.y, half * 2f, pr.height), postureColor);

            if (b.State == BossState.Windup && b.CurrentAttack != null && b.CurrentAttack.HasHitbox)
                Shadowed(new Rect(x, y + 44, bw, 26), b.CurrentAttack.name, smallCenter, Util.AttackColorValue(b.CurrentAttack.color));

            // Lock-on marker on the boss's chest.
            var cam = OrbitCamera.Instance != null ? OrbitCamera.Instance.GetComponent<Camera>() : null;
            if (p != null && p.LockedOn && cam != null)
            {
                Vector3 sp = cam.WorldToScreenPoint(b.ChestPosition);
                if (sp.z > 0f)
                {
                    float gx = sp.x / scale, gy = (Screen.height - sp.y) / scale;
                    Fill(new Rect(gx - 7, gy - 7, 14, 14), new Color(0f, 0f, 0f, 0.7f));
                    Fill(new Rect(gx - 4, gy - 4, 8, 8), new Color(1f, 0.85f, 0.6f));
                }
            }
        }

        void DrawHelp(float w)
        {
            const string text =
                "WASD  move (strafe while locked)\n" +
                "Mouse  orbit camera (click to capture, Esc to release)\n" +
                "Tab / Middle mouse  lock on\n" +
                "LMB  light attack (every 3rd hit in a row: +1 Focus)\n" +
                "RMB  heavy  |  hold RMB with Focus: charged heavy\n" +
                "Q / Left Shift  block (press just before a hit to parry)\n" +
                "Space  dodge roll (perfect dodge: slow-mo, +1 Focus)\n" +
                "V  Immobilize (2.5 s, 45 s cooldown)\n" +
                "1-4  boss: Cinder Warden, Brass Regent, Drowned Cantor, Pale Huntress\n" +
                "R  restart    H  hide this panel\n\n" +
                "Markers: orange = normal, yellow = parryable, red = unblockable (dodge!)";
            var r = new Rect(w - 560, 16, 540, 340);
            Fill(r, new Color(0f, 0f, 0f, 0.55f));
            GUI.Label(new Rect(r.x + 14, r.y + 10, r.width - 28, r.height - 20), text, small);
        }
    }
}
