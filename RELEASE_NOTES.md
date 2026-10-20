# v0.1.0 — Quest games on macOS with MoltenVR

The first player release of Klepton for macOS + MoltenVR.

- Browse your APK collection and launch games from a native Mac app.
- Includes the ARM64 runtime, MoltenVK, ANGLE, and game profiles.
- Automatic APK / OBB setup, separate saves, and reusable shader caches.
- Native stereo rendering, head / controller tracking, haptics, and game overlays through MoltenVR.
- Includes shared runtime improvements and game-specific rendering fixes, including Syberia’s 4× MSAA memory fix.
- Diagnostic captures and tracing are disabled; no continuous game log.

Tested here: Walkabout Mini Golf, Batman: Arkham Shadow, Assassin’s Creed Nexus VR, Alien: Rogue Incursion, BONELAB, Syberia VR, and Vampire: The Masquerade – Justice.

The release also carries existing Klepton compatibility fixes and the game profiles from myMartek’s AVP Play fork. Additional upstream-supported games include SUPERHOT VR, Resident Evil 4 VR, OpenJK XR, Counter-Strike, Half-Life, Half-Life 2, Portal, Vice City, Into the Radius, and Red Matter 2. See the README for the full upstream list and the separate Mac + MoltenVR test results.

On an M3 Max with Quest 3, several tested titles offer a sharper picture and high frame rates compared with their standalone Quest settings. Individual games still need fixes and tuning.

Download the ZIP, extract it, run Install.command once, connect MoltenVR, and open APK VR Library.app. Requires Apple Silicon, macOS 26+, MoltenVR, Homebrew Python 3, and your own game files.
