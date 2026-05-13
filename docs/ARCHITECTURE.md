# AirFloat iOS Architecture

AirFloat iOS is organized around a native workout loop:

```text
Camera frame
  -> MediaPipe pose landmarks
  -> exercise-specific counter
  -> Live UI feedback
  -> local session record
  -> Progress review
```

## App Layer

- `App/AirFloatApp.swift` starts the SwiftUI app.
- `App/AppRootView.swift` owns root navigation across Today, Train, Live, Progress, and First Launch.
- `Shared/UI/ShellScreenScaffold.swift` provides the shared screen structure.

## Core Layer

The `Core/` folder contains platform-local domain models:

- `Session/` - workout records, attempts, and start requests
- `Exercise/` - exercise catalog and train availability
- `Schedule/` - weekly training schedule and date overrides
- `Progress/` - latest-session maps, calendar models, progress summaries
- `Today/` - body-map and recommendation models
- `MediaPipe/` - bundled pose model resource resolution

## Feature Layer

- `Features/Today/` renders the current workout focus and body-zone carousel.
- `Features/Train/` selects an exercise and goal reps.
- `Features/Live/` owns camera preview, pose source, skeleton overlay, and exercise counters.
- `Features/Progress/` renders latest-session review and calendar history.
- `Features/FirstLaunch/` handles first-run setup.

## Live Runtime

Live tracking is intentionally split:

- `LiveCameraController` owns AVFoundation capture.
- `MediaPipeLivePoseSource` converts frames into MediaPipe landmarks.
- `LivePoseFrame` normalizes landmark data for counters.
- Exercise counters make deterministic rep decisions per exercise.
- `LiveSessionState` accumulates reps and attempt records before saving.

## Publishing Boundary

The repository contains source code, project files, dependency declarations, and bundled model assets. Signing material, generated archives, exported IPA files, and publisher account setup are intentionally outside version control.

