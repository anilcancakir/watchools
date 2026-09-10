#!/usr/bin/env bash
#
# Start the app with a provider credential, for development.
#
# There is no onboarding screen and, on macOS, no way to store a credential at
# all: `Vault` is the Keychain, a sandboxed build has no
# `keychain-access-groups` entitlement, and adding one makes the build demand a
# development certificate, so every write fails with OSStatus -34018. Without a
# credential `hasCredentials` is false, all four screens fall back to the
# fixture, and a fixture channel carries no `streamId`, so nothing is playable.
#
# This reads `.env.local` (gitignored, and the file CLAUDE.md reserves for
# exactly this) and passes the four values as `--dart-define`. The app reads
# them through `XtreamCredentials.fromEnvironment`, in debug builds only and
# only when the vault is empty.
#
# Why not have the app read `.env.local` itself: magic loads exactly one env
# file and reads it as a Flutter asset, and a declared asset that is missing
# fails the build outright. Declaring `.env.local` would make every fresh
# checkout require one.
#
# Usage:
#   tool/dev/run_with_provider.sh                 # macOS, the default
#   tool/dev/run_with_provider.sh chrome          # any device id
#
# Against the local mock panel, which is what to use unless a real stream is
# the point (`tool/xtream-mock/README.md`):
#   node tool/xtream-mock/server.mjs &
#   printf 'XTREAM_BASE_URL=http://127.0.0.1:3300\nXTREAM_USERNAME=demo\nXTREAM_PASSWORD=demo\n' > .env.local
#   tool/dev/run_with_provider.sh
set -euo pipefail

cd "$(dirname "$0")/../.."

DEVICE="${1:-macos}"
ENV_FILE=".env.local"

if [[ ! -f "$ENV_FILE" ]]; then
    printf '\033[31m%s does not exist.\033[0m\n' "$ENV_FILE"
    printf 'It is gitignored and holds the four values this script passes as defines:\n\n'
    printf '  XTREAM_BASE_URL=http://127.0.0.1:3300\n'
    printf '  XTREAM_USERNAME=demo\n'
    printf '  XTREAM_PASSWORD=demo\n'
    printf '  XTREAM_USER_AGENT=Watchools/1.0   # optional\n\n'
    printf 'For a local panel that serves real video and costs no provider request:\n'
    printf '  node tool/xtream-mock/server.mjs\n'
    exit 1
fi

# Read the four keys individually rather than sourcing the file. Sourcing would
# execute whatever is in it and would also export every unrelated key, and this
# file is the one place in the repo that may hold a real subscription password.
read_key() {
    # Last assignment wins, matching dotenv, and the value keeps any `=` in it.
    grep -E "^${1}=" "$ENV_FILE" | tail -n 1 | cut -d= -f2- || true
}

BASE_URL="$(read_key XTREAM_BASE_URL)"
USERNAME="$(read_key XTREAM_USERNAME)"
PASSWORD="$(read_key XTREAM_PASSWORD)"
USER_AGENT="$(read_key XTREAM_USER_AGENT)"

MISSING=()
[[ -z "$BASE_URL" ]] && MISSING+=(XTREAM_BASE_URL)
[[ -z "$USERNAME" ]] && MISSING+=(XTREAM_USERNAME)
[[ -z "$PASSWORD" ]] && MISSING+=(XTREAM_PASSWORD)

if (( ${#MISSING[@]} > 0 )); then
    printf '\033[31m%s is missing: %s\033[0m\n' "$ENV_FILE" "${MISSING[*]}"
    printf 'A partial set is refused rather than half-honoured: the app requires all\n'
    printf 'three, because guessing a default for a password is the one thing it must\n'
    printf 'never do.\n'
    exit 1
fi

# The base URL and the user name are printed; the password never is, and neither
# is the assembled stream URL, which carries it in its path.
printf '\033[32m→\033[0m %s as %s on %s\n' "$BASE_URL" "$USERNAME" "$DEVICE"

DEFINES=(
    "--dart-define=XTREAM_BASE_URL=$BASE_URL"
    "--dart-define=XTREAM_USERNAME=$USERNAME"
    "--dart-define=XTREAM_PASSWORD=$PASSWORD"
)
[[ -n "$USER_AGENT" ]] && DEFINES+=("--dart-define=XTREAM_USER_AGENT=$USER_AGENT")

# `flutter run` directly rather than `fsa start`, because this is an
# interactive session a human watches: `fsa start` detaches and records a VM
# service URI for the dusk tooling, which is a different job. Pass the same
# defines to `fsa start --flutter-arg=` when driving the app from a script.
exec flutter run -d "$DEVICE" "${DEFINES[@]}"
