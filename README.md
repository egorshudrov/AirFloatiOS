# AirFloat iOS

AirFloat iOS is a native SwiftUI fitness app for live camera-based exercise tracking. It uses MediaPipe pose landmarks, exercise-specific movement logic, and local workout history to deliver a complete Today -> Train -> Live -> Progress loop.

## Highlights

- Native SwiftUI app
- Live camera preview with MediaPipe pose tracking
- Skeleton overlay and large rep counter
- Exercise support for Barbell Press, Dumbbell Press, Squat, Push-up, and Sit-up
- Today, Train, Live, and Progress surfaces
- Local workout session persistence
- Attempt-level progress review
- CocoaPods-based MediaPipe integration

## Tech Stack

- Swift
- SwiftUI
- AVFoundation
- MediaPipe Tasks Vision
- CocoaPods
- iOS deployment target `26.2`

## Project Structure

```text
AirFloat/
  AirFloat.xcworkspace
  AirFloat.xcodeproj
  Podfile
  Podfile.lock
  AirFloat/
    App/          App entry and root navigation
    Core/         Session, schedule, progress, exercise, and Today models
    Features/     Today, Train, Live, Progress, First Launch UI
    Resources/    MediaPipe model asset
    Shared/       Shared UI primitives
```

## Setup

Requirements:

- macOS
- Xcode 26.4.x or compatible newer Xcode
- CocoaPods
- Apple Developer account for device builds or App Store release

Install dependencies:

```bash
cd AirFloat
pod install
```

Open the app:

```bash
open AirFloat.xcworkspace
```

Always open the workspace, not the project file.

## Build

From Xcode:

- Scheme: `AirFloat`
- Destination: physical iPhone or generic iOS device

From terminal:

```bash
cd AirFloat
xcodebuild -workspace AirFloat.xcworkspace -scheme AirFloat -destination 'generic/platform=iOS' build
```

If a clean machine does not have signing configured, Xcode will ask the publisher to select a development team and provisioning profile.

## Release Handoff

Publishing notes are documented in [RELEASE_HANDOFF.md](RELEASE_HANDOFF.md).

The repository does not include Apple certificates, provisioning profiles, `.ipa` files, `.xcarchive` files, `Pods/`, or local Xcode user state.

