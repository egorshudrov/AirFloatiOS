# AirFloat iOS Release Handoff

This repository contains the iOS source needed to build AirFloat.

## Requirements

- Xcode 26.4.x or newer compatible Xcode
- CocoaPods
- Apple Developer Program access
- App Store Connect access
- A valid signing team, certificate, provisioning profile, and App Store app record

## Setup

```bash
cd AirFloat
pod install
open AirFloat.xcworkspace
```

Open the workspace, not the project file.

## Build

```bash
cd AirFloat
xcodebuild -workspace AirFloat.xcworkspace -scheme AirFloat -destination 'generic/platform=iOS' build
```

If building from a clean machine, Xcode may require the publisher to select their Apple Team before device/archive builds succeed.

## App Store Archive

In Xcode:

1. Open `AirFloat/AirFloat.xcworkspace`.
2. Select scheme `AirFloat`.
3. Select destination `Any iOS Device`.
4. Open target `AirFloat` signing settings.
5. Set the publisher's Team.
6. Confirm or change the bundle identifier.
7. Use `Product > Archive`.
8. Upload through Organizer to App Store Connect.

## Current Bundle Metadata

- Bundle ID: `com.airfloat.AirFloat`
- Version: `1.0`
- Build: `1`
- Minimum iOS deployment target: `26.2`

If the publisher uses a different Apple Developer account or company, they may need a different bundle identifier before the first App Store release.

## Publishing Notes

The repository intentionally does not include:

- Apple certificates
- provisioning profiles
- `.ipa` files
- `.xcarchive` files
- `Pods/`
- local Xcode user state

Those are generated or owned by the publisher.

## Known Handoff Boundaries

- Source, project/workspace files, Podfile, Podfile.lock, MediaPipe model asset, and app assets should be committed.
- App Store publication still requires the publisher's Apple Developer/App Store Connect setup.
- The repository includes a generated 1024x1024 app icon derived from current AirFloat artwork. The publisher may replace it with final brand artwork before production submission.
