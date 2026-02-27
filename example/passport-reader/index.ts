import { requireNativeModule } from "expo-modules-core";

export interface PassportData {
  firstName: string;
  lastName: string;
  gender: string;
  nationality: string;
  documentNumber: string;
  serialNumber: string;
  dateOfBirth: string;
  expiryDate: string;
  activeAuthentication: boolean;
  passiveAuthentication: boolean;
  nfcDataGroups: string[];
  isVerified: boolean;
  placeOfBirth?: string;
}

interface PassportReaderNative {
  readPassport(
    serialNumber: string,
    dateOfBirth: string,
    dateOfExpiry: string,
  ): Promise<PassportData>;
  isNFCSupported(): boolean;
}

const PassportReaderModule =
  requireNativeModule<PassportReaderNative>("PassportReader");

/**
 * Read passport data via NFC.
 * @param serialNumber - Document serial / passport number
 * @param dateOfBirth - Date of birth in YYMMDD format
 * @param dateOfExpiry - Date of expiry in YYMMDD format
 * @returns Passport identity data
 */
export async function readPassport(
  serialNumber: string,
  dateOfBirth: string,
  dateOfExpiry: string,
): Promise<PassportData> {
  return PassportReaderModule.readPassport(
    serialNumber,
    dateOfBirth,
    dateOfExpiry,
  );
}

/**
 * Check if NFC is available on this device.
 */
export function isNFCSupported(): boolean {
  return PassportReaderModule.isNFCSupported();
}
