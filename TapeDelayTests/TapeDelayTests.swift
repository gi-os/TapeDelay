import XCTest
import UIKit
@testable import TapeDelay

final class ParserTests: XCTestCase {
    private func event(state: String = "in", name: String = "STATUS_IN_PROGRESS", home: Any = "14", away: Any = "7",
                       date: String = "2026-09-28T17:00Z") -> [String: Any] {
        [
            "id": "401", "uid": "s:20~l:28~e:401", "date": date,
            "competitions": [[
                "status": ["period": 2, "type": ["state": state, "name": name, "shortDetail": "3:24 - 2nd"]],
                "competitors": [
                    ["homeAway": "home", "score": home, "winner": false,
                     "team": ["id": "26", "uid": "s:20~l:28~t:26", "abbreviation": "SEA", "shortDisplayName": "Seahawks",
                              "displayName": "Seattle Seahawks", "color": "002244", "logo": "https://a.espncdn.com/sea.png"],
                     "records": [["summary": "3-1"]], "linescores": [["value": 7.0], ["displayValue": "7"]]],
                    ["homeAway": "away", "score": away,
                     "team": ["id": "17", "uid": "s:20~l:28~t:17", "abbreviation": "NE", "shortDisplayName": "Patriots"]],
                ],
                "situation": ["possession": "26", "shortDownDistanceText": "2nd & 7", "lastPlay": ["text": "Run for 4"]],
                "broadcasts": [["names": ["CBS"]]],
            ]],
        ]
    }

    func testParsesAGame() throws {
        let g = try XCTUnwrap(ESPN.parseEvent(event(), league: "nfl"))
        XCTAssertEqual(g.state, .live)
        XCTAssertEqual(g.home.score, 14)
        XCTAssertEqual(g.away.score, 7)
        XCTAssertEqual(g.home.uid, "s:20~l:28~t:26")
        XCTAssertEqual(g.home.lines, ["7", "7"])
        XCTAssertEqual(g.home.record, "3-1")
        XCTAssertEqual(g.tv, "CBS")
        XCTAssertEqual(g.situation?.downDistance, "2nd & 7")
        XCTAssertEqual(g.situation?.lastPlay, "Run for 4")
    }

    func testTimestampsWithoutSeconds() {
        XCTAssertNotNil(ESPN.iso("2026-07-29T16:10Z"))
        XCTAssertNotNil(ESPN.iso("2026-07-29T16:10:00Z"))
    }

    func testScoreAsObjectOrNumber() throws {
        let g = try XCTUnwrap(ESPN.parseEvent(event(home: ["value": 3.0, "displayValue": "3"], away: 2), league: "nfl"))
        XCTAssertEqual(g.home.score, 3)
        XCTAssertEqual(g.away.score, 2)
    }

    func testRainDelayIsOffNotLive() throws {
        let g = try XCTUnwrap(ESPN.parseEvent(event(name: "STATUS_RAIN_DELAY"), league: "mlb"))
        XCTAssertEqual(g.state, .off)
        let p = try XCTUnwrap(ESPN.parseEvent(event(state: "post", name: "STATUS_POSTPONED"), league: "mlb"))
        XCTAssertEqual(p.state, .off)
    }

    func testStandingsTreeAnyDepth() {
        let entry: [String: Any] = ["team": ["uid": "s:1~l:10~t:10", "displayName": "New York Yankees", "abbreviation": "NYY"],
                                    "stats": [["name": "wins", "displayValue": "94"], ["name": "losses", "displayValue": "68"]]]
        let doc: [String: Any] = ["children": [["name": "AL", "children": [["name": "AL East", "standings": ["entries": [entry]]]]]]]
        let gs = ESPN.parseStandings(doc, kind: .baseball)
        XCTAssertEqual(gs.count, 1)
        XCTAssertEqual(gs[0].name, "AL East")
        XCTAssertEqual(gs[0].rows[0].values.prefix(2), ["94", "68"])
    }
}

final class HoldTests: XCTestCase {
    private var game: Game {
        ESPN.parseEvent([
            "id": "9", "date": "2026-09-28T17:00Z",
            "competitions": [["status": ["period": 3, "type": ["state": "in", "name": "STATUS_IN_PROGRESS", "shortDetail": "Q3"]],
                              "competitors": [["homeAway": "home", "score": "21", "team": ["id": "1", "uid": "h"]],
                                              ["homeAway": "away", "score": "10", "team": ["id": "2", "uid": "a"]]]]],
        ], league: "nfl")!
    }

    func testHeldCopyReplacesLiveScore() throws {
        let json = #"{"id":"9","st":"in","nm":"STATUS_IN_PROGRESS","dt":"5:00 - 2nd","p":2,"home":{"id":"1","sc":14},"away":{"id":"2","sc":10}}"#
        let s = try JSONDecoder().decode(Relay.Snapshot.self, from: Data(json.utf8))
        let g = game.holding(s)
        XCTAssertTrue(g.held)
        XCTAssertEqual(g.home.score, 14)
        XCTAssertEqual(g.detail, "5:00 - 2nd")
    }

    func testHeldBeforeKickoffShowsNoScore() throws {
        let s = try JSONDecoder().decode(Relay.Snapshot.self, from: Data(#"{"id":"9","st":"pre","held":true}"#.utf8))
        let g = game.holding(s)
        XCTAssertEqual(g.state, .pre)
        XCTAssertNil(g.home.score)
    }

    func testMaskHidesEverything() {
        let g = game.masking()
        XCTAssertTrue(g.masked)
        XCTAssertNil(g.home.score)
        XCTAssertNil(g.situation)
    }

    func testBuckets() {
        let now = ESPN.iso("2026-09-28T18:00Z")!
        var g = game
        XCTAssertEqual(Bucket.of(g, now: now), .live)
        g.state = .pre
        g = Game(id: "x", league: "nfl", date: now.addingTimeInterval(86400 * 3), state: .pre, detail: "", period: 0,
                 home: g.home, away: g.away)
        XCTAssertEqual(Bucket.of(g, now: now), .upcoming)
    }

    func testDelayFormat() {
        XCTAssertEqual(AppModel.format(0), "live")
        XCTAssertEqual(AppModel.format(45), "45s")
        XCTAssertEqual(AppModel.format(600), "10 min")
        XCTAssertEqual(AppModel.format(90), "1m 30s")
    }

    func testLiveActivityWireFormatMatchesRelay() throws {
        // Exactly what relay/tape.py content_state() emits for a baseball game.
        let json = #"{"home":2,"away":1,"detail":"Top 5th","state":"in","period":5,"outs":1,"balls":2,"strikes":1,"bases":[true,false,false],"lastPlay":"Single"}"#
        let s = try JSONDecoder().decode(GameAttributes.ContentState.self, from: Data(json.utf8))
        XCTAssertEqual(s.bases, [true, false, false])
        XCTAssertEqual(s.outs, 1)
    }
}

final class LogoContrastTests: XCTestCase {
    private func solid(_ c: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40)).image { ctx in
            c.setFill(); ctx.fill(CGRect(x: 8, y: 8, width: 24, height: 24))
        }
    }

    func testNavyCrestOnNavyGoesWhite() {
        let navy = UIColor(red: 12 / 255, green: 35 / 255, blue: 64 / 255, alpha: 1)
        XCTAssertTrue(LogoContrast.blends(solid(navy), on: "0c2340", key: "navy"))
    }

    func testWhiteCrestOnNavyStays() {
        XCTAssertFalse(LogoContrast.blends(solid(.white), on: "0c2340", key: "white"))
    }

    func testDarken() {
        XCTAssertEqual(LogoContrast.darken("ffffff", by: 0.5), "7f7f7f")
    }
}

final class LogoDetailTests: XCTestCase {
    func testDetailedMulticolourLogoKeepsItsColours() {
        // Four colour bands, one of them the background colour: not simple, so no silhouette.
        let img = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40)).image { ctx in
            let cs: [UIColor] = [UIColor(red: 12 / 255, green: 35 / 255, blue: 64 / 255, alpha: 1), .orange, .systemTeal, .white]
            for (i, c) in cs.enumerated() { c.setFill(); ctx.fill(CGRect(x: 0, y: i * 10, width: 40, height: 10)) }
        }
        XCTAssertFalse(LogoContrast.blends(img, on: "0c2340", key: "multi"))
    }
}
