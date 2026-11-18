using UnityEngine;

namespace BossPrototype
{
    /// <summary>Owns the arena: hazards parent, boss swapping (1-4) and restart (R).</summary>
    public class ArenaRoot : MonoBehaviour
    {
        public static ArenaRoot Instance { get; private set; }
        public const float ArenaRadius = 32f;
        public static readonly Vector3 PlayerSpawn = new Vector3(0f, 0.05f, -12f);
        public static readonly Vector3 BossSpawn = new Vector3(0f, 0f, 10f);

        public Transform Hazards;
        public int currentBoss;

        void OnEnable() { Instance = this; }
        void OnDisable() { if (Instance == this) Instance = null; }

        void Awake()
        {
            if (Hazards == null)
            {
                var h = transform.Find("Hazards");
                Hazards = h != null ? h : new GameObject("Hazards").transform;
                Hazards.SetParent(transform, false);
            }
            var src = GetComponent<AudioSource>();
            if (src == null) src = gameObject.AddComponent<AudioSource>();
            src.playOnAwake = false;
            src.spatialBlend = 0f;
            Sfx.Bind(src);
            var boss = BossController.Instance;
            if (boss != null) currentBoss = boss.bossIndex;
        }

        void Update()
        {
            var player = PlayerController.Instance;
            var boss = BossController.Instance;
            for (int i = 0; i < BossLibrary.Count; i++)
                if (GameInput.KeyDown(KeyCode.Alpha1 + i) || GameInput.KeyDown(KeyCode.Keypad1 + i)) { ResetArena(i); return; }
            if (GameInput.KeyDown(KeyCode.R) && ((player != null && !player.IsAlive) || (boss != null && !boss.IsAlive) || GameInput.Key(KeyCode.LeftControl)))
                ResetArena(currentBoss);
        }

        /// <summary>Despawn hazards, rebuild the boss and reset the player.</summary>
        public void ResetArena(int bossIndex)
        {
            currentBoss = Mathf.Clamp(bossIndex, 0, BossLibrary.Count - 1);
            GameFeel.ResetTime();
            for (int i = Hazards.childCount - 1; i >= 0; i--) Destroy(Hazards.GetChild(i).gameObject);
            FirePool.ActiveCount = 0;

            var boss = BossController.Instance;
            if (boss != null)
            {
                boss.transform.SetPositionAndRotation(BossSpawn, Quaternion.LookRotation(Vector3.back));
                boss.Setup(currentBoss);
            }
            else ArenaFactory.CreateBoss(transform, currentBoss);

            var player = PlayerController.Instance;
            if (player != null)
            {
                player.ResetPlayer(PlayerSpawn, Quaternion.identity);
                if (OrbitCamera.Instance != null) OrbitCamera.Instance.SnapBehind(player.transform);
            }
            var def = BossLibrary.Create(currentBoss);
            HudOverlay.Flash(def.name + "  -  " + def.epithet, def.accentColor, 2.5f);
        }
    }
}
