# crashkit

An Android library that wraps [Google Crashpad](https://chromium.googlesource.com/crashpad/crashpad/) and exposes a small Kotlin API for native crash reporting.

- Captures native (NDK) crashes as **minidumps** stored on-device.
- Runs the Crashpad handler as a separate subprocess — reliable capture even under low-memory conditions.
- Writes a crash marker file at signal time (async-signal-safe); calls back into the app on next launch so the app can fire its own telemetry pixel over HTTPS.
- Ships a sample app (`app/`) to exercise the integration.

---

## Kotlin API

```kotlin
// Initialize once per process (e.g. in Application.onCreate())
Crashpad.init(
    context,
    platform = "Android",
    version = BuildConfig.VERSION_NAME,
    osVersion = "Android SDK ${Build.VERSION.SDK_INT}",
    extraAnnotations = mapOf(          // optional, embedded in every minidump
        "customTab" to "false",
        "webViewVersion" to "...",
    ),
    config = CrashpadConfig(
        uploadUrl = "https://your-backend/upload",   // omit or leave "" to disable uploads
        uploadsEnabled = true,
        noRateLimit = BuildConfig.DEBUG,             // bypass 1-upload/hour limit in debug
        onCrash = {
            // Called on next launch if a crash occurred in the previous session.
            // Fire your own telemetry pixel here — runs on the calling thread.
            myPixel.fire("native_crash", mapOf("v" to BuildConfig.VERSION_NAME))
        },
    ),
)

// Dev / QA utilities
Crashpad.dumpWithoutCrash()   // capture a minidump without terminating
Crashpad.crash()              // trigger a real native crash (app terminates)
```

`init()` is idempotent — safe to call multiple times in the same process.

`CrashpadConfig` defaults to uploads disabled and no crash callback. Omit `config` entirely for local-only capture with no telemetry.

### Multi-process apps

Call `Crashpad.init()` **in each process** that should be covered. Each process runs its own Crashpad handler instance.

---

## Minidump location

Minidumps are written to:

```
<context.filesDir>/crashpad/new/        ← freshly captured
<context.filesDir>/crashpad/pending/    ← waiting to be uploaded
<context.filesDir>/crashpad/completed/  ← uploaded or manually processed
```

Uploads are **disabled by default** — minidumps accumulate locally. To enable uploads, pass a `CrashpadConfig` with `uploadsEnabled = true` and a URL pointing to a Crashpad-compatible ingestion backend (Sentry, Backtrace, self-hosted, or the included `server/crashpad_server.py` for local testing).

---

## Adding to your project

### Maven (AAR)

```kotlin
// settings.gradle.kts
dependencyResolutionManagement {
    repositories {
        mavenLocal()   // or mavenCentral() once published
    }
}

// build.gradle.kts
dependencies {
    implementation("com.duckduckgo.crashkit:android-crashkit:<version>")
}
```

### Module dependency (monorepo)

```kotlin
// settings.gradle.kts
include(":crashkit")

// build.gradle.kts
dependencies {
    implementation(project(":crashkit"))
}
```

---

## Publishing

### Prerequisites

Add the following to `~/.gradle/gradle.properties` (not in this repo):

```properties
# Sonatype Central Portal credentials
# Generate at: https://central.sonatype.com/account → User Tokens
mavenCentralUsername=<token-username>
mavenCentralPassword=<token-password>

# GPG signing key
signing.keyId=<last-8-chars-of-key-id>
signing.password=<passphrase>
signing.secretKeyRingFile=/Users/you/.gnupg/secring.gpg
```

To export your secret keyring if it doesn't exist yet:
```bash
gpg --export-secret-keys > ~/.gnupg/secring.gpg
```

### Commands

```bash
# Publish to Maven local (no credentials needed)
./gradlew :crashkit:publishToMavenLocal -PVERSION_NAME=0.0.2-SNAPSHOT

# Publish to Maven Central and release (upload + close + release staging repo)
./gradlew :crashkit:publishAndReleaseToMavenCentral -PVERSION_NAME=1.0.0
```

`VERSION_NAME` can also be set permanently in `gradle.properties` instead of passing it on the command line.

---

## Project layout

```
crashkit/               ← library module (AAR)
  src/main/
    java/               ← Crashpad.kt (Kotlin API)
    cpp/
      native-bridge.cpp ← JNI bridge
      process.cpp       ← process name helper
      crashpad/
        include/        ← vendored Crashpad headers
        lib/<abi>/      ← vendored static libs + handler per ABI
app/                    ← sample app
scripts/                ← Crashpad build helpers
BUILDING_CRASHPAD.md    ← how to update the vendored Crashpad artifacts
```

---

## Sample app (`app/`)

The `app/` module is a minimal Android app that exercises crashkit. Run it on a device or emulator (arm64-v8a or x86_64).

**Configuring the upload URL (real device):**

The debug build defaults to `10.0.2.2:8080` (Android emulator's alias for the host machine). To point a real device at your Mac's local server, add this to your `local.properties` (already gitignored):

```
crashpad.uploadHost=192.168.x.x
```

Then rebuild. Start the local server first with `python3 server/crashpad_server.py`.

**What you'll see on launch:**
- `"Crashpad initialized"` — handler started successfully
- `"Crashpad init failed"` — something went wrong (check logcat for details)

**Buttons:**
- **Dump Without Crash** — captures a minidump and returns normally. Use this to verify the pipeline without terminating the app.
- **Crash** — triggers a real native crash. The app terminates immediately and a minidump is written.

**Finding the minidumps:**

Use Android Studio's Device Explorer or adb:

```bash
adb shell ls /data/data/com.duckduckgo.crashkit.sample/files/crashpad/
# new/        ← just captured, not yet processed
# pending/    ← waiting to be uploaded
# completed/  ← processed
```

Pull a minidump to your machine:
```bash
adb pull /data/data/com.duckduckgo.crashkit.sample/files/crashpad/pending/ ./minidumps/
```

Minidumps have a `.dmp` extension. Each crash also produces a `.meta` sidecar file with basic metadata.

---

## Updating Crashpad

The Crashpad static libs and handler binary are vendored in `crashkit/src/main/cpp/crashpad/lib/`. To upgrade them, see **[BUILDING_CRASHPAD.md](BUILDING_CRASHPAD.md)**.

---

## License

Apache 2.0. Crashpad is licensed under its own upstream license.
