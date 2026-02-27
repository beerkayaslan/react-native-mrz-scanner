package com.documentaccept.rn.mrzscanner

import android.app.Activity
import android.content.Intent
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition
import expo.modules.kotlin.Promise

class MRZScannerModule : Module() {
    companion object {
        private const val REQUEST_CODE_SCAN = 9101
        const val EXTRA_MRZ_RESULT = "mrz_result"
        const val EXTRA_ERROR = "mrz_error"
    }

    private var pendingPromise: Promise? = null

    override fun definition() = ModuleDefinition {
        Name("MRZScanner")

        AsyncFunction("scanMRZ") { promise: Promise ->
            val activity = appContext.activityProvider?.currentActivity
            if (activity == null) {
                promise.reject("ERR_NO_ACTIVITY", "Activity bulunamadı.", null)
                return@AsyncFunction
            }

            pendingPromise = promise

            val intent = Intent(activity, MRZScannerActivity::class.java)
            activity.startActivityForResult(intent, REQUEST_CODE_SCAN)
        }

        OnActivityResult { _, payload ->
            val promise = pendingPromise ?: return@OnActivityResult
            pendingPromise = null

            val resultCode = payload.resultCode
            val data = payload.data

            if (resultCode == Activity.RESULT_OK && data != null) {
                val mrz = data.getStringExtra(EXTRA_MRZ_RESULT)
                if (!mrz.isNullOrEmpty()) {
                    promise.resolve(mrz)
                } else {
                    promise.reject("ERR_MRZ", "MRZ okunamadı.", null)
                }
            } else {
                val error = data?.getStringExtra(EXTRA_ERROR)
                promise.reject("ERR_CANCELLED", error ?: "MRZ tarama iptal edildi.", null)
            }
        }
    }
}
