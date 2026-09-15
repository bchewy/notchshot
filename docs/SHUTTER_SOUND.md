# Capture shutters

NotchShot offers three locally bundled Fujifilm shutter recordings in Settings: X-T3, X100S, and FinePix F11. X-T3 remains the default. The selected sound is saved across launches; clicking a camera tile selects and auditions it, while restoring a saved selection stays silent. It plays once when a capture's first preview is ready; later accessibility updates do not replay it. The existing capture-sound preference controls automatic playback. Settings shows three generated lens-facing camera illustrations. Clicking a tile selects and previews that sound without taking a screenshot or changing the mute preference; clicking it again replays it.

## X-T3 source

- Recording: [DSLR shutter sound (Fujifilm x-t3)](https://freesound.org/people/boredomfounder/sounds/815501/) by boredomfounder, July 9, 2025.
- Camera is identified by the uploader as Fujifilm X-T3, recorded on an iPhone 12.
- License: [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/).
- Input: the official public [HQ preview](https://cdn.freesound.org/previews/815/815501_10675217-hq.mp3); original-length MP3 preserved in local work files, not included as another app resource.
- Freesound [outbound terms](https://freesound.org/help/tos_web/) associate published sounds with their selected license. No original-download login was bypassed.

## X-T3 processing

A single shutter was selected from **7.475–7.815 seconds** of the decoded recording. 90 Hz one-pole high-pass; 1.5 ms leading/35 ms trailing fades; peak normalized to -5 dBFS. No generated layers or extra beeps were added.

Final asset: `Sources/NotchShot/Resources/CaptureShutter.wav` — **340 ms, mono, 48 kHz, 16-bit PCM**. Peak **-5.00 dBFS**, RMS **-29.03 dBFS**, first/last samples zero. Runtime playback uses a moderate additional volume reduction.

- Download SHA-256: `fcf182770efbbfc8fafa05bf8c7c27982882b0b49bc4ddc594646406199a83f1`
- Final WAV SHA-256: `d9b921d319670ef1cbbbba80a7a010c4dc98379a4f2a5218dcc7beef2e47bc4c`

The WAV is bundled directly in the signed app's `Contents/Resources`; SwiftPM also processes it for `swift run` and tests. No network request is made to play it. See `THIRD_PARTY_NOTICES.md` for redistribution attribution.

## Additional recordings

### Fuji X100S.wav

- Recording by **hmilleo**: [Fuji X100S.wav](https://freesound.org/people/hmilleo/sounds/409096/). The uploader identifies the camera.
- License: [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/).
- Input: [official public HQ preview](https://cdn.freesound.org/previews/409/409096_3482955-hq.mp3).
- Changes: one shutter excerpt from **1.57–2.09 seconds**; 90 Hz one-pole high-pass; 1.5 ms leading/35 ms trailing fades; peak -5 dBFS.
- Bundled asset: `Sources/NotchShot/Resources/CaptureShutterX100S.wav` — 520 ms, mono 48 kHz, 16-bit PCM. Peak -5.00 dBFS; RMS -34.96 dBFS; endpoint samples zero.
- Input SHA-256: `fd886b47f21fe2e7c36efe275815c5a9f87321705686283b044e8024618ec272`.
- Asset SHA-256: `d1de493eeeca3c0c1c359a5ac8d69158cb12524062caba0bf61f963873d70ba2`.

### Fuji-Finepix-F11-Shoot.flac

- Recording by **Erdie**: [Fuji-Finepix-F11-Shoot.flac](https://freesound.org/people/Erdie/sounds/50450/). The uploader identifies the camera.
- License: [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
- Input: [official public HQ preview](https://cdn.freesound.org/previews/50/50450_118241-hq.mp3).
- Changes: one shutter excerpt from **0.89–1.48 seconds**; 90 Hz one-pole high-pass; 1.5 ms leading/35 ms trailing fades; peak -5 dBFS.
- Bundled asset: `Sources/NotchShot/Resources/CaptureShutterFinePixF11.wav` — 590 ms, mono 48 kHz, 16-bit PCM. Peak -5.00 dBFS; RMS -28.43 dBFS; endpoint samples zero.
- Input SHA-256: `df5e78317bb3423da47e786d23ca7edc3f8348c0e5b8fd46461ba8ac93aae170`.
- Asset SHA-256: `ea5820ae58ff5ea4227de9b743a1e36cabdd32d80e7c7771e43ecfbc313ae7d3`.

Playback retains one active voice, stops the previous voice when switching, and restarts rather than stacking on repeat tile preview/capture. Automatic playback respects Capture sound; explicit tile previews also work while muted. The app uses no network access for audio.

The GW670 II recording by kulmajaba was also researched (Freesound 588608, CC0), but its three-minute mix of film loading, winding and shutter sounds was not included because a specific shutter excerpt could not be confidently identified.
