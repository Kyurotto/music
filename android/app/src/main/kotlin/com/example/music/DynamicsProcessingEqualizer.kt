package com.example.music

import android.media.audiofx.DynamicsProcessing
import android.os.Build
import android.util.Log

/**
 * Real multi-band equalizer for Android 9+.
 *
 * The platform [android.media.audiofx.Equalizer] effect on many devices (for
 * example the Infinix X6731) only exposes a +/-1.5 dB range, which is too
 * narrow for the app presets. The DynamicsProcessing pre-EQ stage offers a
 * +/-12 dB range instead.
 */
class DynamicsProcessingEqualizer {
    private var effect: DynamicsProcessing? = null
    private var sessionId: Int = 0
    private var bands: List<Float> = List(ANCHOR_FREQUENCIES.size) { 0f }

    fun isSupported(): Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.P

    /**
     * Creates (or reuses) the effect on [audioSessionId] and applies [newBands].
     *
     * Returns false when the platform has no working DynamicsProcessing
     * implementation, so Dart can fall back to its AndroidEqualizer backend.
     */
    @Synchronized
    fun attach(audioSessionId: Int, newBands: List<Float>): Boolean {
        if (!isSupported() || audioSessionId <= 0) return false

        if (effect != null && sessionId == audioSessionId) {
            return apply(newBands)
        }

        release()
        bands = sanitize(newBands)

        return try {
            val processor = DynamicsProcessing(
                0,
                audioSessionId,
                buildConfig(bands),
            )
            processor.enabled = true
            effect = processor
            sessionId = audioSessionId
            Log.i(
                TAG,
                "Attached DynamicsProcessing to session $audioSessionId " +
                    "with ${bands.joinToString()} dB",
            )
            true
        } catch (t: Throwable) {
            Log.w(TAG, "Unable to attach DynamicsProcessing to session $audioSessionId", t)
            release()
            false
        }
    }

    @Synchronized
    fun apply(newBands: List<Float>): Boolean {
        bands = sanitize(newBands)
        val processor = effect ?: return false

        return try {
            for (index in ANCHOR_FREQUENCIES.indices) {
                processor.setPreEqBandAllChannelsTo(
                    index,
                    DynamicsProcessing.EqBand(
                        true,
                        ANCHOR_FREQUENCIES[index],
                        bands[index],
                    ),
                )
            }
            Log.i(TAG, "Applied ${bands.joinToString()} dB to DynamicsProcessing")
            true
        } catch (t: Throwable) {
            Log.w(TAG, "Unable to update DynamicsProcessing bands", t)
            false
        }
    }

    @Synchronized
    fun release() {
        try {
            effect?.enabled = false
            effect?.release()
        } catch (_: Throwable) {
            // The effect may already be detached from a dead audio session.
        } finally {
            effect = null
            sessionId = 0
        }
    }

    private fun buildConfig(initialBands: List<Float>): DynamicsProcessing.Config {
        val builder = DynamicsProcessing.Config.Builder(
            DynamicsProcessing.VARIANT_FAVOR_FREQUENCY_RESOLUTION,
            CHANNEL_COUNT,
            true,
            ANCHOR_FREQUENCIES.size,
            false,
            0,
            false,
            0,
            false,
        )
        val config = builder.build()
        for (index in ANCHOR_FREQUENCIES.indices) {
            config.setPreEqBandAllChannelsTo(
                index,
                DynamicsProcessing.EqBand(
                    true,
                    ANCHOR_FREQUENCIES[index],
                    initialBands[index],
                ),
            )
        }
        return config
    }

    private fun sanitize(values: List<Float>): List<Float> {
        val result = MutableList(ANCHOR_FREQUENCIES.size) { 0f }
        for (index in result.indices) {
            result[index] = if (index < values.size) {
                values[index].coerceIn(MIN_GAIN_DB, MAX_GAIN_DB)
            } else {
                0f
            }
        }
        return result
    }

    companion object {
        private const val TAG = "AudioEqNative"
        private const val CHANNEL_COUNT = 2
        private const val MIN_GAIN_DB = -12f
        private const val MAX_GAIN_DB = 12f
        private val ANCHOR_FREQUENCIES = floatArrayOf(60f, 230f, 910f, 3600f, 14000f)
    }
}
