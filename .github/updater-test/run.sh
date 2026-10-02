#!/bin/bash
# keepup's built-in updater, proven on a Mac that has never run keepup: one of GitHub's (scripts/updater-test.py in
# keepup's own repo starts this). Build A (keepup-test-A.zip in the "updater-test" prerelease) is installed fresh
# for each case; the feed beside it (appcast.xml) offers build B. keepup stays running when it's asked to quit, so
# each case checks that an update still gets through, and that keepup comes back afterwards.
# It deletes /Applications/keepup.app and keepup's preferences: it refuses to run anywhere but on a runner.
set -uo pipefail

if [ "${GITHUB_ACTIONS:-}" != true ]; then
    echo "this replaces the installed keepup: it only runs on GitHub's runners" >&2
    exit 2
fi

ID=com.markestefanos.keepup.mac
APP=/Applications/keepup.app
FEED="https://github.com/$GITHUB_REPOSITORY/releases/download/updater-test"
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
OUT="${RUNNER_TEMP:-/tmp}/updater-test"  # screenshots and the log, kept with the run
BEGAN="$(date '+%Y-%m-%d %H:%M:%S')"
STARTED="$BEGAN"
failures=0
mkdir -p "$OUT"

say() { printf '\n== %s\n' "$*"; }
pass() { printf '   ok: %s\n' "$*"; }
shot() { screencapture -x "$OUT/$1.png" 2>/dev/null || true; }
fail() {
    printf '   FAILED: %s\n   now: %s, build %s\n' "$*" "$(state)" "$(build)"
    failures=$((failures + 1))
    shot "failed-$failures"
}

state() { "$WORK/probe" state; }
field() { state | tr ' ' '\n' | sed -n "s/^$1=//p"; }
build() { /usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Contents/Info.plist" 2>/dev/null || echo none; }

# what must be true
in_dock() { [ "$(field policy)" = regular ] && [ "$(field windows)" -ge 1 ]; }
menu_bar_only() { [ "$(state | cut -d' ' -f2-)" = "policy=accessory windows=0" ]; }
same_in_menu_bar() { [ "$(state)" = "pid=$1 policy=accessory windows=0" ]; }
waiting_with_window() { [ "$(build)" = "$OLD" ] && [ "$(field pid)" = "$1" ] && [ "$(field windows)" -ge 1 ]; }
updated_from() { [ "$(build)" = "$NEW" ] && [ "$(field pid)" != 0 ] && [ "$(field pid)" != "$1" ]; }
logged() {  # keepup's own account of the update, since this case began (ios/CommsMac/Updates.swift)
    sudo log show --start "$STARTED" --predicate "subsystem == \"$ID\"" --style compact 2>/dev/null | grep -q "$1"
}

close_windows() {  # each of keepup's windows, by its close button (fails where a script may not click)
    osascript > /dev/null 2>&1 << 'END'
tell application "System Events" to tell process "keepup"
    repeat 5 times
        if (count of windows) is 0 then exit repeat
        click (first button of window 1 whose subrole is "AXCloseButton")
        delay 1
    end repeat
end tell
END
}

check() {  # check "what" condition...
    local what=$1
    shift
    if "$@"; then pass "$what"; else fail "$what"; fi
}

wait_for() {  # wait_for seconds "what" condition...
    local end=$((SECONDS + $1)) seconds=$1 what=$2
    shift 2
    until "$@"; do
        if [ "$SECONDS" -ge "$end" ]; then
            fail "$what (waited $seconds s)"
            return 1
        fi
        sleep 2
    done
    pass "$what"
}

fresh() {  # build A as on a Mac that has never run keepup, opened. $1: seconds until its next update check (0: at launch)
    pkill -x keepup
    pkill -x Autoupdate
    pkill -x Updater
    sleep 2
    rm -rf "$APP" "$HOME/Library/Saved Application State/$ID.savedState" "$HOME/Library/Caches/$ID"
    defaults delete "$ID" > /dev/null 2>&1
    ditto -x -k "$WORK/keepup-test-A.zip" /Applications
    # "install updates automatically" on, and the last check an hour ago less $1 seconds (an hour is the shortest
    # time Sparkle leaves between checks)
    defaults write "$ID" SUEnableAutomaticChecks -bool YES
    defaults write "$ID" SUAutomaticallyUpdate -bool YES
    defaults write "$ID" SUHasLaunchedBefore -bool YES
    defaults write "$ID" SUScheduledCheckInterval -int 3600
    defaults write "$ID" SULastCheckTime -date "$(date -u -v-3600S -v+"$1"S '+%Y-%m-%d %H:%M:%S +0000')"
    STARTED="$(date '+%Y-%m-%d %H:%M:%S')"
    open "$APP"
}

say "Setting up on $(sw_vers -productName) $(sw_vers -productVersion) ($(uname -m))"
swiftc -O "$HERE/probe.swift" -o "$WORK/probe" || exit 1
curl -fsSL -o "$WORK/keepup-test-A.zip" "$FEED/keepup-test-A.zip" || exit 1
curl -fsSL -o "$WORK/appcast.xml" "$FEED/appcast.xml" || exit 1
ditto -x -k "$WORK/keepup-test-A.zip" "$WORK/A"
OLD="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$WORK/A/keepup.app/Contents/Info.plist")"
NEW="$(sed -n 's/.*<sparkle:version>\([0-9]*\)<.*/\1/p' "$WORK/appcast.xml" | sort -n | tail -1)"
echo "   build $OLD is installed; the feed offers build $NEW"
if [ -z "$OLD" ] || [ -z "$NEW" ] || [ "$NEW" -le "$OLD" ]; then
    echo "   the feed must offer a newer build than the one installed" >&2
    exit 1
fi
spctl --assess --type execute -v "$WORK/A/keepup.app" 2>&1 | sed 's/^/   /'

say "1. A quit leaves keepup in the menu bar, and an update that arrives there installs itself"
fresh 50
if wait_for 60 "keepup opens with a window, in the Dock" in_dock; then
    shot 1-opened
    first="$(field pid)"
    "$WORK/probe" quit
    wait_for 20 "after a quit the same keepup is running, in the menu bar only" same_in_menu_bar "$first"
    "$WORK/probe" quit
    sleep 3
    check "a second quit, from the menu bar, leaves it running too" same_in_menu_bar "$first"
    check "it's still build $OLD" [ "$(build)" = "$OLD" ]
    if wait_for 300 "build $NEW installed itself and keepup is running again" updated_from "$first"; then
        sleep 8
        check "it came back in the menu bar only, with no window" menu_bar_only
        check "keepup's log says it installed from the menu bar" logged "installing from the menu bar"
        second="$(field pid)"
        "$WORK/probe" quit
        sleep 4
        check "build $NEW leaves a quit in the menu bar too" same_in_menu_bar "$second"
    fi
    shot 1-updated
fi

say "2. An update that's ready while a window is open waits, and installs when a quit closes the window"
fresh 0
if wait_for 60 "keepup opens with a window, in the Dock" in_dock; then
    first="$(field pid)"
    if wait_for 300 "the update downloaded in the background" logged "is downloaded and ready"; then
        sleep 5
        check "it waits while the window is open: build $OLD, the same keepup, its window" waiting_with_window "$first"
        "$WORK/probe" quit
        if wait_for 300 "the quit closed the window, build $NEW installed and keepup is running again" updated_from "$first"; then
            sleep 8
            check "it came back in the menu bar only, with no window" menu_bar_only
        fi
    fi
    shot 2-updated
fi

say "3. The same, when the window is closed with its close button"
fresh 0
if wait_for 60 "keepup opens with a window, in the Dock" in_dock; then
    first="$(field pid)"
    if wait_for 300 "the update downloaded in the background" logged "is downloaded and ready"; then
        sleep 5
        close_windows
        if waiting_with_window "$first"; then
            echo "   skipped: this runner doesn't let a script click the window's close button"
        elif wait_for 300 "closing the window installed build $NEW, and keepup is running again" updated_from "$first"; then
            sleep 8
            check "it came back in the menu bar only, with no window" menu_bar_only
        fi
    fi
    shot 3-updated
fi

say "What keepup and its updater logged"
sudo log show --start "$BEGAN" --style compact --predicate \
    "subsystem == \"$ID\" || subsystem == \"org.sparkle-project.Sparkle\" || process == \"Autoupdate\" || process == \"Updater\"" \
    > "$OUT/log.txt" 2>&1
grep -c . "$OUT/log.txt" | sed 's/^/   lines kept with the run: /'
grep "$ID" "$OUT/log.txt" | grep "update:" | sed 's/^/   /'
if [ "$failures" -gt 0 ]; then
    tail -150 "$OUT/log.txt"
    say "$failures failed"
    exit 1
fi
say "All passed"
