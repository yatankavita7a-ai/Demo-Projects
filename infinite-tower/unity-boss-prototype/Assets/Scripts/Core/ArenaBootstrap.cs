using UnityEngine;

namespace BossPrototype
{
    /// <summary>Pressing Play in any scene without an arena (e.g. an empty scene) spawns one.</summary>
    public static class ArenaBootstrap
    {
        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
        static void EnsureArena()
        {
            if (Object.FindAnyObjectByType<ArenaRoot>() != null) return;
            // Disable cameras/listeners from a default scene so ours is the only one.
            foreach (var cam in Object.FindObjectsByType<Camera>(FindObjectsSortMode.None)) cam.gameObject.SetActive(false);
            foreach (var l in Object.FindObjectsByType<Light>(FindObjectsSortMode.None))
                if (l.type == LightType.Directional) l.enabled = false;
            ArenaFactory.Build(0);
            Debug.Log("[BossPrototype] No arena in scene - spawned the boss arena at runtime.");
        }
    }
}
