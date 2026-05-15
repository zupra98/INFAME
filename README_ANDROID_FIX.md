# Infame Android v2 embedding fix

This fixes the `Build failed due to use of deleted Android v1 embedding` issue caused by the local files v2 patch.

What it does:
- Restores a modern AndroidManifest.xml with `flutterEmbedding` value `2`.
- Keeps audio/storage permissions needed for local files.
- Deletes the checked-in `android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java`.
  Modern Flutter generates this during build; it should not be manually checked into `android/app/src/main`.
- Deletes accidental root-level `AndroidManifest.xml` if present.

How to apply:

1. Extract this zip into the project root:
   `D:\MUSIC APP\musix`

2. Run PowerShell from project root:

```powershell
cd "D:\MUSIC APP\musix"
powershell -ExecutionPolicy Bypass -File ".\fix_android_v2_embedding.ps1"
flutter clean
flutter pub get
flutter build apk --debug
```

If it still fails, run:

```powershell
Select-String -Path "android\app\src\main\AndroidManifest.xml","android\app\src\main\kotlin\**\*.kt","android\app\src\main\java\**\*.java" -Pattern "io\.flutter\.app|FlutterApplication|flutterEmbedding.*1|GeneratedPluginRegistrant\.registerWith|ShimPluginRegistry|ShimRegistrar"
```

Then send the output.
