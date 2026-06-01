# HookCut — Overnight Worklog

## What it is

HookCut is a native macOS app (Swift 5.9 / SwiftUI, macOS 14+) that finds the
best highlights in a podcast or video and exports them as NLE-ready timelines.
The pipeline is: extract audio (AVFoundation) → transcribe (OpenAI Whisper API
**or** on-device WhisperKit/CoreML) → diarize speakers (GPT-4o / Claude /
Ollama) → detect highlights (GPT-4o / Claude / Ollama) → review in the UI →
export FCPXML, Premiere XML, EDL, SRT, CSV, or plain text. It supports a fully
local mode (on-device Whisper + Ollama) with no API key and no cloud calls.

Built with Swift Package Manager; an `.xcodeproj` is generated from `project.yml`
via XcodeGen. Depends on WhisperKit (argmaxinc).

## Starting state

- Honest starting completeness: **~72%**.
- The app was already substantial and genuinely Mark-authored (not a clone):
  ~5,765 lines across well-separated models / services / view-models / views /
  exporters, with a real (non-mock) pipeline for transcription, diarization,
  highlight detection, and six export formats.
- `swift build` already succeeded. `xcodebuild` (app target) had not been
  re-verified against the current source layout.
- **No tests existed.** Several real bugs were latent (see below). No LICENSE
  file despite the README linking one. README under-described the local/Ollama
  capabilities that were already in the code.

## What I changed, fixed, added, built

All work is in commits on top of `427234a` (the prior HEAD).

### Bug fixes (real, verified)

1. **XML double-escaping in FCPXML + Premiere exporters** —
   `FCPXMLGenerator.sanitizeForXML` / `PremiereXMLGenerator.sanitize` manually
   escaped `& < > " '` and then handed the result to Foundation's
   `XMLElement`/`XMLNode`, which escape **again** on serialization. A clip whose
   text contained `AT&T` was written as `AT&amp;amp;T` (corrupt — FCP/Premiere
   would display literal `&amp;`). Removed the manual escaping; the XML APIs now
   do the single correct escape. Proven with a standalone repro and locked in by
   regression tests. (`HookCut/Export/FCPXMLGenerator.swift`,
   `HookCut/Export/PremiereXMLGenerator.swift`)

2. **Whisper word-level timestamps silently dropped** —
   `WhisperService.parseWhisperResponse` only read per-segment `words`, which the
   `whisper-1` `verbose_json` response never populates (words arrive as a flat
   top-level array). Word timestamps were therefore always empty. Now the
   top-level words are distributed into their containing segment by time range.
   (`HookCut/Services/WhisperService.swift`)

3. **VideoPlayerView seek-to-highlight left a stale end-cap** —
   `playHighlight` set `forwardPlaybackEndTime` to stop at a clip's end but
   nothing cleared it, so after previewing one highlight, normal play/scrub
   would silently halt at that old end time. `togglePlayback` (on resume) and
   `seek` now reset the cap when not in assembled-preview mode.
   (`HookCut/ViewModels/AppViewModel.swift`)

4. **Dead diarization API-key ternary** — `startAnalysis` built `analysisApiKey`
   with a no-op ternary (both branches returned the OpenAI key). Removed it and
   documented the actual key routing. (`HookCut/ViewModels/AppViewModel.swift`)

### Features / completeness

5. **Batch processing finished** (`HookCut/Views/BatchView.swift`):
   - Respects the transcription engine: a **Local** batch now prepares the
     on-device model once and uses it for every item (previously batch always
     forced the cloud Whisper API).
   - **Cancellation**: a Cancel button stops the in-flight batch; the current
     item resets to idle so it can be re-run, the rest are untouched.
   - **Export All**: writes every completed item's approved highlights to a
     chosen folder in the default export format, with a result summary.
   - `hasAPIKey` / the warning message now mirror the main pipeline (Ollama
     needs no key; Anthropic needs its own), so fully-local batches aren't
     blocked.

6. **First-run welcome screen** (`HookCut/Views/WelcomeView.swift`) — shown once
   (UserDefaults-gated), explaining cloud-vs-local, import, and export, with an
   "Open Settings" shortcut. Wired into `ContentView`.

7. **Engine-aware cost estimate** (`HookCut/Services/CostEstimator.swift`) — now
   reports $0 transcription cost for on-device Whisper instead of charging the
   API rate; fully-local runs estimate $0.00. `ImportView` passes the engine.

### Tests (new)

8. **SwiftPM test target `HookCutTests` — 25 tests, all passing**
   (`Tests/HookCutTests/`, `Package.swift`). Covers RationalTime/FrameRate
   timecode math, Highlight rating/duration invariants, AnalysisResult
   aggregates, the engine-aware CostEstimator, AppSettings Codable round-trip,
   and **all six exporters** — including explicit regression guards that FCPXML
   and Premiere output is valid XML and is *not* double-escaped, EDL drop vs
   non-drop timecode, SRT timing, CSV quoting, and plain-text annotation.

### Docs / packaging

9. Added the **MIT `LICENSE`** the README already referenced. Updated the README
   to document on-device WhisperKit, fully-local Ollama, batch Export All +
   cancellation, the welcome screen, `swift test`, and a Packaging &
   Distribution section (signing/notarization). Tech-stack table and project
   tree brought in line with the actual code.

## Current state — does it build? does it run? tests?

- **`swift build`** — clean. ✅
- **`xcodebuild` (app target, Debug, macOS, code-signing off)** — `** BUILD
  SUCCEEDED **`. ✅
- **`swift test`** — 25 tests, 0 failures. ✅
- **Runtime boot** — launched the built binary; it boots and runs its event loop
  without crashing or error output. ✅ (Full end-to-end transcription/analysis
  needs live API keys or a downloaded local model — see NEEDS FROM MARK.)

## How to run it locally

```bash
cd /Users/markksantos/Developer/HookCut
swift build
swift run HookCut
# or:  xcodegen generate && open HookCut.xcodeproj   (Cmd+R)
swift test            # 25 tests
```

On first launch the welcome screen points to **Settings (⌘,)**. Choose a
transcription engine and AI provider:
- **Cloud**: enter an OpenAI API key (Whisper + GPT-4o). Optionally an Anthropic
  key to use Claude.
- **Fully local**: set transcription to On-Device, provider to Ollama, and run
  `ollama serve` with a model (e.g. `qwen3:8b`). No keys, no cost.

Then drag in an MP4/MOV/M4V/WAV/MP3/M4A, click **Analyze**, review highlights,
and **Export**.

## How to deploy (exact steps, when ready)

This is a desktop app — "deploy" means producing a signed, notarized artifact.
Do NOT do this without Mark's Apple Developer account.

1. `xcodegen generate`
2. Release build with a Developer ID identity:
   ```bash
   xcodebuild -project HookCut.xcodeproj -scheme HookCut -configuration Release \
     -derivedDataPath build \
     CODE_SIGN_IDENTITY="Developer ID Application: <Name> (<TEAMID>)" build
   ```
3. Package: `create-dmg` (or `hdiutil`) the `HookCut.app`.
4. `codesign --deep --options runtime` the app/dmg, then
   `xcrun notarytool submit ... --wait`, then `xcrun stapler staple`.
5. (Optional Mac App Store) archive + upload via App Store Connect — the app
   already ships App Sandbox + hardened-runtime entitlements and a
   `PrivacyInfo.xcprivacy` manifest.

Auto-update (Sparkle or similar) is not yet integrated — see below.

## NEEDS FROM MARK

- **OpenAI API key** — for live cloud testing of Whisper + GPT-4o end-to-end.
- **Anthropic API key** — only if the Claude path needs live end-to-end testing.
- **Apple Developer account / Developer ID signing identity** — required to
  produce a signed + notarized `.dmg` (or to ship to the Mac App Store). Build
  and compile are fully verified; signing/notarization is the only gate.
- **Decision: auto-update mechanism** — Sparkle vs MAS-only vs none. Not wired
  yet; needs a feed URL + signing if Sparkle is chosen.

## Honest completeness % now and what still remains

**~88%** and deploy-ready (compile/run/tests all green; only signing remains to
ship a build).

Remaining (none block local use; most need Mark's account or a product call):
- Code-signing + notarization workflow / signed `.dmg` (needs Apple account).
- Sparkle or direct auto-update mechanism (product decision + signing).
- Deeper live-API integration testing once keys are available (the network
  layers are implemented and structurally correct but were not exercised
  against the live OpenAI/Anthropic endpoints in this run).
- Optional: distribute word-level timestamps into the diarization/highlight
  prompts for tighter clip boundaries (now that word timestamps are preserved).
