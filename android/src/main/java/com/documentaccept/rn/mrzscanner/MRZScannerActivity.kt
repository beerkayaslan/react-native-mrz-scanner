package com.documentaccept.rn.mrzscanner

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.os.Bundle
import android.util.Size
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.Button
import android.widget.FrameLayout
import android.widget.TextView
import androidx.annotation.OptIn
import androidx.appcompat.app.AppCompatActivity
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class MRZScannerActivity : AppCompatActivity() {

    companion object {
        private const val CAMERA_PERMISSION_CODE = 1001
    }

    private lateinit var cameraExecutor: ExecutorService
    private val textRecognizer = TextRecognition.getClient(TextRecognizerOptions.Builder().build())
    private val stringTracker = StringTracker()
    private var resultDelivered = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        MRZUtils.resetCaptures()

        // Build UI programmatically — no XML layout needed
        val root = FrameLayout(this).apply { setBackgroundColor(Color.BLACK) }

        val previewView = PreviewView(this).apply {
            layoutParams = FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT)
            implementationMode = PreviewView.ImplementationMode.COMPATIBLE
        }
        root.addView(previewView)

        // Semi-transparent overlay hint
        val hint = TextView(this).apply {
            text = "Kimliğin MRZ alanını çerçeve içine yerleştirin"
            setTextColor(Color.WHITE)
            textSize = 14f
            gravity = Gravity.CENTER
            setBackgroundColor(Color.parseColor("#66000000"))
            setPadding(24, 16, 24, 16)
            layoutParams = FrameLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                gravity = Gravity.BOTTOM
                bottomMargin = 160
            }
        }
        root.addView(hint)

        // Close button
        val closeBtn = Button(this).apply {
            text = "Kapat"
            setTextColor(Color.WHITE)
            setBackgroundColor(Color.parseColor("#66000000"))
            layoutParams = FrameLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                gravity = Gravity.TOP or Gravity.START
                topMargin = 48
                leftMargin = 24
            }
            setOnClickListener { cancelScan() }
        }
        root.addView(closeBtn)

        setContentView(root)

        cameraExecutor = Executors.newSingleThreadExecutor()

        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
            startCamera(previewView)
        } else {
            ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.CAMERA), CAMERA_PERMISSION_CODE)
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == CAMERA_PERMISSION_CODE) {
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                val previewView = (window.decorView as FrameLayout).let { root ->
                    (0 until root.childCount).map { root.getChildAt(it) }
                        .filterIsInstance<PreviewView>()
                        .firstOrNull()
                }
                // Rebuild to get the PreviewView
                if (previewView != null) {
                    startCamera(previewView)
                } else {
                    recreate()
                }
            } else {
                deliverError("Kamera izni reddedildi.")
            }
        }
    }

    @OptIn(ExperimentalGetImage::class)
    private fun startCamera(previewView: PreviewView) {
        val cameraProviderFuture = ProcessCameraProvider.getInstance(this)

        cameraProviderFuture.addListener({
            val cameraProvider = cameraProviderFuture.get()

            val preview = Preview.Builder().build().also {
                it.surfaceProvider = previewView.surfaceProvider
            }

            val imageAnalysis = ImageAnalysis.Builder()
                .setTargetResolution(Size(1920, 1080))
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .build()

            imageAnalysis.setAnalyzer(cameraExecutor) { imageProxy ->
                processImageProxy(imageProxy)
            }

            val cameraSelector = CameraSelector.DEFAULT_BACK_CAMERA

            try {
                cameraProvider.unbindAll()
                cameraProvider.bindToLifecycle(this, cameraSelector, preview, imageAnalysis)
            } catch (e: Exception) {
                deliverError("Kamera başlatılamadı: ${e.message}")
            }
        }, ContextCompat.getMainExecutor(this))
    }

    @ExperimentalGetImage
    private fun processImageProxy(imageProxy: ImageProxy) {
        if (resultDelivered) {
            imageProxy.close()
            return
        }

        val mediaImage = imageProxy.image
        if (mediaImage == null) {
            imageProxy.close()
            return
        }

        val inputImage = InputImage.fromMediaImage(mediaImage, imageProxy.imageInfo.rotationDegrees)

        textRecognizer.process(inputImage)
            .addOnSuccessListener { visionText ->
                val codes = mutableListOf<String>()

                for (block in visionText.textBlocks) {
                    for (line in block.lines) {
                        val raw = line.text.replace(" ", "")
                        val filtered = raw.uppercase().filter {
                            "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789<".contains(it)
                        }
                        val result = MRZUtils.checkMrz(filtered)
                        if (result != null) {
                            codes.add(result)
                        }
                    }
                }

                stringTracker.logFrame(codes)

                val stable = stringTracker.getStableString()
                if (stable != null && !resultDelivered) {
                    resultDelivered = true
                    stringTracker.reset(stable)
                    deliverResult(stable)
                }
            }
            .addOnFailureListener { /* ignore frame errors */ }
            .addOnCompleteListener { imageProxy.close() }
    }

    private fun deliverResult(mrz: String) {
        val data = Intent().apply {
            putExtra(MRZScannerModule.EXTRA_MRZ_RESULT, mrz)
        }
        setResult(Activity.RESULT_OK, data)
        finish()
    }

    private fun deliverError(message: String) {
        val data = Intent().apply {
            putExtra(MRZScannerModule.EXTRA_ERROR, message)
        }
        setResult(Activity.RESULT_CANCELED, data)
        finish()
    }

    private fun cancelScan() {
        setResult(Activity.RESULT_CANCELED)
        finish()
    }

    override fun onDestroy() {
        super.onDestroy()
        if (::cameraExecutor.isInitialized) {
            cameraExecutor.shutdown()
        }
    }
}
