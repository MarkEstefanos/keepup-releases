#!/bin/bash
# keepup's built-in updater, proven on a Mac that has never run keepup: one of GitHub's (scripts/updater-test.py in
# keepup's own repo starts this). Build A (keepup-test-A.zip in the "updater-test" prerelease) is installed fresh
# for each case; the feed beside it (appcast.xml) offers build B. keepup stays running when it's asked to quit, so
# the first three cases check that an update still gets through, and that keepup comes back afterwards; the fourth,
# that the move to Applications at first launch (which must end the copy on the disk image) still works; the last
# three click through Sparkle's own windows when asked first, from build A, from the published 0.1.1, and from
# keepup's menu, where an update found while keepup sits in the menu bar waits.
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
    if [ -s "$OUT/ax.txt" ]; then sed 's/^/   seen: /' "$OUT/ax.txt"; fi
    failures=$((failures + 1))
    shot "failed-$failures"
}

state() { "$WORK/probe" state; }
field() { state | tr ' ' '\n' | sed -n "s/^$1=//p"; }
build() { /usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Contents/Info.plist" 2>/dev/null || echo none; }

# what must be true
running() { [ "$(field pid)" != 0 ]; }
in_dock() { [ "$(field policy)" = regular ] && [ "$(field windows)" -ge 1 ]; }
menu_bar_only() { [ "$(state | cut -d' ' -f2-)" = "policy=accessory windows=0" ]; }
same_in_menu_bar() { [ "$(state)" = "pid=$1 policy=accessory windows=0" ]; }
waiting_with_window() { [ "$(build)" = "$OLD" ] && [ "$(field pid)" = "$1" ] && [ "$(field windows)" -ge 1 ]; }
quit_stays() {  # a quit, then the same keepup is still there with no window
    local pid
    pid="$(field pid)"
    "$WORK/probe" quit
    sleep 4
    same_in_menu_bar "$pid"
}
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

answer_question() {  # press the default button of the question keepup is asking, e.g. "Copy to Applications and Open"
    osascript > /dev/null 2>&1 << END
tell application "System Events" to tell process "keepup"
    set frontmost to true
    repeat with w in windows
        if exists (button "$1" of w) then
            click button "$1" of w
            return
        end if
    end repeat
    key code 36 -- Return: the default button, where the question's buttons aren't the window's own
end tell
END
}
running_from_applications() {
    local pid
    pid="$(field pid)"
    [ "$pid" != 0 ] && ps -o command= -p "$pid" | grep -q "^$APP/"
}

# Sparkle's windows. The buttons it needs here are each window's default one (Install Update, then Install and
# Relaunch), so the test presses Return in Sparkle's window: System Events didn't list the buttons by name.
sparkle_window() {
    osascript -e 'tell application "System Events" to tell process "keepup" to exists (first window whose name is "Software Update" or name is "Updating keepup")' 2> /dev/null | grep -q true
}
sparkle_in_front() {  # keepup is the frontmost app, and Sparkle's window is its frontmost window
    osascript -e 'tell application "System Events" to tell process "keepup" to return (frontmost as text) & " " & (name of window 1)' 2> /dev/null | grep -q "^true Software Update$"
}
press_default() {  # Return in Sparkle's window, brought to the front
    osascript > /dev/null 2>&1 << 'END'
tell application "System Events" to tell process "keepup"
    set w to first window whose name is "Software Update" or name is "Updating keepup"
    set frontmost to true
    perform action "AXRaise" of w
    delay 0.5
    key code 36
end tell
END
}
installs_through_sparkle() {  # press Sparkle's default button whenever its window is up, until $1 has become build B
    updated_from "$1" && return 0
    sparkle_window && press_default
    return 1
}
sparkle_ax() {  # what System Events sees in Sparkle's window, kept with the run
    osascript > "$OUT/$1" 2>&1 << 'END'
tell application "System Events" to tell process "keepup"
    set out to ""
    repeat with e in (entire contents of (first window whose name is "Software Update"))
        try
            set out to out & (role of e) & " | " & (name of e as text) & " | " & (description of e as text) & linefeed
        on error
            set out to out & "?" & linefeed
        end try
    end repeat
    return out
end tell
END
}

menu_item() {  # choose the item of keepup's menu in the menu bar whose name starts with $1
    osascript - "$1" > /dev/null 2>&1 << 'END'
on run argv
    tell application "System Events" to tell process "keepup"
        repeat with i from (count of menu bars) to 1 by -1
            repeat with m in (menu bar items of menu bar i)
                try
                    click m
                    delay 1
                    click (first menu item of menu 1 of m whose name starts with (item 1 of argv))
                    return
                on error
                    key code 53 -- Escape: close whatever opened
                end try
            end repeat
        end repeat
    end tell
    error "no such menu item"
end run
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

fresh() {  # build A as on a Mac that has never run keepup, opened. $1: seconds until its next update check (0: at
    # launch); $2: "ask" for Sparkle's own default, asking before it installs ("install updates automatically" is
    # on otherwise); $3: another build's zip, which is told to read the test feed
    pkill -x keepup
    pkill -x Autoupdate
    pkill -x Updater
    sleep 2
    rm -rf "$APP" "$HOME/Library/Saved Application State/$ID.savedState" "$HOME/Library/Caches/$ID"
    defaults delete "$ID" > /dev/null 2>&1
    ditto -x -k "${3:-$WORK/keepup-test-A.zip}" /Applications
    if [ -n "${3:-}" ]; then defaults write "$ID" SUFeedURL "$FEED/appcast.xml"; fi
    # the last check an hour ago less $1 seconds (an hour is the shortest time Sparkle leaves between checks)
    defaults write "$ID" SUEnableAutomaticChecks -bool YES
    if [ "${2:-}" = ask ]; then
        defaults write "$ID" SUAutomaticallyUpdate -bool NO
    else
        defaults write "$ID" SUAutomaticallyUpdate -bool YES
    fi
    defaults write "$ID" SUHasLaunchedBefore -bool YES
    defaults write "$ID" SUScheduledCheckInterval -int 3600
    defaults write "$ID" SULastCheckTime -date "$(date -u -v-3600S -v+"$1"S '+%Y-%m-%d %H:%M:%S +0000')"
    STARTED="$(date '+%Y-%m-%d %H:%M:%S')"
    rm -f "$OUT/ax.txt"
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
        sleep 20  # Setup, when it opens itself, comes a few seconds after launch
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
            sleep 20
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
            sleep 20
            check "it came back in the menu bar only, with no window" menu_bar_only
        fi
    fi
    shot 3-updated
fi

say "4. Opened from its disk image, keepup copies itself to Applications and opens from there"
pkill -x keepup
sleep 2
rm -rf "$APP" "$HOME/Library/Saved Application State/$ID.savedState"
defaults delete "$ID" > /dev/null 2>&1
defaults write "$ID" SUEnableAutomaticChecks -bool NO  # no update in this one
mkdir "$WORK/image"
ditto "$WORK/A/keepup.app" "$WORK/image/keepup.app"
hdiutil create -quiet -volname keepup -srcfolder "$WORK/image" -fs HFS+ -format UDZO "$WORK/keepup.dmg"
hdiutil attach -quiet -nobrowse "$WORK/keepup.dmg"
open /Volumes/keepup/keepup.app
if wait_for 60 "keepup opens from the disk image" running; then
    image="$(field pid)"
    sleep 6  # its question comes up
    shot 4-question
    answer_question "Copy to Applications and Open"
    if wait_for 60 "it copied itself to Applications and is running from there" running_from_applications; then
        check "the copy on the disk image has quit" [ "$(field pid)" != "$image" ]
        if wait_for 60 "it opens with a window, in the Dock" in_dock; then
            sleep 8  # Setup opens too
            check "a quit leaves it in the menu bar" quit_stays
        fi
    fi
    shot 4-moved
fi
pkill -x keepup
hdiutil detach -quiet /Volumes/keepup

say "5. Asked first (Sparkle's default): Install Update, then Install and Relaunch"
fresh 0 ask
if wait_for 60 "keepup opens with a window, in the Dock" in_dock; then
    first="$(field pid)"
    if wait_for 120 "Sparkle offers build $NEW" sparkle_window; then
        shot 5-offered
        sparkle_ax 5-sparkle-ax.txt
        wait_for 240 "Install Update, then Install and Relaunch: build $NEW installed and keepup opened again" \
            installs_through_sparkle "$first"
    fi
    shot 5-updated
fi

say "6. What testers have: the published keepup 0.1.1 updates itself to this build"
if curl -fsSL -o "$WORK/keepup-0.1.1.zip" "https://github.com/$GITHUB_REPOSITORY/releases/download/v0.1.1/keepup-0.1.1.zip"; then
    fresh 0 ask "$WORK/keepup-0.1.1.zip"
    check "0.1.1 is installed" [ "$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")" = 0.1.1 ]
    if wait_for 60 "keepup 0.1.1 is running" running; then
        first="$(field pid)"
        if wait_for 120 "Sparkle offers build $NEW" sparkle_window; then
            shot 6-offered
            if wait_for 240 "Install Update, then Install and Relaunch: build $NEW installed and keepup opened again" \
                installs_through_sparkle "$first"; then
                if wait_for 60 "it opens with a window, in the Dock" in_dock; then
                    sleep 8
                    check "and now a quit leaves it in the menu bar" quit_stays
                fi
            fi
        fi
        shot 6-updated
    fi
else
    fail "couldn't download keepup 0.1.1"
fi

say "7. Asked first, with keepup in the menu bar: the update waits in keepup's menu, not in a window behind other apps"
fresh 50 ask
if wait_for 60 "keepup opens with a window, in the Dock" in_dock; then
    first="$(field pid)"
    sleep 8  # Setup opens too
    "$WORK/probe" quit
    wait_for 20 "a quit leaves it in the menu bar" same_in_menu_bar "$first"
    if wait_for 180 "the daily check found build $NEW, and keepup's menu offers it" logged "is offered in the menu"; then
        sleep 3
        check "no window opened for it" same_in_menu_bar "$first"
        if menu_item "Update to keepup"; then
            if wait_for 60 "choosing it brings Sparkle's window to the front" sparkle_in_front; then
                shot 7-offered
                wait_for 240 "Install Update, then Install and Relaunch: build $NEW installed and keepup opened again" \
                    installs_through_sparkle "$first"
            fi
        else
            fail "couldn't choose Update to keepup… in keepup's menu"
        fi
    fi
    shot 7-updated
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
