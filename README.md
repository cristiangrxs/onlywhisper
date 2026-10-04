# OnlyWhisper

<p align="center">
  <img src="https://raw.githubusercontent.com/cristiangrxs/onlywhisper-landingpage/main/media/command-palette.png" alt="OnlyWhisper command palette">
</p>

<p align="center">
  <a href="https://github.com/cristiangrxs/onlywhisper/releases/latest"><img src="https://img.shields.io/github/v/release/cristiangrxs/onlywhisper?style=flat-square" alt="Latest release"></a>
  <a href="https://onlywhisper.dev"><img src="https://img.shields.io/badge/macOS-27-0A84FF?style=flat-square&logo=apple&logoColor=white" alt="macOS 27"></a>
  <img src="https://img.shields.io/badge/Apple%20silicon-only-black?style=flat-square" alt="Apple silicon">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache--2.0-green?style=flat-square" alt="License: Apache-2.0"></a>
</p>

Dictation for the Mac menu bar. Audio stays on the Mac.

Hold the right Option key, speak, and the text lands in the field you are using. A tap of the same key dictates hands-free.

https://github.com/user-attachments/assets/c6df423b-4328-41cf-9886-39abaa23691f

![The sentence after it lands](https://raw.githubusercontent.com/cristiangrxs/onlywhisper-landingpage/main/media/inserted.png)

## What it does

- Dictation in the focused app, with a live transcript
- Polish and rewrite on the Mac, with Qwen3 4B
- Meetings with speakers, and transcription of audio and video files
- History and a custom dictionary

Speech recognition is Whisper Large v3, on device. The first launch downloads the models (about 4 GB). After that, OnlyWhisper works offline.

## Install

Download the signed disk image from the [latest release](https://github.com/cristiangrxs/onlywhisper/releases/latest).

You need an Apple silicon Mac on macOS 27. The app asks for the microphone, Accessibility, and Input Monitoring.

## Build

Open `OnlyWhisper.xcodeproj` in Xcode, or:

```sh
xcodebuild -project OnlyWhisper.xcodeproj -scheme OnlyWhisper -configuration Release -destination 'platform=macOS,arch=arm64'
```

## Contributing

Issues and pull requests are welcome. The maintainer merges them.

## License

[Apache-2.0](LICENSE)
