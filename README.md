<p align="center"><img src="docs/assets/moveio-mark.svg" width="112" height="112" alt="Moveio logo"></p>

<h1 align="center">Moveio</h1>

<p align="center"><strong>Workout tracking and daily movement for iPhone and Apple Watch.</strong></p>

<p align="center">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-F05138?style=flat-square&amp;logo=swift&amp;logoColor=white">
  <img alt="Xcode" src="https://img.shields.io/badge/Xcode-147EFB?style=flat-square&amp;logo=xcode&amp;logoColor=white">
  <img alt="iOS and watchOS" src="https://img.shields.io/badge/iOS%20%2B%20watchOS-24292F?style=flat-square&amp;logo=apple&amp;logoColor=white">
</p>

<p align="center">
  <a href="#features">Features</a> ·
  <a href="#tech-stack">Tech stack</a> ·
  <a href="#architecture">Architecture</a> ·
  <a href="#getting-started">Getting started</a> ·
  <a href="#roadmap">Roadmap</a>
</p>

Moveio brings workout recording, activity history, and daily wellbeing tools into a native app. Start a session from iPhone, track live metrics on Apple Watch, and see your progress in one place. Workout history, routes, and preferences are stored on the device.

> **Project status.** Moveio is an early prototype. Device signing and the HealthKit, GPS, and widget integrations still need validation on physical hardware.

## Features

| | |
| --- | --- |
| **Workout tracking** | Record on iPhone or hand off to Apple Watch. The Watch uses HealthKit for live heart rate, energy, and distance. iPhone outdoor workouts support route maps, pace, kilometre splits, and GPX export. |
| **Activity and history** | Review sessions, add manual entries, export CSV, and follow activity rings, streaks, quests, and achievements. The Apple Health summary can show steps, sleep, and resting heart rate with permission. |
| **Daily routines** | Follow training plans, set reminders, log water and body measurements, or use breathing exercises, guided stretching, and a Pomodoro timer. Wellbeing timers are also available on Watch. |
| **Friends and widgets** | Exchange friend codes to compare snapshots of activity stats. See your streak on the Home Screen or Lock Screen when the widget's shared storage is configured. |

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

## Architecture

1. **iPhone workouts.** The workout screen tracks time and uses Core Location for outdoor sessions. On completion, Moveio stores a workout record in local history, saves route points in a separate JSON file keyed by the workout ID, and attempts to save the workout to Apple Health when authorized.
2. **Apple Watch workouts.** `HKWorkoutSession` and `HKLiveWorkoutBuilder` provide live metrics. When the workout ends, WatchConnectivity queues the record for iPhone. The iPhone checks the workout UUID before adding it to history, so repeated delivery does not create a duplicate.
3. **Streak widget.** The iPhone app builds a summary from local activity data. With the shared App Group configured, the app writes that summary for WidgetKit to read when building its timeline.
4. **Friend codes.** The app encodes a snapshot of activity stats into a shareable code. The recipient imports the snapshot into their local leaderboard.

## Getting started

Clone the repository and open the Xcode project.

```sh
git clone https://github.com/paalmijs/Moveio.git
cd Moveio
open Moveio.xcodeproj
```

1. Use Xcode with the iOS 27 and watchOS SDKs installed. The project embeds both the Watch app and the widget in the iPhone app.
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
