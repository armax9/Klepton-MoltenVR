# Building the macOS fork

The player ZIP targets macOS 26+ because its bundled SDL3 build targets macOS 26. The runtime itself currently targets macOS 15. These instructions are for building the runtime or changing the launcher.

## Runtime

Use Xcode and its command-line tools on an Apple Silicon Mac:

```sh
brew install pkg-config sdl3 vulkan-headers
cd source
make -f Makefile.moltenvr -j6 CC='xcrun clang' MVK_INC=-I/opt/homebrew/include build/openbrush-moltenvr-shared
```

The native OpenXR headers, Fossilize, and SMOL-V source needed by this target are included. MoltenVR itself is installed separately and loaded from its normal Application Support location.

## Launcher

```sh
bash scripts/build_launcher.sh
python3 -m unittest discover -s launcher -p 'test_*.py'
```

Keep `library.py`, `apk_manifest.py`, `engine_profiles.py`, `runtime_policy.py`, `profiles.json`, `shared-runtime.json`, and `recipes/` next to the app. The runtime directory is `runtime/` next to those files. Player data is stored separately in Application Support.

## Graphics components

The player release includes the matching prebuilt graphics libraries. Versions and SHA-256 fingerprints are recorded in `shared-runtime.json`.

- ANGLE: commit `25e721127e1c6c4c6fa0182b5c234b2c88971175`, with `source/angle-patches/klepton.patch`. Build the macOS ARM64 Metal backend with `is_debug=false`, `angle_enable_vulkan=false`, and `angle_enable_swiftshader=false`.
- Shared MoltenVK: commit `5189f8de86ec365860f63bf1da736815cfaea5cd` from KhronosGroup/MoltenVK, built for macOS.
- Syberia uses its separately fingerprinted MoltenVK 1.4.2 companion. `scripts/patch_mvk_image_lifetime.py SOURCE OUTPUT` reproduces the binary patch against the exact input hash; the runtime-side lifetime handling is in the included runtime source. The workaround follows the credited Ryujinx MoltenVK image-view patch.
- SDL3 is bundled alongside the runtime. Its install name is changed to `@executable_path/../lib/libSDL3.0.dylib` in the release copy.

After replacing a component, update its fingerprint and re-sign changed Mach-O files. The launcher rejects mismatched component files.

## Diagnostics

The player release disables diagnostic environment flags and sends game output to `/dev/null`. For a deliberate diagnostic run, start the launcher with `APKVR_DEBUG=1`; it writes one `latest.log` per game in Application Support. Source-level regression tests remain in `source/tests/`.

No APKs, OBBs, translated game libraries, saves, or shader caches belong in a release.
