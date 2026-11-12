package cn.autochaoxing.auto_chaoxing

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log

/**
 * 执行期间占住进程的前台服务。
 *
 * 它自己不干活：网络请求与 60 秒节流都在 Flutter 的 Dart 侧跑。这个服务只做两件事——
 *   1. 把进程提到前台服务优先级，避免切后台后被系统当成「后台应用」回收；
 *   2. 持一把 PARTIAL_WAKE_LOCK，让熄屏后 CPU 不进 Doze 深度睡眠，
 *      否则 Dart 的定时器会被系统拖长到几分钟甚至不再到期。
 *
 * 通知上有「停止」：点了走 [ACTION_STOP]，停服务并回调 Dart 侧的 onStopRequested。
 * Dart 自己结束执行时走 [ACTION_END]，只停服务、不回调（避免把「正常结束」误当成用户叫停）。
 */
class RunKeepService : Service() {

    companion object {
        const val ACTION_START = "cn.autochaoxing.RUN_KEEP_START"
        const val ACTION_UPDATE = "cn.autochaoxing.RUN_KEEP_UPDATE"
        const val ACTION_STOP = "cn.autochaoxing.RUN_KEEP_STOP"
        const val ACTION_END = "cn.autochaoxing.RUN_KEEP_END"
        const val ACTION_FINISH = "cn.autochaoxing.RUN_KEEP_FINISH"

        const val EXTRA_TITLE = "title"
        const val EXTRA_BODY = "body"

        private const val CHANNEL_ID = "run_keep"
        private const val NOTIFICATION_ID = 0xAC01

        /** 系统设置里给用户看到的通知渠道名。 */
        const val CHANNEL_NAME = "执行进度"

        private const val WAKE_TAG = "AutoChaoxing::run"

        /**
         * 诊断用。熄屏保活出问题时，用户拿不到任何现场——
         * adb 一断就什么都看不到，所以把「锁有没有持有、服务活了多久」写进 logcat，
         * 事后用 `adb logcat -d -s AcxRunKeep` 就能复盘。
         */
        private const val TAG = "AcxRunKeep"
    }

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra(EXTRA_TITLE) ?: "正在执行"
        val body = intent?.getStringExtra(EXTRA_BODY) ?: ""
        Log.i(TAG, "onStartCommand action=${intent?.action} held=${wakeLock?.isHeld}")

        when (intent?.action) {
            ACTION_STOP -> {
                // 用户在通知栏叫停：先告诉 Dart，再停自己。
                RunKeeperBridge.notifyStopRequested()
                stopSelf()
                return START_NOT_STICKY
            }

            ACTION_END -> {
                stopSelf()
                return START_NOT_STICKY
            }

            ACTION_UPDATE -> {
                // 只换文案。startForeground 重复调用是安全的，且能保证通知始终挂着。
                startForegroundCompat(buildNotification(title, body))
                return START_NOT_STICKY
            }

            ACTION_FINISH -> {
                // 执行已结束：把通知换成结论，不再挂「停止」，然后脱离前台把通知留下。
                // 用户切回应用之前，通知栏是唯一能看到「跑完了 / 卡住了」的地方。
                val done = buildNotification(title, body, ongoing = false, withStop = false)
                (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                    .notify(NOTIFICATION_ID, done)
                detachForeground()
                stopSelf()
                return START_NOT_STICKY
            }

            else -> {
                acquireWakeLock()
                startForegroundCompat(buildNotification(title, body))
                return START_NOT_STICKY
            }
        }
    }

    override fun onDestroy() {
        Log.i(TAG, "onDestroy held=${wakeLock?.isHeld}")
        releaseWakeLock()
        super.onDestroy()
    }

    /** 进程被杀时 wakelock 会随进程释放，但正常路径必须显式释放，否则要等系统兜底。 */
    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKE_TAG).apply {
            setReferenceCounted(false)
            // 不设超时：一个前台服务在跑多久，锁就该持多久；stopSelf 时释放。
            @Suppress("WakelockTimeout")
            acquire()
        }
        // 拿不到锁时熄屏必然停表，这条日志是判断「是我们的问题还是系统的问题」的分界。
        Log.i(TAG, "acquireWakeLock held=${wakeLock?.isHeld}")
    }

    private fun releaseWakeLock() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        Log.i(TAG, "releaseWakeLock")
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            // 进度类通知用 LOW：常驻但不发声，只有状态变化才值得看一眼。
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "执行视频任务点期间的进度，可从通知直接停止"
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(
        title: String,
        body: String,
        ongoing: Boolean = true,
        withStop: Boolean = true,
    ): Notification {
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        builder
            .setContentTitle(title)
            .setContentText(body)
            .setSmallIcon(R.drawable.ic_stat_run)
            .setContentIntent(open)
            .setOngoing(ongoing)
            // 每 60 秒换一次文案，不该每次都响。
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_PROGRESS)
            .setVisibility(Notification.VISIBILITY_PUBLIC)

        if (withStop) {
            val stop = PendingIntent.getService(
                this,
                1,
                Intent(this, RunKeepService::class.java).setAction(ACTION_STOP),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            builder.addAction(Notification.Action.Builder(null, "停止", stop).build())
        } else {
            // 结果通知：让它可被划掉，别常驻。
            builder.setAutoCancel(true)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // 用户刚点了开始就要看到通知，不要等系统攒够 10 秒的免打扰窗口。
            builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        }
        return builder.build()
    }

    private fun startForegroundCompat(notification: Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    /** 退出前台但保留通知，让结论留在通知栏。 */
    private fun detachForeground() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            stopForeground(STOP_FOREGROUND_DETACH)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(false)
        }
    }
}

/**
 * 服务与 Flutter 之间的桥。
 *
 * Service 拿不到 MethodChannel（那个注册在 Activity 的 FlutterEngine 上），
 * 所以由 MainActivity 在 configureFlutterEngine 时把通道存一份在这里。
 * 两者同进程，静态引用有效；Activity 切后台只是 onStop，不会销毁 engine。
 */
object RunKeeperBridge {
    @Volatile
    var channel: io.flutter.plugin.common.MethodChannel? = null

    fun notifyStopRequested() {
        // 必须在主线程调用：Service.onStartCommand 本身就在主线程。
        channel?.invokeMethod("onStopRequested", null)
    }
}
