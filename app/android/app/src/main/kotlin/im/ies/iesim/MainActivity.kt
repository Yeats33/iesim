package im.ies.iesim

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.time.ZoneId

class MainActivity : FlutterActivity() {
    private var pendingSaveResult: MethodChannel.Result? = null
    private var pendingSaveBytes: ByteArray? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DOCUMENT_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "saveJson" -> {
                    if (pendingSaveResult != null) {
                        result.error("SAVE_IN_PROGRESS", "已有保存操作正在进行", null)
                        return@setMethodCallHandler
                    }
                    val fileName = call.argument<String>("fileName")
                    val bytes = call.argument<ByteArray>("bytes")
                    if (fileName.isNullOrBlank() || bytes == null) {
                        result.error("INVALID_ARGUMENT", "缺少文件名或内容", null)
                        return@setMethodCallHandler
                    }
                    pendingSaveResult = result
                    pendingSaveBytes = bytes
                    val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "application/json"
                        putExtra(Intent.EXTRA_TITLE, fileName)
                    }
                    startActivityForResult(intent, SAVE_JSON_REQUEST)
                }

                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DEVICE_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "timeZoneId" -> result.success(ZoneId.systemDefault().id)
                else -> result.notImplemented()
            }
        }
    }

    @Deprecated("Android Activity result callback")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != SAVE_JSON_REQUEST) return
        val result = pendingSaveResult
        val bytes = pendingSaveBytes
        pendingSaveResult = null
        pendingSaveBytes = null
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            result?.success(false)
            return
        }
        try {
            contentResolver.openOutputStream(data.data!!)?.use { stream ->
                stream.write(bytes ?: ByteArray(0))
                stream.flush()
            } ?: throw IllegalStateException("无法打开目标文件")
            result?.success(true)
        } catch (error: Exception) {
            result?.error("SAVE_FAILED", error.message, null)
        }
    }

    companion object {
        private const val DOCUMENT_CHANNEL = "im.ies.iesim/documents"
        private const val DEVICE_CHANNEL = "im.ies.iesim/device"
        private const val SAVE_JSON_REQUEST = 7411
    }
}
