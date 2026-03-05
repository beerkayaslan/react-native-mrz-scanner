import { requireNativeModule } from "expo-modules-core";

export interface MRZScannerOptions {
  /**
   * Custom instruction text displayed on the scanner overlay.
   * @default "Kimliğinizin arka yüzünü çerçeveye yerleştirin"
   */
  instructionText?: string;

  /**
   * Whether to show the chip icon on the scanner overlay.
   * @default true
   */
  isChipShow?: boolean;
}

export interface MRZScannerNative {
  scanMRZ(options?: MRZScannerOptions): Promise<string>;
}

const MRZScannerModule = requireNativeModule<MRZScannerNative>("MRZScanner");

/**
 * Opens a full-screen camera scanner to read the MRZ (Machine Readable Zone)
 * from a passport (TD-3) or ID card (TD-1).
 *
 * The scanner displays a card-shaped overlay with a chip icon and corner
 * brackets so the user knows to present the **back** of the document.
 *
 * @param options - Optional configuration for the scanner
 * @param options.instructionText - Custom instruction text displayed on the overlay
 * @returns A promise that resolves with the raw MRZ string (lines separated by `\n`).
 * @throws `ERR_CANCELLED` if the user dismisses the scanner.
 * @throws `ERR_NO_ACTIVITY` (Android) or `ERR_UI` (iOS) if the scanner cannot be presented.
 *
 * @example
 * ```ts
 * import { scanMRZ } from "rn-mrz-scanner";
 *
 * const mrz = await scanMRZ();
 * // or with custom text
 * const mrz = await scanMRZ({ instructionText: "Show the back of your ID" });
 * console.log(mrz);
 * ```
 */
export async function scanMRZ(options?: MRZScannerOptions): Promise<string> {
  return MRZScannerModule.scanMRZ(options ?? {});
}

export default { scanMRZ };
