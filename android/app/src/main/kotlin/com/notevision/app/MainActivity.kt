package com.notevision.app

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val channelName = "com.notevision.app/incoming_file"
    private var methodChannel: MethodChannel? = null
    private var pendingFilePath: String? = null
    private var launchIntentHandled = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName,
        )
        methodChannel!!.setMethodCallHandler { _, _ -> }

        pendingFilePath?.let { path ->
            methodChannel!!.invokeMethod("onFileReceived", path)
            pendingFilePath = null
        }
    }

    override fun onStart() {
        super.onStart()
        if (!launchIntentHandled) {
            launchIntentHandled = true
            handleIntent(intent)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null) return
        val uri: Uri? = when (intent.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND -> {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra(Intent.EXTRA_STREAM)
            }
            else -> return
        }
        if (uri == null) return

        try {
            val tempFile = File(cacheDir, "incoming.nvscore")
            contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(tempFile).use { output ->
                    input.copyTo(output)
                }
            }
            val path = tempFile.absolutePath
            val mc = methodChannel
            if (mc != null) {
                mc.invokeMethod("onFileReceived", path)
            } else {
                pendingFilePath = path
            }
        } catch (_: Exception) {}
    }
}
