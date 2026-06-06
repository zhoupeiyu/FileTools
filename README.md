# PDF Compression

Flutter desktop app for local PDF compression on macOS and Windows.

## V1 Features

- Select one local PDF.
- Choose compression strength: high compression, recommended, high quality.
- Choose a save location.
- Customize the output file name.
- Default output name: original file name plus `_compressed.pdf`.
- Run compression locally with bundled Ghostscript. No upload.

## Run

```bash
flutter pub get
flutter run -d macos
```

## Build

macOS:

```bash
flutter build macos
```

Windows:

```bash
flutter build windows
```

Windows release package on a Windows host:

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\build_windows_release.ps1
powershell -ExecutionPolicy Bypass -File .\tool\build_windows_installer.ps1
```

The packaged files are written to:

```text
dist\FileTools-windows-x64.zip
dist\FileToolsSetup-1.0.0-x64.exe
```

Windows release package without a Windows computer:

1. Push this project to GitHub.
2. Open the repository on GitHub.
3. Go to Actions -> Windows Release.
4. Click Run workflow.
5. Download the artifacts after the workflow completes.

- `FileTools-windows-installer` contains the installer for other people.
- `FileTools-windows-x64` contains the portable zip.

For normal users, download `FileTools-windows-installer`, unzip the artifact,
then run `FileToolsSetup-1.0.0-x64.exe`.

Windows verification on a Windows host:

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\verify_windows.ps1
```

To verify with a specific PDF:

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\verify_windows.ps1 -InputPdf "C:\path\file.pdf"
```

The app bundles Ghostscript resources from `third_party/ghostscript`.

- macOS build copies `third_party/ghostscript/macos` into
  `Contents/Resources/ghostscript`.
- Windows build copies `third_party/ghostscript/windows` next to the executable
  as `ghostscript`.

## Verification

```bash
flutter analyze
flutter test
flutter build macos --debug
```

Manual compression has been verified on macOS with bundled Ghostscript.
Windows resource paths and CMake copy rules are implemented, but final Windows
runtime verification must be run on a Windows machine with
`tool/verify_windows.ps1`.

## License

Ghostscript 10.07.1 is bundled. Ghostscript is available under AGPL or a
commercial Artifex license. Confirm the correct license path before distributing
this app outside local/internal use.
