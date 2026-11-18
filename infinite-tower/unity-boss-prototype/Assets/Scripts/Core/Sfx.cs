using System.Collections.Generic;
using UnityEngine;

namespace BossPrototype
{
    public enum SfxKind { WindupNormal, WindupYellow, WindupRed, Impact, PlayerHit, BossHit, Parry, Block, Dodge, PerfectDodge, Roar, Critical, Immobilize }

    /// <summary>Tiny procedural sound set so every telegraph colour has a distinct cue. No audio assets.</summary>
    public static class Sfx
    {
        static readonly Dictionary<SfxKind, AudioClip> clips = new Dictionary<SfxKind, AudioClip>();
        static AudioSource source;

        public static void Bind(AudioSource s) { source = s; }

        public static void Play(SfxKind kind, float volume = 0.6f)
        {
            if (source == null || !Application.isPlaying) return;
            source.PlayOneShot(Get(kind), volume);
        }

        static AudioClip Get(SfxKind kind)
        {
            if (clips.TryGetValue(kind, out AudioClip c) && c != null) return c;
            c = Make(kind);
            clips[kind] = c;
            return c;
        }

        static AudioClip Make(SfxKind kind)
        {
            const int rate = 22050;
            float len;
            switch (kind)
            {
                case SfxKind.Roar: len = 1.6f; break;
                case SfxKind.WindupRed: len = 0.6f; break;
                case SfxKind.Impact: len = 0.45f; break;
                default: len = 0.25f; break;
            }
            int n = Mathf.CeilToInt(len * rate);
            var data = new float[n];
            var rng = new System.Random((int)kind * 7919 + 13);
            float phase = 0f;
            for (int i = 0; i < n; i++)
            {
                float t = (float)i / rate;
                float u = t / len;
                float env = Mathf.Clamp01(t * 60f) * (1f - u);
                float noise = (float)(rng.NextDouble() * 2.0 - 1.0);
                float freq;
                float v;
                switch (kind)
                {
                    case SfxKind.WindupNormal: freq = Mathf.Lerp(220f, 440f, u); phase += freq / rate; v = Mathf.Sin(phase * 2f * Mathf.PI) * 0.5f; break;
                    case SfxKind.WindupYellow: freq = 1320f; phase += freq / rate; v = Mathf.Sin(phase * 2f * Mathf.PI) * 0.45f * (1f - u); break;
                    case SfxKind.WindupRed: freq = Mathf.Lerp(70f, 50f, u); phase += freq / rate; v = (Mathf.Sin(phase * 2f * Mathf.PI) > 0 ? 0.5f : -0.5f) * 0.6f + noise * 0.2f; break;
                    case SfxKind.Impact: v = noise * (1f - u) * (1f - u); break;
                    case SfxKind.PlayerHit: freq = 140f; phase += freq / rate; v = Mathf.Sin(phase * 2f * Mathf.PI) * 0.5f + noise * 0.3f; break;
                    case SfxKind.BossHit: v = noise * 0.6f * (1f - u); break;
                    case SfxKind.Parry: freq = 1760f; phase += freq / rate; v = Mathf.Sin(phase * 2f * Mathf.PI) * 0.6f + Mathf.Sin(phase * 3.01f * Mathf.PI) * 0.3f; break;
                    case SfxKind.Block: freq = 600f; phase += freq / rate; v = Mathf.Sin(phase * 2f * Mathf.PI) * 0.4f + noise * 0.2f; break;
                    case SfxKind.Dodge: v = noise * 0.25f * Mathf.Sin(u * Mathf.PI); break;
                    case SfxKind.PerfectDodge: freq = Mathf.Lerp(880f, 1760f, u); phase += freq / rate; v = Mathf.Sin(phase * 2f * Mathf.PI) * 0.4f; break;
                    case SfxKind.Roar: freq = 60f + 20f * Mathf.Sin(t * 9f); phase += freq / rate; v = Mathf.Sin(phase * 2f * Mathf.PI) * 0.5f + noise * 0.35f; break;
                    case SfxKind.Critical: freq = 90f; phase += freq / rate; v = Mathf.Sin(phase * 2f * Mathf.PI) * 0.7f + noise * 0.4f; break;
                    default: freq = 300f; phase += freq / rate; v = Mathf.Sin(phase * 2f * Mathf.PI) * 0.4f; break;
                }
                data[i] = v * env;
            }
            var clip = AudioClip.Create("sfx_" + kind, n, 1, rate, false);
            clip.SetData(data, 0);
            return clip;
        }
    }
}
