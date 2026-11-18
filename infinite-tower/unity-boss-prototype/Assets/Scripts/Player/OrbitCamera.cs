using UnityEngine;

namespace BossPrototype
{
    /// <summary>
    /// Mouse orbit camera. Lock-on frames the boss's chest; for bosses 3x the player's size or bigger
    /// it pulls back and rises. Includes screen shake. Uses unscaled time so hit-stop doesn't freeze it.
    /// </summary>
    [RequireComponent(typeof(Camera))]
    public class OrbitCamera : MonoBehaviour
    {
        public static OrbitCamera Instance { get; private set; }

        public float sensitivity = 2.4f;
        public float distance = 6.5f;
        public float minPitch = -10f;
        public float maxPitch = 65f;

        float yaw;
        float pitch = 18f;
        Vector3 velocity;
        Vector3 lookPoint;
        bool initialised;

        float shakeAmplitude;
        float shakeRemaining;
        float shakeDuration = 0.01f;

        public Vector3 FlatForward
        {
            get
            {
                Vector3 f = transform.forward;
                f.y = 0f;
                return f.sqrMagnitude > 0.0001f ? f.normalized : Vector3.forward;
            }
        }

        void OnEnable() { Instance = this; }
        void OnDisable() { if (Instance == this) Instance = null; }

        public static void Shake(float amplitude, float duration)
        {
            if (Instance == null) return;
            if (amplitude >= Instance.shakeAmplitude * (Instance.shakeRemaining / Instance.shakeDuration))
            {
                Instance.shakeAmplitude = amplitude;
                Instance.shakeDuration = Mathf.Max(0.01f, duration);
                Instance.shakeRemaining = duration;
            }
        }

        public void SnapBehind(Transform target)
        {
            if (target == null) return;
            yaw = target.eulerAngles.y;
            pitch = 18f;
            initialised = false;
        }

        void LateUpdate()
        {
            var player = PlayerController.Instance;
            if (player == null) return;
            float dt = Time.unscaledDeltaTime;

            // Cursor capture: click to capture, Escape to release.
            if (GameInput.MouseDown(0) && Cursor.lockState != CursorLockMode.Locked) { Cursor.lockState = CursorLockMode.Locked; Cursor.visible = false; }
            if (GameInput.KeyDown(KeyCode.Escape)) { Cursor.lockState = CursorLockMode.None; Cursor.visible = true; }

            Vector2 mouse = GameInput.MouseDelta();
            Vector3 pivot = player.transform.position + Vector3.up * 1.6f;
            var boss = BossController.Instance;
            Vector3 desiredPos;
            Vector3 desiredLook;

            if (player.LockedOn && boss != null && boss.IsAlive)
            {
                Vector3 chest = boss.ChestPosition;
                Vector3 dir = CombatMath.Flat(chest - pivot);
                if (dir.sqrMagnitude < 0.01f) dir = player.transform.forward;
                dir.Normalize();
                bool large = CombatMath.IsLargeBoss(boss.Scale);
                float back = large ? 8f + boss.Scale * 0.9f : 5.5f + boss.Scale;
                float up = large ? 2.5f + boss.Scale * 0.6f : 1.6f + boss.Scale * 0.4f;
                desiredPos = pivot - dir * back + Vector3.up * up;
                // Frame the chest, keeping the player in the lower part of the screen.
                desiredLook = Vector3.Lerp(pivot, chest, large ? 0.6f : 0.55f);
                Vector3 e = Quaternion.LookRotation(desiredLook - desiredPos).eulerAngles;
                yaw = e.y;
                pitch = e.x > 180f ? e.x - 360f : e.x;
            }
            else
            {
                yaw += mouse.x * sensitivity;
                pitch = Mathf.Clamp(pitch - mouse.y * sensitivity, minPitch, maxPitch);
                Quaternion rot = Quaternion.Euler(pitch, yaw, 0f);
                desiredPos = pivot - rot * Vector3.forward * distance;
                desiredLook = pivot;
            }
            if (desiredPos.y < 0.4f) desiredPos.y = 0.4f;

            if (!initialised)
            {
                transform.position = desiredPos;
                lookPoint = desiredLook;
                initialised = true;
            }
            transform.position = Vector3.SmoothDamp(transform.position, desiredPos, ref velocity, 0.08f, Mathf.Infinity, dt);
            lookPoint = Vector3.Lerp(lookPoint, desiredLook, 1f - Mathf.Exp(-14f * dt));
            transform.rotation = Quaternion.LookRotation(lookPoint - transform.position);

            if (shakeRemaining > 0f)
            {
                shakeRemaining -= dt;
                float k = Mathf.Clamp01(shakeRemaining / shakeDuration);
                transform.position += Random.insideUnitSphere * shakeAmplitude * k;
            }
        }
    }
}
