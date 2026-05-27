# clean_connect

A new Flutter project.

## Run the app (with Supabase keys)

This app loads Supabase credentials from bundled env files (`env.txt.example` plus optional `env.txt`) via `flutter_dotenv`. You can also pass keys with `--dart-define` if you wire that in your launch config (see below).

### Option A: `env.txt` (matches `pubspec.yaml` assets)

From the project root, create `env.txt` if you do not have it yet (this removes the `asset_does_not_exist` warning and is required for `flutter pub get` / builds):

```bash
cp env.txt.example env.txt
```

Edit `env.txt` with your real `SUPABASE_URL` and `SUPABASE_ANON_KEY`. The file is listed in `.gitignore` so it is not committed.

### Option B: `--dart-define` (only if your launch config merges these into dotenv)

The stock `main.dart` reads Supabase from dotenv (`env.txt.example` / `env.txt`), not from `String.fromEnvironment`. To use `--dart-define` alone you would need to extend startup code to merge those values into `dotenv.load(mergeWith: ...)`.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
