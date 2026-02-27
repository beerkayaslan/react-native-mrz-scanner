import Foundation

var captureFirst = ""
var captureSecond = ""
var captureThird = ""
var mrz = ""
var temp_mrz = ""

extension String {
    private func normalizedMRZLine(to targetLength: Int) -> String {
        let s = self.stripped
        if s.count == targetLength { return s }
        if s.count < targetLength {
            return s + String(repeating: "<", count: targetLength - s.count)
        }
        return String(s.prefix(targetLength))
    }

    func checkMrz() -> String? {
        mrz = ""
        let candidate = self
            .uppercased()
            .replacingOccurrences(of: " ", with: "<")
            .filter { "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789<".contains($0) }

        let tdOneFirstRegex = "(I|C|A).[A-Z0<]{3}[A-Z0-9]{1,9}<?[0-9O]{1}[A-Z0-9<]{14,22}"
        let tdOneSecondRegex = "[0-9O]{7}(M|F|<)[0-9O]{7}[A-Z0<]{3}[A-Z0-9<]{11}[0-9O]"
        let tdOneThirdRegex = "([A-Z0]+<)+<([A-Z0]+<)+<+"
        let tdOneMrzRegex = "(I|C|A).[A-Z0<]{3}[A-Z0-9]{1,9}<?[0-9O]{1}[A-Z0-9<]{14,22}\\n[0-9O]{7}(M|F|<)[0-9O]{7}[A-Z0<]{3}[A-Z0-9<]{11}[0-9O]\\n([A-Z0]+<)+<([A-Z0]+<)+<+"

        let tdThreeFirstRegex = "P.[A-Z0<]{3}([A-Z0]+<)+<([A-Z0]+<)+<+"
        let tdThreeSecondRegex = "[A-Z0-9]{1,9}<?[0-9O]{1}[A-Z0<]{3}[0-9]{7}(M|F|<)[0-9O]{7}[A-Z0-9<]+"
        let tdThreeMrzRegex = "P.[A-Z0<]{3}([A-Z0]+<)+<([A-Z0]+<)+<+\\n[A-Z0-9]{1,9}<?[0-9O]{1}[A-Z0<]{3}[0-9]{7}(M|F|<)[0-9O]{7}[A-Z0-9<]+"

        let regexOpts: String.CompareOptions = [.regularExpression, .caseInsensitive]

        let tdOneFirstLine = candidate.range(of: tdOneFirstRegex, options: regexOpts, range: nil, locale: nil)
        let tdOneSecondLine = candidate.range(of: tdOneSecondRegex, options: regexOpts, range: nil, locale: nil)
        let tdOneThirdLine = candidate.range(of: tdOneThirdRegex, options: regexOpts, range: nil, locale: nil)

        let tdThreeFirstLine = candidate.range(of: tdThreeFirstRegex, options: regexOpts, range: nil, locale: nil)
        let tdThreeSeconddLine = candidate.range(of: tdThreeSecondRegex, options: regexOpts, range: nil, locale: nil)

        if tdOneFirstLine != nil, candidate.count >= 25 && candidate.count <= 36 {
            captureFirst = candidate.normalizedMRZLine(to: 30)
        }
        if tdOneSecondLine != nil, candidate.count >= 25 && candidate.count <= 36 {
            captureSecond = candidate.normalizedMRZLine(to: 30)
        }
        if tdOneThirdLine != nil, candidate.count >= 25 && candidate.count <= 36 {
            captureThird = candidate.normalizedMRZLine(to: 30)
        }

        if tdThreeFirstLine != nil, candidate.count >= 38 && candidate.count <= 50 {
            captureFirst = candidate.normalizedMRZLine(to: 44)
        }
        if tdThreeSeconddLine != nil, candidate.count >= 38 && candidate.count <= 50 {
            captureSecond = candidate.normalizedMRZLine(to: 44)
        }

        if captureFirst.count == 30 && captureSecond.count == 30 && captureThird.count == 30 {
            temp_mrz = (captureFirst.stripped + "\n" + captureSecond.stripped + "\n" + captureThird.stripped).replacingOccurrences(of: " ", with: "<")
            let checkMrz = temp_mrz.range(of: tdOneMrzRegex, options: regexOpts, range: nil, locale: nil)
            if checkMrz != nil {
                mrz = temp_mrz
            } else {
                mrz = temp_mrz
            }
        }

        if captureFirst.count == 44 && captureSecond.count == 44 {
            temp_mrz = (captureFirst.stripped + "\n" + captureSecond.stripped).replacingOccurrences(of: " ", with: "<")
            let checkMrz = temp_mrz.range(of: tdThreeMrzRegex, options: regexOpts, range: nil, locale: nil)
            if checkMrz != nil {
                mrz = temp_mrz
            } else {
                mrz = temp_mrz
            }
        }

        if mrz == "" {
            return nil
        }
        return mrz
    }

    var stripped: String {
        let okayChars = Set("ABCDEFGHIJKLKMNOPQRSTUVWXYZ1234567890<")
        return self.filter { okayChars.contains($0) }
    }
}

class StringTracker {
    var frameIndex: Int64 = 0
    typealias StringObservation = (lastSeen: Int64, count: Int64)

    var seenStrings = [String: StringObservation]()
    var bestCount = Int64(0)
    var bestString = ""

    func logFrame(strings: [String]) {
        for string in strings {
            if seenStrings[string] == nil {
                seenStrings[string] = (lastSeen: Int64(0), count: Int64(-1))
            }
            seenStrings[string]?.lastSeen = frameIndex
            seenStrings[string]?.count += 1
        }

        var obsoleteStrings = [String]()
        for (string, obs) in seenStrings {
            if obs.lastSeen < frameIndex - 30 {
                obsoleteStrings.append(string)
            }

            let count = obs.count
            if !obsoleteStrings.contains(string) && count > bestCount {
                bestCount = Int64(count)
                bestString = string
            }
        }

        for string in obsoleteStrings {
            seenStrings.removeValue(forKey: string)
        }

        frameIndex += 1
    }

    func getStableString() -> String? {
        if bestCount >= 5 {
            return bestString
        }
        return nil
    }

    func reset(string: String) {
        seenStrings.removeValue(forKey: string)
        bestCount = 0
        bestString = ""
        captureFirst = ""
        captureSecond = ""
        captureThird = ""
        mrz = ""
        temp_mrz = ""
    }
}
