# Moveio working context

Reviewed 2026-10-29. This is a source/configuration review, not confirmation of a successful build or device run.

## User constraint

The owner does **not** have an Apple Developer Program subscription. Treat free Apple ID / Personal Team development as the baseline. Do not introduce paid-program services as required dependencies. Verify capability availability and actual provisioning before promising real-device support. Preserve local/manual functionality when integrations are unavailable. App Store/TestFlight distribution is outside this baseline.

Apple account reference: https://developer.apple.com/help/account/basics/about-your-developer-account
Capability references: https://developer.apple.com/help/account/reference/supported-capabilities-ios and https://developer.apple.com/help/account/reference/supported-capabilities-watchos

## Architecture and data

- Native SwiftUI prototype, about 4,000 Swift source lines; no external Swift packages or backend configured.
- iPhone entry: `Moveio/MoveioApp.swift`. Onboarding precedes five tabs: Summary, History, Tools, Friends, Profile. Locale is explicitly en_US; a few Latvian strings remain.
- `ConnectivityManager.shared` owns workout records, persists Codable JSON in UserDefaults (`records`), normalizes legacy Latvian activity names, and receives Watch records with UUID deduplication. Watch queues transferUserInfo and optionally sendMessage. Sync is Watch to phone; deletions do not propagate back.
- `WorkoutRecord` contains UUID, activity string, date, duration, calories, average HR, distance. Separate identical copies exist in phone and Watch directories; these are not a single shared source file as README implies. ConnectivityManager and widget shared models also have duplicate copies; keep copies consistent when editing.
- `MoveioWorkout.swift`: phone workout state machine, wall-clock timer with pause/resume, CoreLocation, MET/weight calorie estimate, HealthKit save and Watch launch. Phone HR is zero. Workout dates are recorded at completion.
- `MoveioRoutes.swift`: one JSON route file per workout under Documents/routes; MapKit display, splits/elevation calculations and GPX export.
- `MoveioFeatures.swift`: meditation, Pomodoro, stretching, water, body entries, fixed training plans, local reminders. These use independent ObservableObject stores and UserDefaults/AppStorage, not SwiftData.
- `MoveioMore.swift`: Apple Health summary queries, calendar, achievements, CSV, manual workout entry. Manual/wellbeing logs go to local history without the phone workout HealthKit saving path.
- `MoveioProfiles.swift`: profile/onboarding, optional Health import, cycle data and approximate predictions. Profile keys start with p_; cycle manual dates are local.
- `MoveioSocial.swift`: animations, streak/weekly calculations, quests and friends. Friend codes are base64 JSON snapshots, not accounts or automatic synchronization.
- `MoveioTheme.swift`: adaptive colors, high contrast, cards, logo and rings.
- Watch entry `Moveio_Watch_AppApp.swift`: HKWorkoutSession/HKLiveWorkoutBuilder, live HR/energy/distance, pause/end/summary; Watch_Extras contains wellbeing timers. No Watch GPS route collection.
- Widget reads a WidgetSnapshot from group.palmijs.Moveio. WidgetSync pushes on app appearance, record count changes and foreground entry.

## Configuration findings to resolve before relying on device behavior

- Phone deployment target is iOS 17.6, Watch watchOS 10, widget iOS 27.0; tests use 26.5. Phone also advertises macOS/visionOS despite UIKit-specific code. README requirements are not authoritative.
- Phone Info.plist declares remote-notification background mode, but not location. No NSLocationWhenInUseUsageDescription was found in plist or build settings, despite GPS requesting it. Watch workout-processing background mode was not found in build settings or its entitlement file.
- Both apps declare HealthKit. Widget storage uses an App Group, but no App Groups entitlement is configured. Free-team capability/provisioning must be checked; importing a framework is not proof that it works on a signed device.
- Phone embeds Watch and widget, so their configuration can affect the phone build/install.
- Tests are generated placeholders/launch tests; meaningful domain coverage is absent.
- GPS distance rejects speeds above 12 m/s even for cycling; rejected segments still enter the route. RouteStats recomputes all segments without the same rejection and includes pause gaps. Live distance, split calculations and exported routes can disagree.
- Many HealthKit and persistence errors are silently ignored. Watch start requests authorization asynchronously then immediately attempts to start. Health authorization callback success must not be interpreted as permission to read every type.
- README describes intent; do not assume every listed feature is verified.

## Local environment and existing changes

- Actual checkout path: /Users/apple/Projects/Moveio (case-insensitive alias moveio).
- Xcode is installed at /Applications/Xcode.app, version 27.1 (27A9275). The globally selected developer directory is CommandLineTools, so plain xcodebuild/simctl fails. Use DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer for task commands instead of changing the user's global selection.
- Before this review, Git already had modifications to MoveioApp.swift, MoveioProfiles.swift, MoveioSocial.swift, MoveioTheme.swift, user scheme management, and an untracked shared widget scheme. Preserve these; do not revert them or attribute them to this review.
- This review adds only this context document. No signing, source behavior, bundle IDs or project settings were changed.
