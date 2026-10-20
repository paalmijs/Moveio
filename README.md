
# Moveio

A clean, minimal fitness app for **iPhone** and **Apple Watch**, built with SwiftUI. Track workouts, meditate, stay focused, log water and body measurements, follow training plans, and keep a daily streak.

> **Status:** early prototype, built to run on a free Apple ID (no paid Apple Developer Program needed).

## Features

**Workouts**
- Start a workout on iPhone (timer, GPS distance, pace, estimated calories) or hand it off to Apple Watch with one tap
- Apple Watch workouts with live heart rate, calories and distance (HealthKit)
- Route map, kilometre splits, elevation gain and GPX export (Strava, Garmin and others)
- Workouts are saved to Apple Health and synced from Watch to iPhone

**Wellbeing**
- Meditation with a breathing animation, Pomodoro timer and guided stretching (iPhone and Watch)
- Water tracker, body measurements and weight chart
- Apple Health summary: steps, sleep, resting heart rate
- Optional menstrual cycle view (reads Apple Health data or manual logging, stays on device)

**Motivation**
- Apple Fitness style activity rings, daily quests and achievements
- Month calendar, streaks and confetti animations
- Training plans (Start Running, Strength at Home, Mobility)
- Friends leaderboard using share codes (no server)
- Home Screen and Lock Screen streak widget

**Profile**
- Onboarding with optional import from Apple Health (date of birth, sex, height, weight)
- Reminders for workouts, movement and water

## Requirements

- Mac with Xcode 16 or newer
- iPhone on iOS 17 or newer, optional Apple Watch on watchOS 10 or newer
- A free Apple ID is enough (Personal Team)

## Project structure

```
Moveio/                       iPhone app target
  MoveioApp.swift             App entry, tabs, Summary and History
  MoveioTheme.swift           Colors, cards, activity rings
  MoveioFeatures.swift        Tools, water, body, plans, reminders
  MoveioMore.swift            Health card, calendar, achievements, manual log
  MoveioProfiles.swift        Onboarding, profile, menstrual cycle
  MoveioSocial.swift          Animations, daily quests, friends
  MoveioWorkout.swift         Workouts on iPhone, Watch handoff
  MoveioRoutes.swift          Route maps, splits, GPX export
  MoveioWidgetSync.swift      Pushes data to the widget
Moveio Watch App Watch App/   Apple Watch target
  Moveio_Watch_AppApp.swift   App entry, workout manager, workout views
  Watch_Extras.swift          Meditation, Pomodoro, stretching
MoveioWidget/                 Widget extension
  MoveioStreakWidget.swift    Streak widget
Shared (one copy each, added to more than one target)
  WorkoutRecord.swift         Workout model (iPhone + Watch)
  ConnectivityManager.swift   Watch <-> iPhone sync (iPhone + Watch)
  MoveioWidgetShared.swift    Data shared with the widget (iPhone + Widget)
```

## Getting started

1. Clone the repo and open `Moveio.xcodeproj` in Xcode.
2. For every target (Moveio, Moveio Watch App, MoveioWidget): **Signing & Capabilities**, set **Team** to your Apple ID (Personal Team) and use your own bundle identifiers. The Watch bundle ID must start with the iPhone one, and `WKCompanionAppBundleIdentifier` must equal the iPhone bundle ID.
3. Capabilities:
   - iPhone and Watch: **HealthKit**
   - Watch: **Background Modes > Workout processing**
   - iPhone (optional): **Background Modes > Location updates** for GPS with the screen locked
   - iPhone and widget: **App Groups**, same group on both (default `group.palmijs.Moveio`; if you change it, update `SharedStore.group` in `WidgetShared.swift`)
4. Info.plist keys (iPhone): `NSHealthShareUsageDescription`, `NSHealthUpdateUsageDescription`, `NSLocationWhenInUseUsageDescription`. Watch: the two Health keys.
5. Select your iPhone, press Run. Then select the Watch scheme and Run again.
6. On the iPhone, enable **Developer Mode** (Settings > Privacy & Security) and trust your developer profile (Settings > General > VPN & Device Management).

## Known limitations

- With a free Apple ID, apps expire after **7 days** and must be reinstalled from Xcode.
- Friends use share codes, so stats only update when a friend sends a new code. Automatic sync needs a backend.
- Routes are recorded for workouts started on iPhone only. Watch workouts have no route yet.
- iPhone workouts estimate calories from your weight and the activity (no heart rate).
- Menstrual cycle predictions are approximate, not medical advice and not for contraception.
- Some features may be limited by free account capabilities (for example App Groups for the widget).

## Roadmap

- [ ] Fix build and runtime issues on real devices
- [ ] Reorganise files into folders and add tests
- [ ] Move storage to SwiftData
- [ ] Watch routes and complications
- [ ] Accounts and automatic friend sync with a free backend
- [ ] Strength training log and personal records

## License

No license yet. All rights reserved until one is added.
