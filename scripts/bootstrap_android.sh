
#!/usr/bin/env bash
set -euo pipefail

GRADLE_VERSION="8.14.3"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP"
}
trap cleanup EXIT

if ! command -v flutter >/dev/null 2>&1; then
  echo "ERROR: Flutter SDK is required." >&2
  exit 1
fi

echo "Generating Android Gradle wrapper..."

flutter create \
  --platforms=android \
  --project-name tvexp_iptv \
  "$TMP/wrapper_seed" >/dev/null

WRAPPER_SOURCE="$TMP/wrapper_seed/android/gradle/wrapper"
WRAPPER_TARGET="$ROOT/android/gradle/wrapper"

if [[ ! -f "$WRAPPER_SOURCE/gradle-wrapper.properties" ]]; then
  echo "ERROR: Gradle wrapper generation failed." >&2
  exit 1
fi

mkdir -p "$ROOT/android/gradle"

cp "$TMP/wrapper_seed/android/gradlew" "$ROOT/android/gradlew"
cp "$TMP/wrapper_seed/android/gradlew.bat" "$ROOT/android/gradlew.bat"

rm -rf "$WRAPPER_TARGET"
mkdir -p "$WRAPPER_TARGET"

cp -R "$WRAPPER_SOURCE/." "$WRAPPER_TARGET/"

chmod +x "$ROOT/android/gradlew"

WRAPPER_PROPERTIES="$WRAPPER_TARGET/gradle-wrapper.properties"

sed -i \
  "s#^distributionUrl=.*#distributionUrl=https\\\\://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-all.zip#" \
  "$WRAPPER_PROPERTIES"

if ! grep -Fq "gradle-${GRADLE_VERSION}-all.zip" "$WRAPPER_PROPERTIES"; then
  echo "ERROR: Gradle version verification failed." >&2
  exit 1
fi

echo "Android Gradle wrapper installed successfully."
echo "Gradle version: ${GRADLE_VERSION}"
echo "Android Gradle Plugin: 8.11.1"

echo "Next: flutter pub get && flutter analyze && flutter test"
