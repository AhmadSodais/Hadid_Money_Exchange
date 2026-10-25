# Prompt: Release a new Windows in-app update

Copy and follow these steps when you want to publish a Hadid Money Exchange update.

---

```
You are releasing a new Windows in-app update for Hadid Money Exchange
(Flutter + desktop_updater 2.0.0-dev.2. Do NOT upgrade that package.)

## Simple In-App Update Steps

**Step 1: Choose the new version**
- Decide new version number (X.Y.Z+N). "N" should be one higher than the last.
- Example: if previous was 1.0.1+2, use 1.0.1+3 (or 1.0.2+3 if you want to bump X.Y.Z).

**Step 2: Update version everywhere**
- Edit these files and make sure version and build number match:
  - `pubspec.yaml` — `version: X.Y.Z+N`
  - `lib/core/constants/app_constants.dart` — `appVersion = 'X.Y.Z'`, `appBuildNumber = N`

**Step 3: Build the release**
```sh
dart run desktop_updater:release windows
```
- You should get: `dist/N/hadid_exchange-X.Y.Z+N-windows`

**Step 4: Archive (hash) the build**
```sh
dart run desktop_updater:archive windows
```
- This creates: `dist/N/X.Y.Z+N-windows/hashes.json`
- IMPORTANT: Always use this folder with hashes.json (not just the build output without it).

**Step 5: Copy to releases**
```powershell
New-Item -ItemType Directory -Force -Path "releases/X.Y.Z+N-windows" | Out-Null
Copy-Item -Path "dist/N/X.Y.Z+N-windows/*" -Destination "releases/X.Y.Z+N-windows/" -Recurse -Force
Test-Path "releases/X.Y.Z+N-windows/hashes.json"   # This must be True
```

**Step 6: Update manifest**
- Open `app-archive.json`
- Add a new item at the TOP of `"items"`, like:
  {
    "version": "X.Y.Z",
    "shortVersion": N,
    "changes": [
      { "type": "feat|fix|chore", "message": "Describe user-facing changes" }
    ],
    "date": "YYYY-MM-DD",
    "mandatory": false,
    "url": "https://raw.githubusercontent.com/AhmadSodais/Hadid_Money_Exchange/main/releases/X.Y.Z+N-windows",
    "platform": "windows"
  }
- Make sure `"url"` matches what you just copied. The folder and URL must match exactly.

**Step 7: Commit and push everything**
```sh
git add releases/X.Y.Z+N-windows app-archive.json pubspec.yaml lib/core/constants/app_constants.dart
git commit -m "Release X.Y.Z+N Windows update"
git push origin main
```
- The commit should include the release package (~many MB), not just a few KB.

**Step 8: Verify on GitHub**
- Check these URLs give HTTP 200 (no 404):
  - https://raw.githubusercontent.com/AhmadSodais/Hadid_Money_Exchange/main/app-archive.json
  - https://raw.githubusercontent.com/AhmadSodais/Hadid_Money_Exchange/main/releases/X.Y.Z+N-windows/hashes.json

**Step 9: Test**
- Install or run an older build (where shortVersion < N)
- In the app: Go to Settings → Check for update → it should offer this new release

---

## Tips and Common Mistakes

- Don’t use `git add .` blindly! Always copy to `releases/` or your update won’t appear on GitHub.
- Don’t let version numbers get out of sync in `pubspec.yaml`, `app_constants.dart`, and `app-archive.json`.
- Never push a manifest with a URL that doesn’t exist yet.
- Don’t upgrade desktop_updater past 2.0.0-dev.2 — newer versions are incompatible with this flow.

---

## If someone just says “release update”:
- Ask for the list of user-facing changes if it wasn’t provided.
- Then follow the steps above (don’t skip copy-to-releases or verification).

```
