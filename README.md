# Rest & Routine

A private, native macOS app for keeping track of sleep and a few everyday habits: water, movement and wind-down. Everything is entered by hand and stays on your Mac.

- **Today** shows your last sleep (time in bed, estimated sleep when you entered awake minutes, quality, source) and today's habits. **Log sleep** (⌘L) opens the sleep sheet.
- **History** lists recent dates, opens any date (including ones you did not log), and lets you edit or delete a date's sleep and habits after confirming.
- **Trends** shows 7-day and 30-day charts for time in bed, estimated sleep, quality, water, movement and wind-down. Missing days are gaps, and averages use logged days only.
- **Settings** (⌘, or the sidebar's Settings button) holds the appearance, the water unit (mL or US fl oz), optional morning and evening reminders (off until you turn them on), backup and restore, and Delete All Records.

## Appearance

Settings › Appearance changes the look of every open window at once and keeps it after you quit:

- **Preset**: Soft studio (the starting look: soft tiles and tinted blocks), Dusk journal (warm paper tones and outlined cards) or Quiet signal (precise borders and monospaced values). Choosing a preset also sets its accent and headings.
- **Appearance**: Follow system, Light or Dark.
- **Accent**: Ember, Moss, Ocean or Iris, each with light and dark shades.
- **Headings**: Journal (serif), Soft (rounded) or Clean (system). Body text stays in the system font.
- **Reset appearance** returns to Soft studio, Follow system, Ocean and rounded headings. It does not change units, reminders or records.

## Requirements

macOS 14 or later, Xcode 16 or later (built and tested with Xcode 27.0).

## Build, run and test

Open `RestRoutine.xcodeproj` and run the **RestRoutine** scheme, or from a terminal:

```sh
xcodebuild -project RestRoutine.xcodeproj -scheme RestRoutine -derivedDataPath build build
open build/Build/Products/Debug/RestRoutine.app

xcodebuild -project RestRoutine.xcodeproj -scheme RestRoutine -derivedDataPath build test
```

The app is signed to run locally (ad hoc); it is not set up for distribution. The test run uses a disposable database (`-RRDisposableStore`, Debug builds only), so it never touches your records. `SnapshotTests` renders each screen with sample records, in every preset and in light and dark, into the app container's `tmp/RestRoutineSnapshots` folder. `ThemePropagationTests` work the real Settings controls and check that every open window follows them.

## Rules the app follows

- Time in bed is the elapsed time between bedtime and wake time, so it stays correct across daylight-saving changes. Estimated sleep is time in bed minus awake minutes, and only exists when you enter awake minutes.
- Each sleep entry belongs to the date you woke up, in the time zone you were in. One entry per wake date; saving a second one offers to edit the existing entry instead.
- A habit you did not enter is **Not logged**, which is different from zero or **Not done**. Water is stored in milliliters; movement is whole minutes.
- There are no targets, scores or medical advice.

## Privacy and storage

- Records live in a SwiftData database under `~/Library/Containers/com.example.RestRoutine/Data/Library/Application Support/RestRoutine/`. Preferences, including the appearance, stay in the same sandbox; the appearance is not part of backups. There is no account, network access, cloud sync, analytics or HealthKit access.
- The database and backup files are not separately encrypted; other software running as you can read them.
- **Back Up Records** writes a versioned JSON file (format `com.example.RestRoutine.backup`, version 1) to a place you choose. **Restore** checks the whole file first, asks before replacing anything, and leaves your records unchanged if the file is invalid. Restored reminders stay off until you turn them on again.
- Reminders ask for notification permission only when you turn one on, show generic text with no health values, and may not arrive while the Mac is asleep, off or in a Focus.
- **Delete All Records** removes every record and turns reminders off. It does not touch backup files.
