# Delay of Game

Sports scores for iPhone that wait for your stream. You follow teams, say how far behind live
you're watching (YouTube TV about 30s, Peacock about 45s, or any number you pick), and every
alert, Live Activity update and on-screen score arrives that much later. They land when you
see the play, not before.

It's the iPhone side of [BrightSports](https://github.com/gi-os/BrightSports). The Light Phone app
can poll in the background and hold alerts itself; an iPhone can't, so the holding happens on
the BasilNet relay (`relay/tape.py` in the BrightSports repo), which already listens to ESPN
FastCast for every game.

```
ESPN FastCast ──> bs-relay (BasilNet) ──┬─> ntfy topics ──> Light Phones (unchanged)
                                        └─> tape.py: diff → hold per device → APNs
                                               alerts · Live Activity start/update/end
                                               GET /tape/v1/delayed  (the app's own screens)
```

- **Leagues:** NFL, MLB, NBA, NHL, MLS (plus Leagues Cup and U.S. Open Cup), WNBA, NWSL, FBS
  college football, Premier League, Champions League. All of them are on the relay's feed, so
  every followed team gets held pushes.
- **Alerts:** game start, every score (basketball: period ends and the final unless "Every
  basket" is on), end of each period, final, delays and restarts. The rules are BrightSports'
  ScoreDiff.
- **Live Activities:** started by push when a followed game begins, or by hand from a game.
  Updates are held by the same delay.
- **In the app:** live games show the relay's copy from *delay* seconds ago, marked HELD. If the
  relay has no copy, the score is hidden rather than shown ahead of the stream.

## Build

```sh
brew install xcodegen && xcodegen generate && open TapeDelay.xcodeproj
```

CI works the same as NDPass and XA: `check.yml` on every branch, a push to `main` ships to
TestFlight through fastlane match, and **on the 1st of every month `main` is rebuilt as-is** so
a TestFlight build never expires (they last 90 days). The workflow re-enables its own schedule
on each run, because GitHub turns off schedules in repos that go 60 days without a commit.

## One-time setup

1. **App Store Connect:** My Apps → + → New App, bundle ID `com.gios.tapedelay`, name *Tape
   Delay*. This is the one step the API can't do; the first TestFlight run stops and says so.
2. **APNs key:** developer.apple.com → Keys → + → Apple Push Notifications service. Put the
   `.p8` at `/volume1/docker/brightsports-relay/tape-data/apns.p8` on BasilNet, add
   `APNS_KEY_ID=…` and `APNS_TEAM_ID=…` to that folder's `.env`, then
   `docker compose up -d relay`. Until then the relay runs dry and logs what it would send.

Push Notifications is turned on for the app ID by the Fastfile, and the profile is remade when it
does.
