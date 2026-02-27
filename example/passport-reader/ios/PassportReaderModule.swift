import ExpoModulesCore
import NFCPassportReader
import CoreNFC

public class PassportReaderModule: Module {
    private var passportReader = PassportReader()

    public func definition() -> ModuleDefinition {
        Name("PassportReader")

        /// Read passport via NFC using MRZ key components.
        /// Parameters: serialNumber, dateOfBirth (YYMMDD), dateOfExpiry (YYMMDD)
        AsyncFunction("readPassport") { (serialNumber: String, dateOfBirth: String, dateOfExpiry: String, promise: Promise) in
            Task { @MainActor in
                await self.performRead(
                    serialNumber: serialNumber,
                    dateOfBirth: dateOfBirth,
                    dateOfExpiry: dateOfExpiry,
                    promise: promise
                )
            }
        }

        /// Check if NFC is available on device
        Function("isNFCSupported") { () -> Bool in
            return NFCTagReaderSession.readingAvailable
        }
    }

    @MainActor
    private func performRead(
        serialNumber: String,
        dateOfBirth: String,
        dateOfExpiry: String,
        promise: Promise
    ) async {
        let normalizedSerialNumber = normalizeDocumentNumber(serialNumber)
        let normalizedDateOfBirth = normalizeDate(dateOfBirth)
        let normalizedDateOfExpiry = normalizeDate(dateOfExpiry)

        guard normalizedSerialNumber.count >= 6,
              normalizedDateOfBirth.count == 6,
              normalizedDateOfExpiry.count == 6 else {
            promise.reject("ERR_MRZ", "MRZ alanları geçersiz. Lütfen belgeyi tekrar tarayın.")
            return
        }

        // Build MRZ key (BAC key)
        let mrzKey = buildMRZKey(
            passportNumber: normalizedSerialNumber,
            dateOfBirth: normalizedDateOfBirth,
            dateOfExpiry: normalizedDateOfExpiry
        )

        // Load CSCA master list
        guard let masterListURL = resolveMasterListURL() else {
            promise.reject("ERR_CERT", "NFC sertifika dosyası (bundle.pem) bulunamadı.")
            return
        }

        passportReader.setMasterListURL(masterListURL)

        let customMessageHandler: (NFCViewDisplayMessage) -> String? = { message in
            switch message {
            case .requestPresentPassport:
                return "Lütfen NFC destekli kimliği telefonunuza yaklaştırın."
            case .readingDataGroupProgress(let id, let progress):
                return "Veri grubu \(id) okunuyor... %\(Int(progress * 100))"
            case .activeAuthentication:
                return "Kimlik doğrulanıyor..."
            case .authenticatingWithPassport:
                return "Kimlik doğrulaması yapılıyor..."
            case .successfulRead:
                return "Okuma başarılı"
            default:
                return nil
            }
        }

        do {
            let dataGroups: [DataGroupId] = [.COM, .SOD, .DG1, .DG2, .DG7, .DG11, .DG12, .DG14]
            let passport = try await passportReader.readPassport(
                mrzKey: mrzKey,
                tags: dataGroups,
                useExtendedMode: true,
                customDisplayMessage: customMessageHandler
            )

            let result = buildResult(passport: passport, serialNumber: normalizedSerialNumber)
            promise.resolve(result)
        } catch {
            promise.reject("ERR_NFC", error.localizedDescription)
        }
    }

    private func buildResult(passport: NFCPassportModel, serialNumber: String) -> [String: Any] {
        let firstName = clean(passport.firstName)
        let lastName = clean(passport.lastName)
        let gender = clean(passport.gender)
        let nationality = clean(passport.nationality)
        let documentNumber = clean(passport.documentNumber)
        let dateOfBirth = clean(passport.dateOfBirth)
        let expiryDate = clean(passport.documentExpiryDate)
        let activeAuth = passport.activeAuthenticationPassed
        let passiveAuth = passport.passportCorrectlySigned

        let readGroups = passport.dataGroupsRead.keys
            .map { String($0.rawValue) }
            .sorted()

        return [
            "firstName": firstName,
            "lastName": lastName,
            "gender": gender,
            "nationality": nationality,
            "documentNumber": documentNumber,
            "serialNumber": serialNumber,
            "dateOfBirth": dateOfBirth,
            "expiryDate": expiryDate,
            "activeAuthentication": activeAuth,
            "passiveAuthentication": passiveAuth,
            "nfcDataGroups": readGroups,
            "isVerified": activeAuth || passiveAuth,
        ]
    }

    private func clean(_ value: String) -> String {
        let normalized = value
            .replacingOccurrences(of: "<", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized == "?" ? "" : normalized
    }

    // ICAO 9303 BAC key derivation
    private func buildMRZKey(passportNumber: String, dateOfBirth: String, dateOfExpiry: String) -> String {
        func pad(_ value: String, length: Int) -> String {
            var s = value
            while s.count < length { s += "<" }
            return String(s.prefix(length))
        }

        func checksum(_ str: String) -> Int {
            let weights = [7, 3, 1]
            let chars = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ<"
            var sum = 0
            for (i, ch) in str.enumerated() {
                let value: Int
                if let idx = chars.firstIndex(of: ch) {
                    value = chars.distance(from: chars.startIndex, to: idx)
                } else {
                    value = 0
                }
                sum += value * weights[i % 3]
            }
            return sum % 10
        }

        let pptNr = pad(passportNumber, length: 9)
        let dob = pad(dateOfBirth, length: 6)
        let exp = pad(dateOfExpiry, length: 6)

        let pptNrChk = checksum(pptNr)
        let dobChk = checksum(dob)
        let expChk = checksum(exp)

        return "\(pptNr)\(pptNrChk)\(dob)\(dobChk)\(exp)\(expChk)"
    }

    private func resolveMasterListURL() -> URL? {
        if let url = Bundle.main.url(forResource: "bundle", withExtension: "pem") {
            return url
        }

        let moduleBundle = Bundle(for: PassportReaderModule.self)
        if let url = moduleBundle.url(forResource: "bundle", withExtension: "pem") {
            return url
        }

        for bundle in Bundle.allBundles + Bundle.allFrameworks {
            if let url = bundle.url(forResource: "bundle", withExtension: "pem") {
                return url
            }
        }

        return nil
    }

    private func normalizeDocumentNumber(_ value: String) -> String {
        return value
            .uppercased()
            .filter { $0.isLetter || $0.isNumber || $0 == "<" }
            .replacingOccurrences(of: "<", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeDate(_ value: String) -> String {
        var normalized = value
            .uppercased()
            .filter { $0.isLetter || $0.isNumber || $0 == "<" }

        let substitutions: [Character: Character] = [
            "O": "0",
            "I": "1",
            "B": "8",
            "S": "5",
            "Z": "2"
        ]

        normalized = String(normalized.map { substitutions[$0] ?? $0 })
        if normalized.count >= 6 {
            return String(normalized.prefix(6))
        }

        return normalized + String(repeating: "<", count: 6 - normalized.count)
    }
}
