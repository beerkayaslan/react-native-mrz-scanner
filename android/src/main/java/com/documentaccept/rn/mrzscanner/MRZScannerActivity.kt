package com.documentaccept.rn.mrzscanner

import android.Manifest
import android.animation.ObjectAnimator
import android.animation.ValueAnimator
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.*
import android.os.Bundle
import android.util.Size
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.animation.AccelerateDecelerateInterpolator
import android.widget.FrameLayout
import android.widget.ImageView
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
        const val EXTRA_INSTRUCTION_TEXT = "instructionText"
    }

    private lateinit var cameraExecutor: ExecutorService
    private val textRecognizer = TextRecognition.getClient(TextRecognizerOptions.Builder().build())
    private val stringTracker = StringTracker()
    private var resultDelivered = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        MRZUtils.resetCaptures()

        val instructionText = intent.getStringExtra(EXTRA_INSTRUCTION_TEXT)
            ?: "Kimliğinizin arka yüzünü çerçeveye yerleştirin"

        // ── Build UI ──────────────────────────────

        val root = FrameLayout(this).apply { setBackgroundColor(Color.BLACK) }

        // Camera preview
        val previewView = PreviewView(this).apply {
            layoutParams = FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT)
            implementationMode = PreviewView.ImplementationMode.COMPATIBLE
        }
        root.addView(previewView)

        // Card overlay (custom drawn view)
        val overlayView = CardOverlayView(this)
        root.addView(overlayView, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))

        // Chip icon (drawn on a separate view, positioned after layout)
        val chipView = ChipIconView(this)
        root.addView(chipView, FrameLayout.LayoutParams(dp(52), dp(40)))

        // MRZ line indicators (3 thin lines)
        val mrzLinesView = MRZLinesView(this)
        root.addView(mrzLinesView, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))

        // Scan line
        val scanLineView = View(this).apply {
            setBackgroundColor(Color.parseColor("#804DB8FF"))
        }
        root.addView(scanLineView, FrameLayout.LayoutParams(MATCH_PARENT, dp(2)))

        // Hint text
        val hintView = TextView(this).apply {
            text = instructionText
            setTextColor(Color.WHITE)
            textSize = 15f
            gravity = Gravity.CENTER
            setShadowLayer(4f, 0f, 1f, Color.parseColor("#B3000000"))
            layoutParams = FrameLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                gravity = Gravity.CENTER_HORIZONTAL
            }
        }
        root.addView(hintView)

        // Close button (circular X)
        val closeBtn = createCloseButton()
        root.addView(closeBtn)

        setContentView(root)

        // Position chip, MRZ lines, scan line and hint after layout
        root.post {
            val cardRect = overlayView.cardRect
            if (cardRect.width() > 0f) {
                // Chip position
                val chipLP = chipView.layoutParams as FrameLayout.LayoutParams
                chipLP.leftMargin = (cardRect.left + cardRect.width() * 0.07f).toInt() + dp(10)
                chipLP.topMargin = (cardRect.top + cardRect.height() * 0.22f).toInt() + dp(10)
                chipView.layoutParams = chipLP

                // MRZ lines
                val mrzInset = dp(16)
                val mrzH = (cardRect.height() * 0.28f).toInt()
                val mrzY = (cardRect.bottom - mrzH - dp(11)).toInt()
                val mrzLP = mrzLinesView.layoutParams as FrameLayout.LayoutParams
                mrzLP.width = (cardRect.width()).toInt() - 2 * mrzInset
                mrzLP.height = mrzH
                mrzLP.leftMargin = cardRect.left.toInt() + mrzInset
                mrzLP.topMargin = mrzY
                mrzLinesView.layoutParams = mrzLP

                // Scan line
                val scanLP = scanLineView.layoutParams as FrameLayout.LayoutParams
                scanLP.width = cardRect.width().toInt() - dp(16)
                scanLP.height = dp(2)
                scanLP.leftMargin = cardRect.left.toInt() + dp(8)
                scanLP.topMargin = mrzY
                scanLineView.layoutParams = scanLP

                // Animate scan line
                val animator = ObjectAnimator.ofFloat(
                    scanLineView, "translationY",
                    0f, mrzH.toFloat() - dp(2).toFloat()
                )
                animator.duration = 2000
                animator.repeatCount = ValueAnimator.INFINITE
                animator.repeatMode = ValueAnimator.REVERSE
                animator.interpolator = AccelerateDecelerateInterpolator()
                animator.start()

                // Hint text
                val hintLP = hintView.layoutParams as FrameLayout.LayoutParams
                hintLP.leftMargin = cardRect.left.toInt() - dp(10)
                hintLP.width = cardRect.width().toInt() + dp(20)
                hintLP.topMargin = cardRect.bottom.toInt() + dp(24)
                hintView.layoutParams = hintLP
            }
        }

        cameraExecutor = Executors.newSingleThreadExecutor()

        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
            startCamera(previewView)
        } else {
            ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.CAMERA), CAMERA_PERMISSION_CODE)
        }
    }

    // ── Close button ────────────────────────────────

    private fun createCloseButton(): View {
        val size = dp(36)
        val btn = FrameLayout(this).apply {
            layoutParams = FrameLayout.LayoutParams(size, size).apply {
                gravity = Gravity.TOP or Gravity.START
                topMargin = dp(48)
                leftMargin = dp(16)
            }
            setBackgroundColor(Color.TRANSPARENT)
            isClickable = true
            isFocusable = true
            setOnClickListener { cancelScan() }
        }

        // Circle background
        val bg = View(this).apply {
            layoutParams = FrameLayout.LayoutParams(size, size)
            background = createCircleDrawable(Color.parseColor("#80000000"), size)
        }
        btn.addView(bg)

        // X icon (using a simple drawn cross)
        val xIcon = XMarkView(this)
        btn.addView(xIcon, FrameLayout.LayoutParams(size, size))

        return btn
    }

    private fun createCircleDrawable(color: Int, sizePx: Int): android.graphics.drawable.Drawable {
        return object : android.graphics.drawable.Drawable() {
            private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color }
            override fun draw(canvas: Canvas) {
                val r = bounds.width() / 2f
                canvas.drawCircle(r, r, r, paint)
            }
            override fun setAlpha(alpha: Int) { paint.alpha = alpha }
            override fun setColorFilter(cf: ColorFilter?) { paint.colorFilter = cf }
            override fun getOpacity(): Int = PixelFormat.TRANSLUCENT
        }
    }

    // ── Camera ──────────────────────────────────────

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == CAMERA_PERMISSION_CODE) {
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                val root = window.decorView as FrameLayout
                val previewView = findPreviewView(root)
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

    private fun findPreviewView(parent: FrameLayout): PreviewView? {
        for (i in 0 until parent.childCount) {
            val child = parent.getChildAt(i)
            if (child is PreviewView) return child
            if (child is FrameLayout) {
                val found = findPreviewView(child)
                if (found != null) return found
            }
        }
        return null
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

    // ── Results ─────────────────────────────────────

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

    // ── Helpers ─────────────────────────────────────

    private fun dp(value: Int): Int {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            value.toFloat(),
            resources.displayMetrics
        ).toInt()
    }

    // ═══════════════════════════════════════════════
    // Inner Views
    // ═══════════════════════════════════════════════

    /**
     * Dark overlay with a card-shaped transparent cutout,
     * thin card border, and corner bracket decorations.
     */
    inner class CardOverlayView(context: Context) : View(context) {

        var cardRect = RectF()
            private set

        private val overlayPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#8C000000") // 55% black
            style = Paint.Style.FILL
        }
        private val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#59FFFFFF") // 35% white
            style = Paint.Style.STROKE
            strokeWidth = dpF(1.5f)
        }
        private val cornerPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            style = Paint.Style.STROKE
            strokeWidth = dpF(3f)
            strokeCap = Paint.Cap.ROUND
        }

        private val cr = dpF(12f) // corner radius
        private val cornerLen = dpF(28f)

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)

            val w = width.toFloat()
            val h = height.toFloat()

            // Calculate card rect
            val cardW = w * 0.88f
            val cardH = cardW / 1.586f // ID-1 aspect ratio
            val cardX = (w - cardW) / 2f
            val cardY = (h - cardH) / 2f - cardH * 0.08f
            cardRect.set(cardX, cardY, cardX + cardW, cardY + cardH)

            // Dark overlay with card hole (even-odd)
            val path = Path().apply {
                fillType = Path.FillType.EVEN_ODD
                addRect(0f, 0f, w, h, Path.Direction.CW)
                addRoundRect(cardRect, cr, cr, Path.Direction.CW)
            }
            canvas.drawPath(path, overlayPaint)

            // Card border
            canvas.drawRoundRect(cardRect, cr, cr, borderPaint)

            // Corner brackets
            drawCorners(canvas)
        }

        private fun drawCorners(canvas: Canvas) {
            val r = cardRect

            // Top-left
            val tl = Path().apply {
                moveTo(r.left, r.top + cr + cornerLen)
                lineTo(r.left, r.top + cr)
                arcTo(RectF(r.left, r.top, r.left + 2 * cr, r.top + 2 * cr), 180f, 90f, false)
                lineTo(r.left + cr + cornerLen, r.top)
            }
            canvas.drawPath(tl, cornerPaint)

            // Top-right
            val tr = Path().apply {
                moveTo(r.right - cr - cornerLen, r.top)
                lineTo(r.right - cr, r.top)
                arcTo(RectF(r.right - 2 * cr, r.top, r.right, r.top + 2 * cr), -90f, 90f, false)
                lineTo(r.right, r.top + cr + cornerLen)
            }
            canvas.drawPath(tr, cornerPaint)

            // Bottom-left
            val bl = Path().apply {
                moveTo(r.left, r.bottom - cr - cornerLen)
                lineTo(r.left, r.bottom - cr)
                arcTo(RectF(r.left, r.bottom - 2 * cr, r.left + 2 * cr, r.bottom), 180f, -90f, false)
                lineTo(r.left + cr + cornerLen, r.bottom)
            }
            canvas.drawPath(bl, cornerPaint)

            // Bottom-right
            val br = Path().apply {
                moveTo(r.right - cr - cornerLen, r.bottom)
                lineTo(r.right - cr, r.bottom)
                arcTo(RectF(r.right - 2 * cr, r.bottom - 2 * cr, r.right, r.bottom), 90f, -90f, false)
                lineTo(r.right, r.bottom - cr - cornerLen)
            }
            canvas.drawPath(br, cornerPaint)
        }

        private fun dpF(value: Float): Float {
            return TypedValue.applyDimension(
                TypedValue.COMPLEX_UNIT_DIP, value, resources.displayMetrics
            )
        }
    }

    /**
     * Golden IC chip icon that simulates the chip on the back of an ID card.
     */
    inner class ChipIconView(context: Context) : View(context) {

        private val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#EBD1B566") // golden
        }
        private val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#FFAD9447")
            style = Paint.Style.STROKE
            strokeWidth = dpF(0.8f)
        }
        private val linePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#8CAD9447")
            style = Paint.Style.STROKE
            strokeWidth = dpF(0.8f)
        }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            val w = width.toFloat()
            val h = height.toFloat()
            val r = dpF(5f)
            val pad = dpF(5f)

            // Background
            canvas.drawRoundRect(0f, 0f, w, h, r, r, bgPaint)
            canvas.drawRoundRect(0f, 0f, w, h, r, r, borderPaint)

            // Horizontal lines
            val lineCount = 4
            val spacing = (h - 2 * pad) / lineCount
            for (i in 0 until lineCount) {
                val y = pad + i * spacing + spacing / 2
                canvas.drawLine(pad, y, w - pad, y, linePaint)
            }

            // Vertical center line
            canvas.drawLine(w / 2, pad, w / 2, h - pad, linePaint)
        }

        private fun dpF(value: Float): Float {
            return TypedValue.applyDimension(
                TypedValue.COMPLEX_UNIT_DIP, value, resources.displayMetrics
            )
        }
    }

    /**
     * Three thin horizontal lines representing where MRZ text appears.
     */
    inner class MRZLinesView(context: Context) : View(context) {

        private val linePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#2EFFFFFF") // 18% white
            style = Paint.Style.STROKE
            strokeWidth = dpF(2f)
            strokeCap = Paint.Cap.ROUND
        }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            val w = width.toFloat()
            val h = height.toFloat()
            val lineCount = 3
            val lineH = dpF(2f)
            val gap = (h - lineCount * lineH) / (lineCount + 1)

            for (i in 0 until lineCount) {
                val y = gap + i * (lineH + gap) + lineH / 2
                canvas.drawLine(0f, y, w, y, linePaint)
            }
        }

        private fun dpF(value: Float): Float {
            return TypedValue.applyDimension(
                TypedValue.COMPLEX_UNIT_DIP, value, resources.displayMetrics
            )
        }
    }

    /**
     * Simple X mark drawn with two crossing lines.
     */
    inner class XMarkView(context: Context) : View(context) {

        private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            style = Paint.Style.STROKE
            strokeWidth = dpF(2f)
            strokeCap = Paint.Cap.ROUND
        }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            val pad = width * 0.32f
            canvas.drawLine(pad, pad, width - pad, height - pad, paint)
            canvas.drawLine(width - pad, pad, pad, height - pad, paint)
        }

        private fun dpF(value: Float): Float {
            return TypedValue.applyDimension(
                TypedValue.COMPLEX_UNIT_DIP, value, resources.displayMetrics
            )
        }
    }
}
