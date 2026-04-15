# Releasing

## Automated (recommended)

```bash
./release.sh --new-version 1.0.0
```

This will:
1. Set `version.properties` to `1.0.0`
2. Commit `Release 1.0.0`
3. Create annotated git tag `1.0.0`
4. Push commit + tag (triggers CI publish to Maven Central)
5. Bump to `1.0.1-SNAPSHOT` and push

Common options:

```bash
# Preview without changing anything
./release.sh --new-version 1.0.0 --dry-run

# Publish to Maven local instead of pushing (useful for testing the build)
./release.sh --new-version 1.0.0 --maven-local

# Override the next snapshot version
./release.sh --new-version 1.0.0 --next-snapshot 1.1.0-SNAPSHOT

# Do everything except pushing (then push manually)
./release.sh --new-version 1.0.0 --no-push
```

Run `./release.sh --help` for all options.

---

## Manual steps

1. Update `version.properties` to the release version (remove `-SNAPSHOT`)
2. `git commit -am "Release X.Y.Z"`
3. `git tag -a X.Y.Z -m "X.Y.Z"`
4. `git push && git push --tags`
5. Update `version.properties` to the next snapshot version (e.g. `X.Y.Z+1-SNAPSHOT`)
6. `git commit -am "Prepare next development version."`
7. `git push`

---

## Publishing to Maven local (no credentials needed)

```bash
./gradlew :crashkit:publishToMavenLocal
```

The version is read from `version.properties`. No `-PVERSION_NAME` needed.
