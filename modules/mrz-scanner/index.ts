import { requireNativeModule } from "expo-modules-core";

interface MRZScannerNative {
  scanMRZ(): Promise<string>;
}

const MRZScannerModule = requireNativeModule<MRZScannerNative>("MRZScanner");

export async function scanMRZ(): Promise<string> {
  return MRZScannerModule.scanMRZ();
}
