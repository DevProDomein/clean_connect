# clean_connect

A new Flutter project.

## Run the app (with Supabase keys)

This app expects Supabase credentials at runtime via `--dart-define`.

### Option A (recommended): run on an emulator/simulator

```bash
flutter run --dart-define=SUPABASE_URL="https://YOURPROJECT.supabase.co" --dart-define=SUPABASE_ANON_KEY="YOUR_ANON_KEY"
```

### Option B: run in a browser (fast “emulator-like” preview)

```bash
flutter run -d chrome --dart-define=SUPABASE_URL="https://YOURPROJECT.supabase.co" --dart-define=SUPABASE_ANON_KEY="YOUR_ANON_KEY"
```

If you see an error about missing keys, it means one of the `--dart-define` values wasn’t provided.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
