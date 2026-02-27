package com.documentaccept.rn.passportreader

import android.app.Activity
import android.app.PendingIntent
import android.content.Intent
import android.nfc.NfcAdapter
import android.nfc.Tag
import android.nfc.tech.IsoDep
import android.os.Build
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition
import expo.modules.kotlin.Promise
import kotlinx.coroutines.*
import net.sf.scuba.smartcards.CardService
import org.jmrtd.BACKey
import org.jmrtd.BACKeySpec
import org.jmrtd.PassportService
import org.jmrtd.lds.icao.*
import org.jmrtd.lds.*
import java.io.InputStream
import java.security.Security

class PassportReaderModule : Module() {
    private var nfcAdapter: NfcAdapter? = null
    private var pendingPromise: Promise? = null
    private var pendingMrzKey: BACKeySpec? = null

    override fun definition() = ModuleDefinition {
        Name("PassportReader")

        AsyncFunction("readPassport") { serialNumber: String, dateOfBirth: String, dateOfExpiry: String, promise: Promise ->
            val activity = appContext.activityProvider?.currentActivity
            if (activity == null) {
                promise.reject("ERR_NO_ACTIVITY", "Activity bulunamadı.", null)
                return@AsyncFunction
            }

            nfcAdapter = NfcAdapter.getDefaultAdapter(activity)
            if (nfcAdapter == null || !nfcAdapter!!.isEnabled) {
                promise.reject("ERR_NFC", "NFC kullanılamıyor. Lütfen NFC'yi etkinleştirin.", null)
                return@AsyncFunction
            }

            pendingPromise = promise
            pendingMrzKey = BACKey(serialNumber, dateOfBirth, dateOfExpiry)

            enableNfcForegroundDispatch(activity)
        }

        Function("isNFCSupported") {
            val activity = appContext.activityProvider?.currentActivity ?: return@Function false
            val adapter = NfcAdapter.getDefaultAdapter(activity)
            return@Function adapter != null && adapter.isEnabled
        }

        // Handle NFC intent from foreground dispatch
        OnNewIntent { intent ->
            if (NfcAdapter.ACTION_TECH_DISCOVERED == intent.action) {
                val tag: Tag? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(NfcAdapter.EXTRA_TAG, Tag::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(NfcAdapter.EXTRA_TAG)
                }
                tag?.let { handleNfcTag(it) }
            }
        }

        OnDestroy {
            val activity = appContext.activityProvider?.currentActivity
            activity?.let { disableNfcForegroundDispatch(it) }
        }
    }

    private fun enableNfcForegroundDispatch(activity: Activity) {
        val intent = Intent(activity, activity.javaClass).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_MUTABLE
        } else {
            0
        }
        val pendingIntent = PendingIntent.getActivity(activity, 0, intent, flags)
        val techList = arrayOf(arrayOf(IsoDep::class.java.name))
        nfcAdapter?.enableForegroundDispatch(activity, pendingIntent, null, techList)
    }

    private fun disableNfcForegroundDispatch(activity: Activity) {
        try {
            nfcAdapter?.disableForegroundDispatch(activity)
        } catch (_: Exception) {}
    }

    private fun handleNfcTag(tag: Tag) {
        val promise = pendingPromise ?: return
        val bacKey = pendingMrzKey ?: return
        pendingPromise = null
        pendingMrzKey = null

        val activity = appContext.activityProvider?.currentActivity
        activity?.let { disableNfcForegroundDispatch(it) }

        CoroutineScope(Dispatchers.IO).launch {
            try {
                val result = readPassportFromTag(tag, bacKey)
                withContext(Dispatchers.Main) {
                    promise.resolve(result)
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    promise.reject("ERR_NFC_READ", e.message ?: "Bilinmeyen hata", e)
                }
            }
        }
    }

    private fun readPassportFromTag(tag: Tag, bacKey: BACKeySpec): Map<String, Any?> {
        val isoDep = IsoDep.get(tag)
        isoDep.timeout = 10000

        val cardService = CardService.getInstance(isoDep)
        cardService.open()

        val passportService = PassportService(
            cardService,
            PassportService.NORMAL_MAX_TRANCEIVE_LENGTH,
            PassportService.DEFAULT_MAX_BLOCKSIZE,
            false,
            true
        )
        passportService.open()

        // BAC authentication
        passportService.sendSelectApplet(false)
        passportService.doBAC(bacKey)

        // Read DG1 (MRZ data)
        val dg1In: InputStream = passportService.getInputStream(PassportService.EF_DG1)
        val dg1 = DG1File(dg1In)
        val mrzInfo = dg1.mrzInfo

        // Read DG2 (facial image) — just verify it's readable
        var dg2Read = false
        try {
            val dg2In: InputStream = passportService.getInputStream(PassportService.EF_DG2)
            val dg2 = DG2File(dg2In)
            dg2Read = dg2.faceInfos.isNotEmpty()
        } catch (_: Exception) {}

        // Read DG11 (additional personal info)
        var placeOfBirth: String? = null
        try {
            val dg11In: InputStream = passportService.getInputStream(PassportService.EF_DG11)
            val dg11 = DG11File(dg11In)
            placeOfBirth = dg11.placeOfBirth?.joinToString(", ")
        } catch (_: Exception) {}

        val readGroups = mutableListOf("1")
        if (dg2Read) readGroups.add("2")
        if (placeOfBirth != null) readGroups.add("11")

        return mapOf(
            "firstName" to clean(mrzInfo.secondaryIdentifier),
            "lastName" to clean(mrzInfo.primaryIdentifier),
            "gender" to clean(mrzInfo.gender.toString()),
            "nationality" to clean(mrzInfo.nationality),
            "documentNumber" to clean(mrzInfo.documentNumber),
            "serialNumber" to clean(mrzInfo.documentNumber),
            "dateOfBirth" to clean(mrzInfo.dateOfBirth),
            "expiryDate" to clean(mrzInfo.dateOfExpiry),
            "placeOfBirth" to (placeOfBirth ?: ""),
            "activeAuthentication" to false,
            "passiveAuthentication" to false,
            "nfcDataGroups" to readGroups,
            "isVerified" to true,
        )
    }

    private fun clean(value: String?): String {
        if (value == null) return ""
        return value
            .replace("<", " ")
            .trim()
            .let { if (it == "?") "" else it }
    }
}
