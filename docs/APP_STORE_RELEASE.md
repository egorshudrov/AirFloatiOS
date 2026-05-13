# iOS App Store Release Notes

## Current Bundle Metadata

- Bundle ID: `com.airfloat.AirFloat`
- Version: `1.0`
- Build: `1`
- Minimum iOS deployment target: `26.2`

## Setup

```bash
cd AirFloat
pod install
open AirFloat.xcworkspace
```

## Archive

In Xcode:

1. Open `AirFloat/AirFloat.xcworkspace`.
2. Select scheme `AirFloat`.
3. Select destination `Any iOS Device`.
4. Set the publisher's Apple Team in target signing settings.
5. Confirm the bundle identifier.
6. Use `Product > Archive`.
7. Upload from Organizer to App Store Connect.

## Publisher Requirements

The publishing owner must provide:

- Apple Developer Program membership
- App Store Connect access
- signing certificate
- provisioning profile
- App Store app record
- screenshots
- privacy details
- final app review metadata

## Signing

Signing assets are intentionally not stored in this repository. A publisher should configure signing through Xcode using their own Apple Developer team.

