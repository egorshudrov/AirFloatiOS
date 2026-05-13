#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${TMPDIR:-/tmp}/airfloat-core-checks"
BINARY_PATH="$BUILD_DIR/AirFloatCoreChecks"
MODULE_CACHE_PATH="$BUILD_DIR/ModuleCache"

mkdir -p "$BUILD_DIR"
mkdir -p "$MODULE_CACHE_PATH"

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR

xcrun swiftc \
  -module-cache-path "$MODULE_CACHE_PATH" \
  "$ROOT_DIR/AirFloat/Core/Session/ExerciseKey.swift" \
  "$ROOT_DIR/AirFloat/Core/Session/WorkoutSessionAttemptRecord.swift" \
  "$ROOT_DIR/AirFloat/Core/Session/WorkoutSessionRecord.swift" \
  "$ROOT_DIR/AirFloat/Core/Session/SessionRepository.swift" \
  "$ROOT_DIR/AirFloat/Core/Exercise/ExerciseCatalogItem.swift" \
  "$ROOT_DIR/AirFloat/Core/Exercise/ExerciseCatalog.swift" \
  "$ROOT_DIR/AirFloat/Core/Exercise/TrainExerciseAvailability.swift" \
  "$ROOT_DIR/AirFloat/Core/Progress/LatestSessionMapModel.swift" \
  "$ROOT_DIR/AirFloat/Core/Progress/LatestSessionMapFactory.swift" \
  "$ROOT_DIR/AirFloat/Core/Progress/ProgressSummaryModel.swift" \
  "$ROOT_DIR/AirFloat/Core/Progress/ProgressSummaryFactory.swift" \
  "$ROOT_DIR/AirFloat/Core/Progress/ConsistencyCalendarModel.swift" \
  "$ROOT_DIR/AirFloat/Core/Progress/ConsistencyCalendarFactory.swift" \
  "$ROOT_DIR/AirFloat/Core/Today/TodayRecommendationInput.swift" \
  "$ROOT_DIR/AirFloat/Core/Today/TodaySummaryModel.swift" \
  "$ROOT_DIR/AirFloat/Core/Today/TodaySummaryFactory.swift" \
  "$ROOT_DIR/AirFloat/Core/Today/TodayBodyMapModel.swift" \
  "$ROOT_DIR/AirFloat/Core/Today/TodayBodyMapFactory.swift" \
  "$ROOT_DIR/AirFloat/Core/Schedule/PlannedDayType.swift" \
  "$ROOT_DIR/AirFloat/Core/Schedule/ProgramWeekday.swift" \
  "$ROOT_DIR/AirFloat/Core/Schedule/ProgramScheduleDate.swift" \
  "$ROOT_DIR/AirFloat/Core/Schedule/ProgramSchedule.swift" \
  "$ROOT_DIR/AirFloat/Core/Schedule/ProgramScheduleRepository.swift" \
  "$ROOT_DIR/AirFloat/Core/FirstLaunch/FirstLaunchState.swift" \
  "$ROOT_DIR/AirFloat/Core/FirstLaunch/FirstLaunchRepository.swift" \
  "$ROOT_DIR/AirFloat/App/AppRootNavigationContract.swift" \
  "$ROOT_DIR/AirFloat/Core/Session/WorkoutSessionStartRequest.swift" \
  "$ROOT_DIR/AirFloat/Features/Live/LivePoseFrame.swift" \
  "$ROOT_DIR/AirFloat/Features/Live/LiveDiagnosticsPolicy.swift" \
  "$ROOT_DIR/AirFloat/Features/Live/LiveBarbellPressCounter.swift" \
  "$ROOT_DIR/AirFloat/Features/Live/LiveSquatCounter.swift" \
  "$ROOT_DIR/AirFloat/Features/Live/LivePushupCounter.swift" \
  "$ROOT_DIR/AirFloat/Features/Live/LiveSitupCounter.swift" \
  "$ROOT_DIR/AirFloat/Features/Live/LiveSessionState.swift" \
  "$ROOT_DIR/AirFloat/Features/Train/TrainRecentSessionModel.swift" \
  "$ROOT_DIR/AirFloat/Features/Train/TrainRecentSessionsFactory.swift" \
  "$ROOT_DIR/tools/core_checks/main.swift" \
  -o "$BINARY_PATH"

"$BINARY_PATH"
