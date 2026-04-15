package com.duckduckgo.android_crashkit

import android.content.Context
import java.io.File

data class CrashpadConfig(
    val uploadUrl: String = "",
    val uploadsEnabled: Boolean = false,
    val noRateLimit: Boolean = false,
    // Called on the next launch if a crash occurred in the previous session.
    // Runs on the thread that called init() — fire any pixel/telemetry here.
    val onCrash: (() -> Unit)? = null,
)

object Crashpad {
    @Volatile internal var inited = false
    @Volatile internal var libraryLoaded = false

    init {
        runCatching { System.loadLibrary("crashkit") }
            .onSuccess { libraryLoaded = true }
            .onFailure { /* library unavailable — all calls will no-op */ }
    }

    /**
     * Call once per process (e.g., in Application.onCreate()).
     *
     * If a crash occurred in the previous session, [CrashpadConfig.onCrash] is invoked
     * before Crashpad is initialised, on the calling thread.
     */
    @JvmStatic
    fun init(
        context: Context,
        platform: String,
        version: String,
        osVersion: String,
        extraAnnotations: Map<String, String> = emptyMap(),
        dynamicAnnotationKeys: Set<String> = emptySet(),
        config: CrashpadConfig = CrashpadConfig(),
    ): Boolean {
        if (!libraryLoaded) return false
        if (inited) return true

        // Marker file written by the native FirstChanceHandler at crash time.
        // Lives inside the crashpad dir, which is created by CrashReportDatabase.Initialize.
        val markerFile = File(context.filesDir, "crashpad/crash_marker")
        val markerPath = if (config.onCrash != null) markerFile.absolutePath else ""

        // Consume any pending crash marker from the previous session.
        if (config.onCrash != null && markerFile.exists()) {
            markerFile.delete()
            config.onCrash.invoke()
        }

        val handler = File(context.applicationInfo.nativeLibraryDir, "crashpad_handler.so")
        val ok = runCatching {
            initializeCrashpad(
                context.filesDir.absolutePath,
                handler.absolutePath,
                platform = platform,
                version = version,
                osVersion = osVersion,
                uploadUrl = config.uploadUrl,
                uploadsEnabled = config.uploadsEnabled,
                noRateLimit = config.noRateLimit,
                annotationKeys = extraAnnotations.keys.toTypedArray(),
                annotationValues = extraAnnotations.values.toTypedArray(),
                dynamicAnnotationKeys = dynamicAnnotationKeys.toTypedArray(),
                markerPath = markerPath,
            )
        }.getOrDefault(false)
        inited = ok
        return ok
    }

    @JvmStatic private external fun initializeCrashpad(
        dataDir: String,
        handlerPath: String,
        platform: String,
        version: String,
        osVersion: String,
        uploadUrl: String,
        uploadsEnabled: Boolean,
        noRateLimit: Boolean,
        annotationKeys: Array<String>,
        annotationValues: Array<String>,
        dynamicAnnotationKeys: Array<String>,
        markerPath: String,
    ): Boolean

    /**
     * Update a named annotation in the crash report. Call this as state changes — the value
     * captured at crash time will be whatever was set most recently.
     *
     * Keys and values are limited to 255 bytes each (Crashpad SimpleStringDictionary limit).
     * Values exceeding this will be silently truncated by the native layer.
     * Has no effect before [init] is called.
     */
    @JvmStatic fun setAnnotation(key: String, value: String) {
        if (!inited) return
        nativeSetAnnotation(key, value)
    }

    @JvmStatic fun crash(): Boolean {
        if (!libraryLoaded) return false
        return nativeCrash()
    }

    @JvmStatic fun dumpWithoutCrash(): Boolean {
        if (!libraryLoaded) return false
        return nativeDumpWithoutCrash()
    }

    private external fun nativeCrash(): Boolean
    private external fun nativeDumpWithoutCrash(): Boolean
    private external fun nativeSetAnnotation(key: String, value: String)
}
