# AGENT Instructions for mushroomHunter

## Always Build/Install/Run After Code Changes
- After **any code change**, you must build, install, and launch the app on my connected iPhone unless I explicitly say “skip build”.
- If the build or install fails, stop and report the error with the key lines.

### Current device and bundle
- Device (CoreDevice UUID): `664E44A2-57C7-5319-B871-EB1D380FBC1B` (Ken’s iPhone)
- Bundle ID: `com.kenyu.mushroomHunter`
- Project: `/Users/ken/Desktop/mushroomHunter/mushroomHunter.xcodeproj`
- Scheme: `mushroomHunter`

### Required commands (in order)
```bash
xcodebuild -project /Users/ken/Desktop/mushroomHunter/mushroomHunter.xcodeproj \
  -scheme mushroomHunter -configuration Debug \
  -destination "id=00008150-00021D26028A401C" build

# find .app (DerivedData can change)
APP_PATH=$(ls -d /Users/ken/Library/Developer/Xcode/DerivedData/mushroomHunter-*/Build/Products/Debug-iphoneos/mushroomHunter.app | head -n 1)

xcrun devicectl device install app --device 664E44A2-57C7-5319-B871-EB1D380FBC1B "$APP_PATH"
xcrun devicectl device process launch --device 664E44A2-57C7-5319-B871-EB1D380FBC1B com.kenyu.mushroomHunter
```

## General Expectations
- Prefer `rg` for searches if available; otherwise fall back to `grep`.
- Keep changes minimal and focused; don’t reformat unrelated code.
- If behavior changes, mention what to test in the app.
