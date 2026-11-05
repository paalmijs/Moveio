# Moveio

**Track your workouts and build a daily movement routine on iPhone and Apple Watch.**

Moveio brings workout history, activity goals, and simple wellbeing tools into one SwiftUI app. It's an early prototype built around local storage and Apple's native frameworks, with no backend or third-party Swift packages.

## What you can do

- **Record workouts.** Start a session on iPhone or launch it on Apple Watch. On iPhone, outdoor sessions are designed to record GPS routes, pace, and kilometre splits, with GPX export. On Apple Watch, the workout screen uses HealthKit for live heart rate, energy, and distance, and sends completed sessions to iPhone via WatchConnectivity.
- **Follow your progress.** Review your history, log workouts manually, export a CSV, and track activity rings, streaks, daily quests, and achievements. The Apple Health summary can show steps, sleep, and resting heart rate when authorized.
- **Build a routine.** Follow training plans, set reminders, log water and body measurements, or take a break with breathing exercises, guided stretching, and a Pomodoro timer. The Watch app also includes the wellbeing timers.
- **Share a snapshot.** Exchange friend codes to compare activity. Each code captures stats at the time it was created. To refresh a friend's stats, import a new code.

## Tech stack

| Area | Technology | Role in Moveio |
| --- | --- | --- |
| Language and build | Swift, Xcode | Native iOS and watchOS targets with Swift 5 language mode |
| Interface and state | SwiftUI, Combine, UIKit | App screens, observable state, and iPhone haptics |
| Charts | Swift Charts | Weight history, water intake, steps, and weekly activity |
| Workouts and health | HealthKit, WatchKit | Workout sessions and live metrics on Watch, Apple Health integration, and Watch app handoff |
| GPS and maps | Core Location, MapKit | iPhone location samples, route display, and data for distance and split calculations |
| Device sync | WatchConnectivity | Queued workout transfer from Watch to iPhone, with immediate messaging when reachable |
| Widgets | WidgetKit, App Groups | Streak timelines and a shared snapshot between the iPhone app and its widget |
| Local storage | Foundation, Codable, UserDefaults, FileManager | Workout records, settings, and JSON route files |
| Reminders and sharing | UserNotifications, SwiftUI ShareLink | Local reminders and sharing GPX, CSV, or friend codes |
| Tests | Swift Testing, XCTest | Unit test targets and UI launch tests |

All dependencies come from Apple SDKs. Moveio runs without a backend, an account system, or API keys.

## Architecture and data flow

1. **iPhone workouts.** The workout screen tracks time and uses Core Location for outdoor sessions. On completion, Moveio stores a workout record in local history, saves route points in a separate JSON file keyed by the workout ID, and attempts to save the workout to Apple Health when authorized.
2. **Apple Watch workouts.** `HKWorkoutSession` and `HKLiveWorkoutBuilder` provide live metrics. When the workout ends, WatchConnectivity queues the record for iPhone. The iPhone checks the workout UUID before adding it to history, so repeated delivery does not create a duplicate.
3. **Streak widget.** The iPhone app builds a summary from local activity data. With the shared App Group configured, the app writes that summary for WidgetKit to read when building its timeline.
4. **Friend codes.** The app encodes a snapshot of activity stats into a shareable code. The recipient imports the snapshot into their local leaderboard.

## Run locally

1. Open `Moveio.xcodeproj` in Xcode with the iOS 27 and watchOS SDKs installed. The project embeds both the Watch app and the widget in the iPhone app.
2. Select the **Moveio** scheme and an iPhone simulator, then press **⌘R**. Use an iOS 27 simulator to evaluate the widget alongside the app.
3. To open the Watch app separately, select **Moveio Watch App Watch App** and a paired Watch simulator. Use paired physical devices to validate workout metrics and Watch-to-iPhone transfers.

| Target | Deployment setting |
| --- | --- |
| iPhone app | iOS 17.6 |
| Apple Watch app | watchOS 10 |
| Widget extension | iOS 27.0 |

These are per-target build settings. The widget has its own OS requirement, and device installation depends on signing the embedded targets as well as the iPhone app.

### Device setup and integration status

For a physical device, enable **Developer Mode** and choose your team in **Signing & Capabilities** for the iPhone, Watch, and widget targets. If you change the bundle identifiers, keep the Watch and widget identifiers under the iPhone identifier and update the Watch target's `WKCompanionAppBundleIdentifier` to match the iPhone app. Personal Team is the project's development baseline. Verify provisioning for each capability with your team.

| Integration | What to verify |
| --- | --- |
| Apple Health | Both apps declare HealthKit. Grant the relevant permissions on the device to read or save workout and health data. Manual workout entries are stored in Moveio's local history. |
| iPhone GPS | Add `NSLocationWhenInUseUsageDescription` before testing GPS workouts. Configure background location separately if testing with the screen locked. |
| Watch workouts | Verify the Workout Processing background mode before relying on workouts continuing in the background. Route recording is currently implemented on iPhone. |
| Streak widget | Configure the same App Group entitlement in the iPhone and widget targets. If you change the group identifier, update `SharedStore.group` in both copies of `MoveioWidgetShared.swift`. |

## Code map

| Path | Responsibility |
| --- | --- |
| [Moveio/](Moveio/) | iPhone app, workouts, routes, history, wellbeing tools, profile, and friend codes |
| [Moveio Watch App Watch App/](Moveio%20Watch%20App%20Watch%20App/) | Watch workout sessions, live metrics, and wellbeing timers |
| [MoveioWidget/](MoveioWidget/) | Home Screen and Lock Screen streak widget |

Workout history and preferences are stored locally. iPhone routes are stored as JSON files, and the widget reads a summary from the App Group container. The iPhone and Watch targets each have a copy of the workout model and connectivity manager. The iPhone and widget targets each have a copy of the widget data model.

## Roadmap

- [ ] Validate signing, permissions, and workout flows on paired devices
- [ ] Record routes on Apple Watch and add complications
- [ ] Improve local persistence and add tests for workout and route calculations
- [ ] Add strength training logs and personal records
- [ ] Explore automatic friend updates

## License

All rights reserved.
