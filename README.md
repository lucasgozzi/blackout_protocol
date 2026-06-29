# Blackout Protocol

Cooperative strategy game built with Flutter + Flame, based on Zombicide mechanics.

## Setup

```bash
# 1. Install Flutter (if not installed)
brew install --cask flutter

# 2. Install dependencies
flutter pub get

# 3. Generate code (freezed + json_serializable)
dart run build_runner build --delete-conflicting-outputs

# 4. Run
flutter run
```

## Dev Launcher

In **debug builds**, the app opens the **Dev Launcher** instead of the normal flow.
Pick any preset to jump directly into a specific game state:

| Preset | Description |
|--------|-------------|
| Mission Start | Round 1, alert 0, clean board |
| Mid Mission | Round 5, alert 5, scattered enemies |
| High Alert | Round 9, alert 9, crowded board |
| Boss Encounter | SENTINEL-9 active, low resources |
| Near Victory | Objectives done, need to extract |
| Near Defeat | Critical players, max alert |

To add a new preset:
1. Add entry to `GameContextPreset` enum in [lib/core/engine/game_context.dart](lib/core/engine/game_context.dart)
2. Add metadata to `_presetMeta` in [lib/features/dev_launcher/dev_launcher_screen.dart](lib/features/dev_launcher/dev_launcher_screen.dart)
3. Add `GameContext(...)` to `GamePresets._presets`

## Adding a New Campaign

1. Create folder `assets/data/campaigns/campaign_XX/`
2. Add `manifest.json` (copy from campaign_01 as template)
3. Add one JSON per mission (copy `c01_m01_fuel_depot.json` as template)
4. Add the asset paths to `pubspec.yaml` under `flutter.assets`
5. No code changes required — campaigns are pure data

## Project Structure

```
lib/
├── core/
│   ├── models/       # Data models (Campaign, Mission, Enemy, Player, GameState)
│   ├── rules/        # Game rules (combat, movement, alert level, spawning)
│   └── engine/       # Game loop, GameContext (debug), session management
├── data/             # Data loaders (JSON → models)
├── features/
│   ├── campaign_select/
│   ├── game_board/   # Flame component tree
│   ├── ranking/
│   ├── store/
│   └── dev_launcher/ # Debug only
└── services/
    ├── backend/      # Firebase (ranking, save state)
    └── iap/          # In-app purchases
```
