# keepup

keepup finds the messages and email you haven't answered, across iMessage, WhatsApp, Signal, Messenger, X,
Telegram and Gmail, and tells you once or twice a day who's waiting on you. It runs on your Mac; nothing you
read or write in it goes to its makers.

**This is an early beta.** Downloads and updates live here; keepup's source code isn't public. Homepage:
[markestefanos.github.io/keepup-releases](https://markestefanos.github.io/keepup-releases/), with a
[getting-started guide](https://markestefanos.github.io/keepup-releases/guide.html).

## What you need

- A Mac with Apple silicon, on macOS 15 or later
- [Claude Code](https://claude.com/claude-code) with your own Claude plan: keepup's judgement (who's waiting on
  you, what's noise) comes from it. Setup helps you install it and sign in
- For email: a Gmail or Google Workspace account (other email isn't supported yet)

## Install

1. Download `keepup-<version>.dmg` from the [latest release](../../releases/latest).
2. Open it and drag keepup into Applications. Open it from there.
3. keepup's Setup window walks you through the rest (a few minutes): about you, the AI, your email accounts,
   the Mac permission it needs to read Messages and Contacts, which chat networks you use, and when your briefs
   come.

keepup lives in the menu bar and opens when you log in; leave it running in the background. It updates itself
(keepup → Check for Updates…).

## On your iPhone

keepup for iPhone is in beta on [TestFlight](https://testflight.apple.com/join/7d3kTfmV). It shows your list, sends your brief and reminders,
and has a widget, with nothing to pair: it reads your list from your own iCloud, where the Mac app puts it, as
long as both use the same iCloud account.

## Before you connect chat networks

keepup reads WhatsApp, Signal, Messenger, X and Telegram through bridges: open-source programs
([mautrix](https://github.com/mautrix)) that run on your Mac and sign in as you, the way a second device or a
browser would. They aren't official apps. The networks don't support them, and their terms don't allow unofficial
clients, so an account that uses one can be challenged, signed out, or (rarely) restricted or banned. keepup
shows each network's risk before you connect it, only reads, and never sends anything. Connect only the
networks you're comfortable with; each one is optional.

## Privacy

Your messages stay on your Mac, except what keepup sends to Claude to sort them (under your own account, and
Setup asks you to turn off "Help improve Claude" so they aren't used to train models) and, for the iPhone app,
your list in your own iCloud.
No analytics, no tracking, no account with keepup. The full [privacy policy](https://markestefanos.github.io/keepup-releases/privacy.html) says exactly what
leaves your Mac.

## Remove it

Settings → General → Remove keepup from this Mac: it unlinks the chat networks, revokes its Google access,
stops everything and moves its files to the Trash.

## Feedback

keepup → Settings → General → Send feedback (it attaches a report with no message text, which you can read
first), or [heykeepupapp@gmail.com](mailto:heykeepupapp@gmail.com).
