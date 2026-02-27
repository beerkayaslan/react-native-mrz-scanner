import { parse } from "mrz";

export interface MRZResult {
  documentNumber: string;
  serialNumber: string;
  dateOfBirth: string; // YYMMDD
  expiryDate: string; // YYMMDD
  firstName: string;
  lastName: string;
  nationality: string;
  gender: string;
  valid: boolean;
}

function toYYMMDD(value: string): string {
  const normalized = value.replace(/-/g, "").toUpperCase();

  // Already YYMMDD
  if (/^[0-9<]{6}$/.test(normalized)) {
    return normalized;
  }

  // YYYYMMDD -> YYMMDD
  if (/^[0-9]{8}$/.test(normalized)) {
    return normalized.substring(2);
  }

  // Fallback: keep MRZ-valid chars and fit to 6 chars
  const cleaned = normalized
    .replace(/[^0-9A-Z<]/g, "")
    .replace(/O/g, "0")
    .replace(/I/g, "1")
    .replace(/B/g, "8")
    .replace(/S/g, "5")
    .replace(/Z/g, "2");

  return cleaned.substring(0, 6).padEnd(6, "<");
}

/**
 * Normalize raw OCR text into MRZ lines.
 * Supports TD1 (3×30) and TD3 (2×44) formats.
 */
function normalizeMRZ(raw: string): string[] {
  // Keep only valid MRZ characters
  const cleaned = raw
    .toUpperCase()
    .replace(/[^A-Z0-9<\n]/g, "")
    .split("\n")
    .map((l) => l.trim())
    .filter((l) => l.length > 0);

  // TD3: 2 lines of 44 chars
  if (cleaned.length === 2 && cleaned.every((l) => l.length >= 42)) {
    return cleaned.map((l) => l.substring(0, 44).padEnd(44, "<"));
  }

  // TD1: 3 lines of 30 chars
  if (cleaned.length === 3 && cleaned.every((l) => l.length >= 28)) {
    return cleaned.map((l) => l.substring(0, 30).padEnd(30, "<"));
  }

  // Try to detect from combined string
  const combined = cleaned.join("");
  if (combined.length >= 88) {
    return [
      combined.substring(0, 44).padEnd(44, "<"),
      combined.substring(44, 88).padEnd(44, "<"),
    ];
  }
  if (combined.length >= 90) {
    return [
      combined.substring(0, 30).padEnd(30, "<"),
      combined.substring(30, 60).padEnd(30, "<"),
      combined.substring(60, 90).padEnd(30, "<"),
    ];
  }

  return cleaned;
}

/**
 * Check if a text line matches MRZ pattern (TD1 or TD3).
 */
export function isMRZLine(line: string): boolean {
  const cleaned = line.toUpperCase().replace(/[^A-Z0-9<]/g, "");
  // TD3 line: 44 chars, starts with P
  if (/^P[A-Z<][A-Z<]{42}$/.test(cleaned)) return true;
  // TD3 line 2: 44 chars starting with alphanumeric
  if (/^[A-Z0-9<]{44}$/.test(cleaned) && cleaned.includes("<")) return true;
  // TD1 line: 30 chars
  if (/^[A-Z0-9<]{28,30}$/.test(cleaned) && cleaned.includes("<")) return true;
  return false;
}

/**
 * Parse MRZ text (raw OCR output) into structured identity data.
 */
export function parseMRZ(rawText: string): MRZResult | null {
  try {
    const lines = normalizeMRZ(rawText);
    if (lines.length < 2) return null;

    const result = parse(lines);

    if (!result || !result.valid) {
      // Try with minor corrections even if not fully valid
      if (!result?.fields) return null;
    }

    const fields = result.fields;
    if (!fields.documentNumber || !fields.birthDate || !fields.expirationDate) {
      return null;
    }

    const dob = toYYMMDD(String(fields.birthDate));
    const exp = toYYMMDD(String(fields.expirationDate));
    const documentNumber = String(fields.documentNumber)
      .toUpperCase()
      .replace(/[^A-Z0-9<]/g, "")
      .replace(/</g, "")
      .trim();

    if (!documentNumber || dob.length !== 6 || exp.length !== 6) {
      return null;
    }

    return {
      documentNumber,
      serialNumber: documentNumber,
      dateOfBirth: dob,
      expiryDate: exp,
      firstName: fields.firstName || "",
      lastName: fields.lastName || "",
      nationality: fields.nationality || "",
      gender: fields.sex || "",
      valid: result.valid,
    };
  } catch (error) {
    console.warn("MRZ parse error:", error);
    return null;
  }
}
