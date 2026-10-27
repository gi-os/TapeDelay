# Delay of Game (TapeDelay)

Sports scores for iPhone that wait for your stream: alerts, Live Activities and on-screen scores
arrive as far behind live as you watch. The iPhone side of BrightSports; the holding happens on the
BasilNet relay (`relay/tape.py` in gi-os/BrightSports), which talks to this app over APNs and
`GET /tape/v1/delayed`. The house rules, pipeline and skills come from the gi-os kit, loaded at
session start (`.gios/`, read-only here).

- Code: `TapeDelay/` app (App, Data, Model, UI), `TapeDelayWidgets/` Live Activity + widgets,
  `Shared/` code both use, `TapeDelayTests/`.
- Team logos are fetched at build time by `ci/fetch_logos.py` (PREPARE in ci/app.env) into the
  gitignored `Logos/`; a Live Activity can't download them.
- Built with the iOS 27.1 SDK (`RUNNER="xcode-27"`, `XCODE="27.1"`) so the open iPhone Duo gets the
  whole inner display; keep all four orientations in project.yml or App Store Connect rejects it.
- Relay-side changes belong in gi-os/BrightSports.
