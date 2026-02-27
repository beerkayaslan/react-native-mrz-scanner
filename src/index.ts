import { requireNativeModule } from "expo-modules-core";

export interface MRZScannerNative {
  scanMRZ(): Promise<string>;
}

const MRZScannerModule = requireNativeModule<MRZScannerNative>("MRZScanner");

/**
 * Opens a full-screen camera scanner to read the MRZ (Machine Readable Zone)
 * from a passport (TD-3) or ID card (TD-1).
 *
 * @returns A promise that resolves with the raw MRZ string (lines separated by `\n`).
 * @throws `ERR_CANCELLED` if the user dismisses the scanner.
 * @throws `ERR_NO_ACTIVITY` (Android) or `ERR_UI` (iOS) if the scanner cannot be presented.
 *
 * @example
 * ```ts
 * import { scanMRZ } from "react-native-mrz-scanner";
 *
 * const mrz = await scanMRZ();
 * console.log(mrz);
 * ```
 */
export async function scanMRZ(): Promise<string> {
  return MRZScannerModule.scanMRZ();
}

export default { scanMRZ };
