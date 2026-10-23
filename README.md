# OldCamera

> A standalone, modern iOS rebuild of the **Camera** app from **The OldOS Project**, keeping the iOS 6 silver look while running full screen on current iPhones and iPads with iOS 16 or later.

[![iOS](https://img.shields.io/badge/iOS-16.0%2B-0A84FF?logo=apple&logoColor=white)](#requirements)
[![Swift](https://img.shields.io/badge/Swift-SwiftUI-F05138?logo=swift&logoColor=white)](#architecture)
[![Build](https://img.shields.io/github/actions/workflow/status/iamgasgass/OldCamera/build.yml?branch=main&label=build)](https://github.com/iamgasgass/OldCamera/actions)
[![License](https://img.shields.io/badge/License-CC%20BY%204.0-lightgrey)](#license-and-attribution)

## Overview

**OldCamera** brings back the iOS 6 Camera:

- the live viewfinder;
- the translucent flash and HDR capsules and the front/back toggle;
- the brushed silver toolbar with the last-photo thumbnail, the silver shutter and the photo / video switch.

Photos and videos are captured with AVFoundation and saved to the Camera Roll.

## Features

Every control of OldOS `Camera.swift` is included, plus the Camera-SwiftUI service it used. Controls that OldOS only drew now work.

### Shooting

- **Photo:** the shutter takes a photo and saves it to the Camera Roll, with a quick black shutter flash. Each photo is saved in the orientation the phone was held. OldOS always saved portrait.
- **Video:**
  - the shutter starts and stops recording, with the original iOS 6 start / stop tones;
  - the record button blinks red and the 00:00:00 timer runs;
  - the session switches to the video preset (OldOS recorded with the 4:3 photo preset);
  - the microphone is opened only in video mode;
  - landscape clips keep their orientation.
- **Photo / video switch:** drag the knob or tap it, as in OldOS `camera_flipper`.

### Controls

- **Flash capsule** (shown only when the active camera has a flash): tap the bolt to unfold **Auto / On / Off**. It applies to photos; in video mode it drives the torch while recording. In OldOS it only displayed "Auto".
- **HDR capsule** in photo mode: **HDR On** uses the full multi-frame (Smart HDR) capture, **HDR Off** a single fast frame. In OldOS it was only drawn.
- **Front / back toggle**, hidden while recording, like OldOS.
- **Tap to focus** shows the blue iOS 6 focus square, which shrinks into place and blinks. In OldOS the focus view was invisible.
- **Pinch to zoom** (up to 5×) shows the iOS 6 − / + zoom slider, which you can also drag.

### From the Camera-SwiftUI service of OldOS

- Permission and error alerts: "Camera Access" with a Settings button, "Camera Error" when configuration fails or the session cannot resume.
- Spinner while a photo takes more than two seconds to process.
- Focus returns to the centre when the scene changes (subject-area monitoring).
- Video stabilisation after switching camera.
- Frame-rate throttling under thermal pressure.
- Recovery after interruptions (calls, other apps) and media-services resets.
- Embedded preview, HEVC capture and the photo model with compressed data and thumbnail. The thumbnail shows the new shot immediately.
- The capture buttons are disabled while the camera is unavailable.

### Camera Roll and display

- **Thumbnail** updates live. OldOS re-queried after 0.65 s, so it was often one shot behind.
- Tapping the thumbnail opens the **Camera Roll viewer** (inert in OldOS), with the OldPhotos viewer:
  - photos at normal size, swipe, pinch and double-tap zoom, video playback;
  - Email / Message / Copy / Share and Delete;
  - **Camera** returns to the viewfinder.
- **Rotating icons:** turn the phone and the glyphs rotate while the interface stays portrait, as on iOS 6.
- **Aspect UI** in Settings › OldCamera: *Sistema*, *Chiaro* or *Scuro*. In Scuro the silver toolbar, shutter, capsules and photo / video switch use OldSafari's Private graphite palette, with light glyphs; the Camera Roll viewer keeps its black chrome in both.
- **Full screen:** the viewfinder fills the display, the header sits below the Dynamic Island, the silver toolbar extends behind the home indicator, and the status bar is hidden like iOS 6.

## Architecture

```text
OldCamera/
├── .github/workflows/build.yml       # XcodeGen + unsigned IPA build
├── project.yml
├── OldCamera/
│   ├── OldCameraApp.swift            # App / scene delegate, hosting controller (status bar)
│   ├── Models/CameraModels.swift     # mode, flash, camera roll navigator / sheets
│   ├── Store/                        # CameraService (AVFoundation), CameraRoll (PhotoKit), CameraRollActions
│   ├── Views/                        # root, preview + focus square, header / toolbar / switch, Camera Roll viewer
│   ├── Support/                      # OldOSKit (shared with OldSafari) + Camera additions
│   ├── Settings.bundle/              # Settings › OldCamera (Aspect UI)
│   ├── Resources/Sounds/             # RecordStart.caf, RecordStop.caf
│   ├── Assets.xcassets/              # Camera Icons (iOS 6 artwork, renamed) + app icon (Any / Dark / Tinted)
│   └── Info.plist
├── EXTRACTION.json
├── README.md
└── LICENSE
```

## Requirements

- macOS with Xcode 16 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen).
- iPhone or iPad with a camera, running iOS 16.0 or later. The Simulator has no camera.

## Build Locally

```bash
git clone https://github.com/iamgasgass/OldCamera.git
cd OldCamera
brew install xcodegen
xcodegen generate
open OldCamera.xcodeproj
```

## Unsigned IPA via GitHub Actions

The workflow in `.github/workflows/build.yml`:

1. Generates the project from `project.yml`.
2. Builds the app unsigned.
3. Verifies the bundle: the icon, the record tones, and the Camera and Microphone usage strings.
4. Uploads `OldCamera-Unsigned.ipa` and the build log.

## License and Attribution

OldCamera is a standalone rebuild derived from the Camera app in **The OldOS Project** by [@zzanehip](https://github.com/zzanehip), licensed under [Creative Commons Attribution 4.0 International](https://creativecommons.org/licenses/by/4.0/). The capture service is derived from Camera-SwiftUI by Rolando Rodriguez (MIT), as bundled in OldOS.

## Disclaimer

OldCamera is an independent, unofficial project, not affiliated with Apple Inc. iOS is a trademark of Apple Inc.

---

- Built by [iamgasgass](https://github.com/iamgasgass)
