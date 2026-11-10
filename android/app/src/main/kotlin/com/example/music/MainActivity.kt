package com.example.music

import android.os.Build
import android.os.Bundle
import android.view.Display
import android.view.WindowManager
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.math.abs
import kotlin.math.roundToInt

class MainActivity : AudioServiceActivity() {
    private val CHANNEL = "com.example.music/display_rate"
    private val EQUALIZER_CHANNEL = "com.example.music/equalizer"
    private val equalizerEffect = DynamicsProcessingEqualizer()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applyOptimalRefreshRate()
    }

    override fun onResume() {
        super.onResume()
        applyOptimalRefreshRate()
    }

    override fun onDestroy() {
        equalizerEffect.release()
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getRefreshRate" -> {
                    val rate = getCurrentRefreshRate()
                    result.success(rate)
                }
                "getSupportedRefreshRates" -> {
                    val rates = getSupportedRefreshRates()
                    result.success(rates)
                }
                "setRefreshRate" -> {
                    val targetHz = (call.argument<Number>("rate"))?.toDouble()
                    val applied = applyOptimalRefreshRate(targetHz)
                    result.success(applied)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, EQUALIZER_CHANNEL).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "isSupported" -> result.success(equalizerEffect.isSupported())
                    "attach" -> {
                        val sessionId = (call.argument<Number>("sessionId"))?.toInt() ?: 0
                        result.success(equalizerEffect.attach(sessionId, readBands(call.argument("bands"))))
                    }
                    "applyBands" -> {
                        result.success(equalizerEffect.apply(readBands(call.argument("bands"))))
                    }
                    "release" -> {
                        equalizerEffect.release()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (t: Throwable) {
                result.error("EQUALIZER_ERROR", t.message, null)
            }
        }
    }

    private fun readBands(raw: Any?): List<Float> {
        val values = raw as? List<*> ?: return emptyList()
        return values.map { (it as? Number)?.toFloat() ?: 0f }
    }

    private fun getTargetDisplay(): Display? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                display ?: windowManager.defaultDisplay
            } catch (_: Throwable) {
                @Suppress("DEPRECATION")
                windowManager.defaultDisplay
            }
        } else {
            @Suppress("DEPRECATION")
            windowManager.defaultDisplay
        }
    }

    private fun getCurrentRefreshRate(): Double {
        val disp = getTargetDisplay()
        val rate = disp?.refreshRate ?: 60f
        return rate.roundToInt().toDouble()
    }

    private fun getSupportedRefreshRates(): List<Double> {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val disp = getTargetDisplay()
            val modes = disp?.supportedModes
            if (modes != null && modes.isNotEmpty()) {
                val rates = modes.map { it.refreshRate.roundToInt().toDouble() }
                    .distinct()
                    .sortedDescending()
                if (rates.isNotEmpty()) {
                    return rates
                }
            }
        }
        return listOf(getCurrentRefreshRate())
    }

    private fun applyOptimalRefreshRate(targetHz: Double? = null): Double {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val disp = getTargetDisplay()
            val modes = disp?.supportedModes ?: emptyArray()
            if (modes.isNotEmpty()) {
                val selectedMode = if (targetHz != null && targetHz > 0) {
                    modes.minByOrNull { abs(it.refreshRate.toDouble() - targetHz) } ?: modes.maxByOrNull { it.refreshRate }
                } else {
                    modes.maxByOrNull { it.refreshRate }
                }
                if (selectedMode != null) {
                    val params = window.attributes
                    params.preferredDisplayModeId = selectedMode.modeId
                    params.preferredRefreshRate = selectedMode.refreshRate
                    window.attributes = params
                    return selectedMode.refreshRate.roundToInt().toDouble()
                }
            }
        }
        return getCurrentRefreshRate()
    }
}
