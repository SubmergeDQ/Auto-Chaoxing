package cn.autochaoxing.auto_chaoxing

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "cn.autochaoxing/run_keeper"
        private const val REQ_NOTIFICATIONS = 0xAC1
    }

    /** 权限是异步的：等 onRequestPermissionsResult 回来再答 Dart。 */
    private var pendingPermissionResult: MethodChannel.Result? = null

    private lateinit var channel: MethodChannel

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        RunKeeperBridge.channel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "ensureNotificationPermission" -> ensureNotificationPermission(result)

                "begin" -> {
                    // 没有通知权限也照常起服务：Android 13+ 在没有 POST_NOTIFICATIONS 时
                    // 前台服务依然合法、进程优先级依然高，保活是有效的，只是通知不显示。
                    // 保住执行比展示进度重要，所以这里不做权限前置拦截。
                    val intent = serviceIntent(RunKeepService.ACTION_START).apply {
                        putExtra(RunKeepService.EXTRA_TITLE, call.argument<String>("title") ?: "正在执行")
                        putExtra(RunKeepService.EXTRA_BODY, call.argument<String>("body") ?: "")
                    }
                    result.success(startKeepService(intent, foreground = true))
                }

                "update" -> {
                    startKeepService(
                        serviceIntent(RunKeepService.ACTION_UPDATE).apply {
                            putExtra(RunKeepService.EXTRA_TITLE, call.argument<String>("title") ?: "正在执行")
                            putExtra(RunKeepService.EXTRA_BODY, call.argument<String>("body") ?: "")
                        },
                        foreground = true,
                    )
                    result.success(null)
                }

                "finish" -> {
                    // 换成结果通知并脱离前台。服务此刻通常还在跑，因此这里可以安全地
                    // 用普通 startService 投递；服务已被系统回收时 startService 会失败，
                    // 那就只能回应用里看结果，不该因此崩掉。
                    startKeepService(
                        serviceIntent(RunKeepService.ACTION_FINISH).apply {
                            putExtra(RunKeepService.EXTRA_TITLE, call.argument<String>("title") ?: "执行结束")
                            putExtra(RunKeepService.EXTRA_BODY, call.argument<String>("body") ?: "")
                        },
                        foreground = false,
                    )
                    result.success(null)
                }

                "end" -> {
                    // 只停服务，不走 ACTION_STOP：正常结束不该回调成「用户叫停」。
                    startKeepService(serviceIntent(RunKeepService.ACTION_END), foreground = false)
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        if (RunKeeperBridge.channel === channel) RunKeeperBridge.channel = null
        super.onDestroy()
    }

    private fun serviceIntent(action: String) = Intent(this, RunKeepService::class.java).setAction(action)

    /**
     * 起服务。[foreground] 为 true 时用 startForegroundService（系统要求 5 秒内 startForeground，
     * START/UPDATE 都会立即调用，满足）；为 false 时用 startService（结束类 action 不占前台，
     * 用 startForegroundService 反而会因为没调 startForeground 触发 ANR）。
     * 报错时不把异常抛给 Dart——保活失败只该降级，不该打断执行。
     */
    private fun startKeepService(intent: Intent, foreground: Boolean): Boolean = try {
        if (foreground && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
        true
    } catch (e: Exception) {
        false
    }

    private fun hasNotificationPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        return checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
    }

    private fun ensureNotificationPermission(result: MethodChannel.Result) {
        if (hasNotificationPermission()) {
            result.success(true)
            return
        }
        // 已有一次在等结果：把之前的请求当作取消，避免 Result 泄漏。
        pendingPermissionResult?.success(false)
        pendingPermissionResult = result
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQ_NOTIFICATIONS)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQ_NOTIFICATIONS) return
        val pending = pendingPermissionResult ?: return
        pendingPermissionResult = null
        pending.success(
            grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED,
        )
    }
}
