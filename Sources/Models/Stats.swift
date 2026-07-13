import Foundation

/// Pure analysis over a play — presence grid, doubling, through-line, counts.
/// Mirrors the web app's model.ts; fully unit-tested.
@MainActor
enum Stats {
    static func countWords(_ s: String?) -> Int {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return 0 }
        return t.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).count
    }

    struct ElementStats { var speakerIDs: [String]; var lines: Int; var words: Int; var runtimeMinutes: Double }

    static func elementStats(_ els: [Element]) -> ElementStats {
        var speakers: [String] = []; var lines = 0; var words = 0; var stageDirs = 0
        for e in els {
            switch e.kind {
            case .cue:
                lines += 1; words += countWords(e.text)
                if let cid = e.characterID, !speakers.contains(cid) { speakers.append(cid) }
            case .stage: stageDirs += 1
            default: break
            }
        }
        return ElementStats(speakerIDs: speakers, lines: lines, words: words,
                            runtimeMinutes: Double(words) / 140 + Double(stageDirs) * 0.08)
    }

    // MARK: Presence grid

    struct Segment { var sceneLabel: String?; var setting: String?; var speakerIDs: Set<String> }

    static func presenceGrid(_ play: Play) -> [Segment] {
        var segs: [Segment] = []
        var cur = Segment(sceneLabel: nil, setting: nil, speakerIDs: [])
        var started = false
        for el in play.elementList {
            if el.kind == .scene {
                if started || !cur.speakerIDs.isEmpty { segs.append(cur) }
                cur = Segment(sceneLabel: el.label, setting: el.setting, speakerIDs: [])
                started = true
            } else if el.kind == .cue, let cid = el.characterID {
                cur.speakerIDs.insert(cid)
            }
        }
        if started || !cur.speakerIDs.isEmpty { segs.append(cur) }
        return segs
    }

    /// Only the segments that are actual scenes (the grid columns).
    static func scenes(_ play: Play) -> [Segment] { presenceGrid(play).filter { $0.sceneLabel != nil } }

    // MARK: Cast stats

    struct CastStat { var character: Character; var lines: Int; var words: Int; var scenes: Int }
    struct PlayTotals { var totalLines: Int; var spokenWords: Int; var sceneCount: Int; var actCount: Int; var runtimeMinutes: Double }

    static func castStats(_ play: Play) -> (perCharacter: [CastStat], totals: PlayTotals) {
        let grid = presenceGrid(play)
        var scenesByChar: [String: Int] = [:]
        for seg in grid { for cid in seg.speakerIDs { scenesByChar[cid, default: 0] += 1 } }

        var per: [CastStat] = []
        for c in play.characterList {
            var lines = 0; var words = 0
            for el in play.elementList where el.kind == .cue && el.characterID == c.id.uuidString {
                lines += 1; words += countWords(el.text)
            }
            per.append(CastStat(character: c, lines: lines, words: words, scenes: scenesByChar[c.id.uuidString] ?? 0))
        }
        let totalLines = per.reduce(0) { $0 + $1.lines }
        let spokenWords = per.reduce(0) { $0 + $1.words }
        let sceneCount = play.elementList.filter { $0.kind == .scene }.count
        let actCount = play.elementList.filter { $0.kind == .act }.count
        let stageDirs = play.elementList.filter { $0.kind == .stage }.count
        let runtime = Double(spokenWords) / 140 + Double(stageDirs) * 0.08
        return (per, PlayTotals(totalLines: totalLines, spokenWords: spokenWords,
                                sceneCount: sceneCount, actCount: actCount, runtimeMinutes: runtime))
    }

    static func formatRuntime(_ minutes: Double, _ lang: Lang) -> String {
        if minutes < 0.5 { return lang == .fr ? "moins d'une minute" : "under a minute" }
        let total = Int(minutes.rounded())
        let h = total / 60, m = total % 60
        if h == 0 { return "~\(m) min" }
        return lang == .fr ? "~\(h) h \(String(format: "%02d", m))" : "~\(h)h\(String(format: "%02d", m))"
    }

    // MARK: Doubling — roles that never share a scene can be played by one actor.

    static func doubling(_ play: Play) -> [[String]] {
        let scenes = presenceGrid(play).filter { !$0.speakerIDs.isEmpty }
        var conflict: [String: Set<String>] = [:]
        for c in play.characterList { conflict[c.id.uuidString] = [] }
        for seg in scenes {
            let ids = Array(seg.speakerIDs)
            for i in 0..<ids.count { for j in (i + 1)..<ids.count {
                conflict[ids[i]]?.insert(ids[j]); conflict[ids[j]]?.insert(ids[i])
            } }
        }
        var busy: [String: Int] = [:]
        for seg in scenes { for id in seg.speakerIDs { busy[id, default: 0] += 1 } }
        let order = play.characterList
            .filter { (busy[$0.id.uuidString] ?? 0) > 0 }
            .sorted { (busy[$0.id.uuidString] ?? 0) > (busy[$1.id.uuidString] ?? 0) }
            .map { $0.id.uuidString }

        var groups: [[String]] = []
        for id in order {
            if let gi = groups.firstIndex(where: { g in g.allSatisfy { !(conflict[id]?.contains($0) ?? false) } }) {
                groups[gi].append(id)
            } else {
                groups.append([id])
            }
        }
        return groups
    }

    // MARK: Through-line — line count per character per scene.

    struct ThroughLine { var character: Character; var perScene: [Int]; var maxCount: Int }

    static func throughLines(_ play: Play) -> (sceneLabels: [String], lines: [ThroughLine]) {
        // Build ordered scene segments with their element ranges.
        let arr = play.elementList
        var sceneRanges: [(label: String, range: Range<Int>)] = []
        var i = 0
        while i < arr.count {
            if arr[i].kind == .scene {
                var end = arr.count
                for j in (i + 1)..<arr.count where arr[j].kind == .scene { end = j; break }
                sceneRanges.append((arr[i].label ?? "", i..<end))
                i = end
            } else { i += 1 }
        }
        let lines = play.characterList.map { c -> ThroughLine in
            var counts = [Int](repeating: 0, count: sceneRanges.count)
            for (si, sr) in sceneRanges.enumerated() {
                for k in sr.range where arr[k].kind == .cue && arr[k].characterID == c.id.uuidString { counts[si] += 1 }
            }
            return ThroughLine(character: c, perScene: counts, maxCount: counts.max() ?? 0)
        }
        return (sceneRanges.map(\.label), lines)
    }
}
