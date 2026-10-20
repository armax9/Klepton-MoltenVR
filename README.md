# Klepton for macOS + MoltenVR

Play Quest games on your Apple Silicon Mac and stream them to your headset with [MoltenVR](https://github.com/MoltenVR/MoltenVR-Preview).

This fork brings [Klepton](https://github.com/shinyquagsire23/Klepton), through [myMartek’s AVP Play fork](https://github.com/myMartek/Klepton/tree/avp-play), to a native macOS game library with MoltenVR support. Pick your games folder, choose a game, and click **Launch in VR**.

On my **M3 Max + Quest 3**, several tested games deliver a sharper picture and high frame rates at resolutions above their standalone Quest settings. Using the Mac’s GPU makes a real difference. Compatibility is still developing: individual games need their own fixes and tuning.

## What you need

- An Apple Silicon Mac running macOS 26 or later.
- MoltenVR installed and connected to your Quest headset and controllers.
- Your own ARM64 Quest APKs and their OBB / additional game data.
- Homebrew. The installer installs Python 3 through Homebrew if needed.

## Install and play

1. Download **APK-VR-Library-macOS-arm64-v0.1.0.zip** from Releases and extract it.
2. Keep the entire **APK VR Library** folder together. Move it wherever you want.
3. Run **Install.command** once. Then open **APK VR Library.app**.
4. Start MoltenVR and connect your headset.
5. Click **Choose Folder…**, select your games folder, and click **Launch in VR** next to a game.

Keep each APK and its expansion files together, for example:

```text
My Quest Games/
  My Game/
    game.apk
    Android/obb/com.example.game/
      main.123.com.example.game.obb
      additional game files
```

The library scans subfolders automatically and uses folder names as game titles. OBB files and loose game data are linked automatically. Keep the original game folders after adding them. Use **Stop Game** before launching another game.

Saves, extracted files, and shader caches live in `~/Library/Application Support/APK VR Library`. Later launches reuse those caches. The first launch can take longer while shaders compile.

## Tested on macOS with MoltenVR

These games were tested here and reached working gameplay:

- Walkabout Mini Golf
- Batman: Arkham Shadow
- Assassin’s Creed Nexus VR
- Alien: Rogue Incursion
- BONELAB
- Syberia VR — including 4× MSAA
- Vampire: The Masquerade – Justice

Open Brush was also used to validate the native OpenXR connection. Wanderer: The Fragments of Fate reaches gameplay but still needs work. Beat Saber needs further head-motion tuning; Demeo and Into the Radius 2 are still being brought up.

## More games supported upstream

The [original Klepton compatibility list](https://github.com/shinyquagsire23/Klepton#status) reports the following games working on macOS / visionOS:

- Beat Saber 1.6, 1.28, and 1.40
- BONELAB
- SUPERHOT VR
- Resident Evil 4 VR
- Open Brush (OpenXR)
- OpenJK XR (Team Beef)
- Counter-Strike
- Half-Life
- Half-Life 2
- Portal
- Vice City
- Into the Radius
- Red Matter 2
- Vampire: The Masquerade – Justice

This fork carries the existing Klepton compatibility code and the game fixes and profiles from [myMartek’s AVP Play branch](https://github.com/myMartek/Klepton/tree/avp-play), alongside the macOS / MoltenVR additions. Those fixes come from the upstream projects; they were not recreated here.

Games in this upstream list are additional candidates to try. The **Tested on macOS with MoltenVR** list above identifies the games checked with this headset connection. Game versions and individual features can still need tuning.

## What this fork adds

- A native Mac game library with folder scanning, launch / stop controls, and compatibility badges.
- A native Metal / OpenXR connection to MoltenVR for stereo rendering, head and controller tracking, and haptics.
- Correct eye-image routing and field-of-view mapping, plus composition of game panels and overlays.
- Automatic Unity / Unreal engine detection and package-specific game profiles.
- APK manifest decoding, OBB discovery, separate saves, and reusable per-game pipeline caches.
- macOS graphics and media integration through MoltenVK, ANGLE, and VideoToolbox.
- Shared fixes for game lifecycle, Android event delivery, video buffers, OpenXR capabilities, and frame / pose pairing.
- Game-specific rendering fixes, including the Syberia MSAA image-lifetime fix that stops GPU memory growing indefinitely.

The release includes the runtime, graphics libraries, profiles, and launcher. Games run on the Mac; MoltenVR handles the headset connection. No CrossOver or OpenComposite is required. Game content is not included.

## Development

Runtime source is in `source/`; the Mac launcher and profiles are in `launcher/`. See [BUILDING.md](BUILDING.md) for build and packaging details. Source diagnostics remain available to developers but are disabled in the player release; it does not write a continuous game log.

## Credits

[Max Thomas / shinyquagsire23](https://github.com/shinyquagsire23/Klepton) created Klepton. [myMartek](https://github.com/myMartek/Klepton) maintains the AVP Play toolchain and game recipes used as this fork’s starting point. [MoltenVR](https://github.com/MoltenVR/MoltenVR-Preview) provides the Mac-to-headset runtime and streaming connection. This fork adds the macOS launcher and MoltenVR integration described above.

Klepton is MIT licensed. Third-party notices are included with the source and binary release.
