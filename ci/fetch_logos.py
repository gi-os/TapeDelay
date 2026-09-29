#!/usr/bin/env python3
"""Bake every team logo into the widget at build time.

A Live Activity can't download anything while it renders, so the lock-screen scorebug reads its
logos from the widget's own bundle. This pulls them from ESPN (and MLB StatsAPI for the minors)
the same way BrightSports does, shrinks each to 120 px with `sips`, and writes Logos/<uid>.png,
the file name `LogoStore` looks up. The monthly TestFlight rebuild refreshes them.

A failed league is skipped, not fatal: the scorebug falls back to the team's letters.
"""
import json, os, re, subprocess, sys, urllib.request
from concurrent.futures import ThreadPoolExecutor

OUT = sys.argv[1] if len(sys.argv) > 1 else "Logos"
SITE = "https://site.api.espn.com/apis/site/v2/sports"
STAND = "https://site.api.espn.com/apis/v2/sports"
LEAGUES = ["football/nfl", "baseball/mlb", "basketball/nba", "hockey/nhl", "soccer/usa.1", "basketball/wnba",
           "soccer/usa.nwsl", "soccer/eng.1", "soccer/uefa.champions",
           "soccer/concacaf.leagues.cup", "soccer/usa.open"]
COLLEGE = [("football/college-football", "80"), ("football/college-football", "81")]
MILB = [11, 12, 13, 14]


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "curl/8.5", "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read()


def safe(uid):
    return "".join(c if c.isalnum() else "_" for c in uid)


def espn_teams(path):
    doc = json.loads(get(f"{SITE}/{path}/teams?limit=1000"))
    teams = ((doc.get("sports") or [{}])[0].get("leagues") or [{}])[0].get("teams") or []
    for w in teams:
        t = w.get("team") or {}
        logos = t.get("logos") or []
        href = next((l.get("href") for l in logos if "default" in (l.get("rel") or [])), None) \
            or (logos[0].get("href") if logos else None)
        if t.get("uid") and href:
            yield t["uid"], href


def college(path, group):
    # teams?groups= is ignored by ESPN; the standings tree carries the right teams.
    doc = json.loads(get(f"{STAND}/{path}/standings?level=3&group={group}"))
    def walk(n):
        for e in ((n.get("standings") or {}).get("entries") or []):
            t = e.get("team") or {}
            logos = t.get("logos") or []
            if t.get("uid") and logos:
                yield t["uid"], logos[0]["href"]
        for c in n.get("children") or []:
            yield from walk(c)
    yield from walk(doc)


def milb(sport_id):
    doc = json.loads(get(f"https://statsapi.mlb.com/api/v1/teams?sportId={sport_id}"))
    for t in doc.get("teams") or []:
        yield f"milb:{t['id']}", f"https://midfield.mlbstatic.com/v1/team/{t['id']}/spots/128"


def save(item):
    uid, url = item
    dst = os.path.join(OUT, safe(uid) + ".png")
    if os.path.exists(dst):
        return True
    try:
        data = get(url)
    except Exception:
        return False
    tmp = dst + ".src"
    open(tmp, "wb").write(data)
    try:
        subprocess.run(["sips", "-s", "format", "png", "-Z", "120", tmp, "--out", dst],
                       check=True, capture_output=True)
    except (FileNotFoundError, subprocess.CalledProcessError):
        os.replace(tmp, dst)   # not on macOS: keep the original
    if os.path.exists(tmp):
        os.remove(tmp)
    return True


def main():
    os.makedirs(OUT, exist_ok=True)
    items = {}
    sources = [(espn_teams, (p,)) for p in LEAGUES] + [(college, c) for c in COLLEGE] + [(milb, (s,)) for s in MILB]
    for fn, args in sources:
        try:
            for uid, href in fn(*args):
                items.setdefault(uid, href)
        except Exception as e:
            print(f"skip {fn.__name__}{args}: {e}", file=sys.stderr)
    with ThreadPoolExecutor(16) as pool:
        ok = sum(pool.map(save, items.items()))
    size = sum(os.path.getsize(os.path.join(OUT, f)) for f in os.listdir(OUT))
    print(f"logos: {ok}/{len(items)} saved, {size // 1024} KB")


if __name__ == "__main__":
    main()
