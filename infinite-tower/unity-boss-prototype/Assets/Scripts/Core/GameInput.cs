using UnityEngine;

namespace BossPrototype
{
    /// <summary>
    /// Thin wrapper over the legacy Input Manager. If the project is switched to
    /// "Input System Package (New)" only, the legacy API throws; we then report it once
    /// on the HUD instead of spamming exceptions every frame.
    /// </summary>
    public static class GameInput
    {
        public static bool Available { get; private set; } = true;
        public static string Problem { get; private set; }

        static Vector3 lastMouse;
        static int lastMouseFrame = -1;
        static bool axisMissing;

        static void Fail(System.Exception e)
        {
            if (!Available) return;
            Available = false;
            Problem = "Legacy input unavailable: set Project Settings > Player > Active Input Handling to 'Input Manager (Old)' or 'Both'. (" + e.GetType().Name + ")";
            Debug.LogError("[BossPrototype] " + Problem);
        }

        public static bool Key(KeyCode k)
        {
            if (!Available) return false;
            try { return Input.GetKey(k); } catch (System.InvalidOperationException e) { Fail(e); return false; }
        }

        public static bool KeyDown(KeyCode k)
        {
            if (!Available) return false;
            try { return Input.GetKeyDown(k); } catch (System.InvalidOperationException e) { Fail(e); return false; }
        }

        public static bool KeyUp(KeyCode k)
        {
            if (!Available) return false;
            try { return Input.GetKeyUp(k); } catch (System.InvalidOperationException e) { Fail(e); return false; }
        }

        public static bool Mouse(int b)
        {
            if (!Available) return false;
            try { return Input.GetMouseButton(b); } catch (System.InvalidOperationException e) { Fail(e); return false; }
        }

        public static bool MouseDown(int b)
        {
            if (!Available) return false;
            try { return Input.GetMouseButtonDown(b); } catch (System.InvalidOperationException e) { Fail(e); return false; }
        }

        public static bool MouseUp(int b)
        {
            if (!Available) return false;
            try { return Input.GetMouseButtonUp(b); } catch (System.InvalidOperationException e) { Fail(e); return false; }
        }

        /// <summary>Mouse delta in Input-Manager axis units (falls back to pixel delta if axes are missing).</summary>
        public static Vector2 MouseDelta()
        {
            if (!Available) return Vector2.zero;
            try
            {
                if (!axisMissing)
                {
                    try { return new Vector2(Input.GetAxisRaw("Mouse X"), Input.GetAxisRaw("Mouse Y")); }
                    catch (System.ArgumentException) { axisMissing = true; }
                }
                Vector3 m = Input.mousePosition;
                Vector2 delta = Vector2.zero;
                if (lastMouseFrame >= 0 && lastMouseFrame != Time.frameCount) delta = (m - lastMouse) * 0.1f;
                lastMouse = m;
                lastMouseFrame = Time.frameCount;
                return delta;
            }
            catch (System.InvalidOperationException e) { Fail(e); return Vector2.zero; }
        }

        public static Vector2 Move()
        {
            float x = 0f, y = 0f;
            if (Key(KeyCode.W) || Key(KeyCode.UpArrow)) y += 1f;
            if (Key(KeyCode.S) || Key(KeyCode.DownArrow)) y -= 1f;
            if (Key(KeyCode.D) || Key(KeyCode.RightArrow)) x += 1f;
            if (Key(KeyCode.A) || Key(KeyCode.LeftArrow)) x -= 1f;
            return Vector2.ClampMagnitude(new Vector2(x, y), 1f);
        }

        public static bool LightDown() { return MouseDown(0); }
        public static bool HeavyDown() { return MouseDown(1); }
        public static bool HeavyHeld() { return Mouse(1); }
        public static bool BlockHeld() { return Key(KeyCode.Q) || Key(KeyCode.LeftShift); }
        public static bool BlockDown() { return KeyDown(KeyCode.Q) || KeyDown(KeyCode.LeftShift); }
        public static bool RollDown() { return KeyDown(KeyCode.Space); }
        public static bool LockDown() { return KeyDown(KeyCode.Tab) || MouseDown(2); }
        public static bool ImmobilizeDown() { return KeyDown(KeyCode.V); }
    }
}
