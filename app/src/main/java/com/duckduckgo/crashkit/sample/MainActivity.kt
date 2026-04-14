package com.duckduckgo.crashkit.sample

import android.os.Build
import android.os.Bundle
import android.view.View
import androidx.appcompat.app.AppCompatActivity
import com.duckduckgo.android_crashkit.Crashpad
import com.duckduckgo.android_crashkit.CrashpadConfig
import com.duckduckgo.crashkit.sample.databinding.ActivityMainBinding

class MainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMainBinding

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        val initialized = Crashpad.init(
            this,
            platform = "Android",
            version = BuildConfig.VERSION_NAME,
            osVersion = "Android SDK ${Build.VERSION.SDK_INT}",
            config = CrashpadConfig(
                uploadUrl = BuildConfig.CRASHPAD_UPLOAD_URL,
                uploadsEnabled = BuildConfig.CRASHPAD_UPLOADS_ENABLED,
                noRateLimit = BuildConfig.DEBUG,
            ),
        )

        val status = if (initialized) "Crashpad initialized" else "Crashpad init failed"
        val url = BuildConfig.CRASHPAD_UPLOAD_URL.ifEmpty { "uploads disabled" }
        binding.sampleText.text = "$status\n$url"
    }

    fun btnCrashClick(view: View) {
        Crashpad.crash()
    }

    fun btnDumpWithoutCrashClick(view: View) {
        Crashpad.dumpWithoutCrash()
    }
}
