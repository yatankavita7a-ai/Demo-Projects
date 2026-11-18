using UnityEngine;

namespace BossPrototype
{
    /// <summary>Hit-stop and slow motion via Time.timeScale, driven by unscaled time.</summary>
    public class GameFeel : MonoBehaviour
    {
        public static GameFeel Instance { get; private set; }

        float hitStopRemaining;
        float hitStopScale = 1f;
        float slowMoRemaining;
        float slowMoScale = 1f;

        void OnEnable() { Instance = this; }

        void OnDisable()
        {
            if (Instance == this) Instance = null;
            Time.timeScale = 1f;
        }

        public static void HitStop(float realSeconds, float scale = 0.05f)
        {
            if (Instance == null) return;
            Instance.hitStopRemaining = Mathf.Max(Instance.hitStopRemaining, realSeconds);
            Instance.hitStopScale = scale;
            Instance.Apply();
        }

        public static void SlowMo(float scale, float realSeconds)
        {
            if (Instance == null) return;
            Instance.slowMoRemaining = Mathf.Max(Instance.slowMoRemaining, realSeconds);
            Instance.slowMoScale = scale;
            Instance.Apply();
        }

        public static void ResetTime()
        {
            if (Instance != null) { Instance.hitStopRemaining = 0f; Instance.slowMoRemaining = 0f; }
            Time.timeScale = 1f;
        }

        void Update()
        {
            float dt = Time.unscaledDeltaTime;
            if (hitStopRemaining > 0f) hitStopRemaining -= dt;
            if (slowMoRemaining > 0f) slowMoRemaining -= dt;
            Apply();
        }

        void Apply()
        {
            float s = 1f;
            if (hitStopRemaining > 0f) s = Mathf.Min(s, hitStopScale);
            if (slowMoRemaining > 0f) s = Mathf.Min(s, slowMoScale);
            Time.timeScale = s;
        }
    }
}
