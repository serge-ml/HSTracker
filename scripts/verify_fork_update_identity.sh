#!/usr/bin/env bash
set -euo pipefail

readonly INFO_PLIST="HSTracker/Info.plist"
readonly PROJECT_FILE="HSTracker.xcodeproj/project.pbxproj"
readonly PACKAGE_RESOLVED="HSTracker.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
readonly EXPECTED_FEED="https://serge-ml.github.io/HSTracker/appcast.xml"
readonly EXPECTED_PUBLIC_KEY="7l1tt2vHbSr03uOge75vssUgsmcVN56u12/NffbvbAw="
readonly OFFICIAL_PUBLIC_KEY="FAEVNwLFlLldmu1C6aA0h041sJAP1sWrTjQhE9iw7BE="

fail() {
  echo "Updater identity check failed: $*" >&2
  exit 1
}

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$INFO_PLIST"
}

[[ "$(plist_value SUFeedURL)" == "$EXPECTED_FEED" ]] ||
  fail "unexpected SUFeedURL"
[[ "$(plist_value SUPublicEDKey)" == "$EXPECTED_PUBLIC_KEY" ]] ||
  fail "unexpected SUPublicEDKey"
[[ "$(plist_value SUEnableSystemProfiling)" == "false" ]] ||
  fail "system profiling must stay disabled"

grep -q 'repositoryURL = "https://github.com/sparkle-project/Sparkle";' \
  "$PROJECT_FILE" ||
  fail "Sparkle package is not configured"
grep -q 'kind = exactVersion;' "$PROJECT_FILE" ||
  fail "Sparkle must use an exact package requirement"
grep -q 'version = 2.9.2;' "$PROJECT_FILE" ||
  fail "Sparkle 2.9.2 is not pinned in the project"
grep -q '"version" : "2.9.2"' "$PACKAGE_RESOLVED" ||
  fail "Sparkle 2.9.2 is not resolved"

if git grep -I -q \
  -e 'hsdecktracker.net/hstracker/appcast' \
  -e "$OFFICIAL_PUBLIC_KEY" \
  -- HSTracker .github scripts \
  ':!scripts/verify_fork_update_identity.sh'; then
  fail "official HSTracker feed or public key is present"
fi

if git grep -I -q -E \
  'BEGIN (RSA |EC |OPENSSH |ENCRYPTED )?PRIVATE KEY' -- .; then
  fail "a PEM private key is tracked"
fi

if git ls-files |
  grep -E -q \
    '(^|/)(dsa_priv\.pem|sparkle[^/]*private[^/]*|[^/]*\.(p12|pfx))$'; then
  fail "a release private-key file is tracked"
fi

echo "Fork updater identity is valid."
