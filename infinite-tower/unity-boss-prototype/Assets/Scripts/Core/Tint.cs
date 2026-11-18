using UnityEngine;

namespace BossPrototype
{
    /// <summary>Applies a lit colour at runtime, so scenes saved by the editor builder need no material assets.</summary>
    public class Tint : MonoBehaviour
    {
        public Color color = Color.gray;

        public static Tint Add(GameObject go, Color c)
        {
            var t = go.GetComponent<Tint>();
            if (t == null) t = go.AddComponent<Tint>();
            t.color = c;
            t.Apply();
            return t;
        }

        void Awake() { Apply(); }

        public void Apply()
        {
            if (!Application.isPlaying) return;
            var r = GetComponent<Renderer>();
            if (r != null) r.sharedMaterial = MaterialFactory.Lit(color);
        }
    }
}
