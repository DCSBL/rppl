<p align="center">
  <img src="assets/rppl.svg" alt="Rppl" width="140">
</p>

<h1 align="center">Rppl</h1>

<p align="center">
  <img src="https://img.shields.io/badge/iOS-26%2B-black?logo=apple&logoColor=white" alt="iOS 26+">
  <img src="https://img.shields.io/badge/watchOS-26%2B-black?logo=apple&logoColor=white" alt="watchOS 26+">
  <img src="https://img.shields.io/badge/privacy-on%20device-0B6E4F" alt="Privacy: on device">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-PolyForm%20NC-blue" alt="PolyForm Noncommercial"></a>
</p>

<p align="center"><strong>Cable-park wakeboarding, recorded on Apple Watch.</strong><br>
Automatic set and rest detection. Saved to Apple Health. No cloud. No subscription.</p>

## What Rppl does

Rppl is a native iPhone and Apple Watch app for cable-park sessions. You start on the Watch; it records GPS, motion, and heart rate for the whole park day as one continuous workout, and detects when you are riding versus waiting at the dock, swimming, or walking back. No Watch? Add a session by hand on iPhone.

Sessions are written through **HealthKit**, so they show up in the Fitness and Health apps like other workouts. Water Lock turns on when you start. After you stop, the Watch syncs to your iPhone, where you can browse sessions and see your route on a map.

There is no account and no Rppl server. Your data stays on your devices (and in Apple Health / your backups when those are enabled).

**Needs:** iPhone · iOS 26+. Apple Watch (watchOS 26+) is recommended: it records your sessions for you.

## A note from the developer

Hi! My name is Duco. Since this year I’ve often been at a cable park to wakeboard. The regular Apple Workout app is too basic, so I went looking for a better tracker. What I found was either too complex, too limited, full of subscriptions, or hungry for my data. That had to be different.

My background is embedded software, so iOS is new territory. This app was built almost entirely with AI help. After several test sessions I dare to make it public, in the hope that others get something out of it.

I hope that, like me, you enjoy tracking your sessions!

-- Duco

(Dutch original in [LEGAL.md](LEGAL.md).)

## What to expect

- **One session per park day.** Start and stop on the Watch. Use Pause when you truly step away; that freezes timers and stops sensors until you resume.
- **Set detection is automatic.** The Watch marks riding, rest, and unsure stretches from sensors. You do not label sets by hand.
- **HealthKit is part of the product.** Workouts, heart rate, and energy land in Apple Health when you allow access.
- **iPhone is for looking back.** After sync, browse sessions and maps on the phone, or add a session by hand. Recording stays on the Watch.
- **Ultra Action Button (optional):** Settings → Action Button → Workout → Rppl starts a session.

## Privacy & license

Hobby project from the Netherlands. No Rppl cloud. Phone logbook can live in your iCloud Drive Documents when sync is on (default). We do not sell your data.

| Doc | Role |
|-----|------|
| [LEGAL.md](LEGAL.md) | Terms & Privacy (also in the iPhone app under Legal) |
| [LICENSE](LICENSE) | Source: PolyForm Noncommercial (noncommercial use only) |

Questions: [rppl@dcsbl.nl](mailto:rppl@dcsbl.nl).

## Contribute

Bugs or ideas: [open an issue](https://github.com/DCSBL/rppl/issues). Code changes: open a pull request.

How we work, what we accept, and where the docs live: [CONTRIBUTING.md](CONTRIBUTING.md).
