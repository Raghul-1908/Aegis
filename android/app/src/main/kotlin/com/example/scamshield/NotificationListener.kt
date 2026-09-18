package com.example.aegis

import android.app.Notification
import android.content.ComponentName
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import android.content.Context
import android.content.SharedPreferences
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant
import io.flutter.view.FlutterCallbackInformation
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

class NotificationListener : NotificationListenerService() {

    companion object {
        @Volatile var eventSink: EventChannel.EventSink? = null
        @Volatile private var serviceInstance: NotificationListener? = null
        private const val TAG = "AegisNL"
        private const val CALLBACK_CHANNEL = "aegis/background_callback"
        private const val PREFS = "aegis_bg_prefs"
        private const val KEY_CALLBACK_HANDLE = "callback_handle"
        private const val KEY_PENDING_QUEUE = "pending_queue"
        private const val MAX_QUEUE_SIZE = 100
        private const val DUPLICATE_WINDOW_MS = 1500L
        private const val JOB_TIMEOUT_MS = 20000L
        private const val MAX_FIELD_LENGTH = 4000

        fun onUiAttached() {
            serviceInstance?.startBackgroundWorker()
        }

        fun onCallbackRegistered() {
            serviceInstance?.startBackgroundWorker()
        }
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val queueLock = Any()
    private val pendingQueue = ArrayDeque<JSONObject>()
    private val ownPackageName: String by lazy { applicationContext.packageName }
    private var backgroundEngine: FlutterEngine? = null
    private var engineChannel: MethodChannel? = null
    private var activeJobId: String? = null
    private var timeoutRunnable: Runnable? = null
    private var readyTimeoutRunnable: Runnable? = null
    private var lastSignature: String? = null
    private var lastTimestamp = 0L

    private val prefs: SharedPreferences by lazy {
        getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    }

    override fun onCreate() {
        super.onCreate()
        serviceInstance = this
        restoreQueue()
        Log.i(TAG, "Notification listener created; queued=${queueSize()}")
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        Log.i(TAG, "Notification listener connected")
        startBackgroundWorker()
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        Log.w(TAG, "Notification listener disconnected; requesting rebind")
        requestRebind(ComponentName(this, NotificationListener::class.java))
    }

    private fun isOwnNotification(packageName: String?): Boolean {
        return packageName != null && packageName == ownPackageName
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        try {
            val packageName = sbn.packageName?.trim()?.take(MAX_FIELD_LENGTH).orEmpty()
            if (isOwnNotification(packageName)) {
                Log.i(TAG, "AegisNL: ignoring own notification")
                return
            }
            val (rawTitle, rawText) = extractContent(sbn)
            val title = rawTitle.take(MAX_FIELD_LENGTH)
            val text = rawText.take(MAX_FIELD_LENGTH)
            if (packageName.isBlank() || (title.isBlank() && text.isBlank())) return

        // Suppress only exact repeats during the short replay window — this
        // catches the OS occasionally re-posting the same notification
        // milliseconds apart. Longer-lived duplicate detection (the same
        // content arriving minutes/hours apart) is handled on the Dart side
        // by NotificationStore, which persists a content signature across
        // app restarts — this native check is just a debounce, not the
        // main dedup layer.
            val signature = "$packageName|$title|$text"
            val now = System.currentTimeMillis()
            synchronized(queueLock) {
                if (signature == lastSignature && now - lastTimestamp < DUPLICATE_WINDOW_MS) return
                lastSignature = signature
                lastTimestamp = now
            }

            val item = JSONObject()
                .put("jobId", UUID.randomUUID().toString())
                .put("package", packageName)
                .put("appName", getAppName(packageName).take(MAX_FIELD_LENGTH))
                .put("title", title)
                .put("text", text)
                .put("timestamp", sbn.postTime)

            mainHandler.post {
                val sink = eventSink
                if (sink != null) {
                    try {
                        sink.success(itemToMap(item))
                    } catch (t: Throwable) {
                        Log.e(TAG, "UI delivery failed; queueing notification", t)
                        enqueue(item)
                        startBackgroundWorker()
                    }
                } else {
                    enqueue(item)
                    startBackgroundWorker()
                }
            }
        } catch (t: Throwable) {
            Log.e(TAG, "Notification capture failed", t)
        }
    }

    private fun enqueue(item: JSONObject) {
        synchronized(queueLock) {
            if (pendingQueue.size >= MAX_QUEUE_SIZE) {
                Log.e(TAG, "Background queue full; notification was not accepted")
                return
            }
            pendingQueue.addLast(item)
            persistQueueLocked()
        }
        Log.d(TAG, "Queued notification; queued=${queueSize()}")
    }

    private fun restoreQueue() {
        synchronized(queueLock) {
            try {
                val array = JSONArray(prefs.getString(KEY_PENDING_QUEUE, "[]") ?: "[]")
                pendingQueue.clear()
                for (index in 0 until array.length()) {
                    val item = array.optJSONObject(index) ?: continue
                    if (item.optString("jobId").isNotBlank()) pendingQueue.addLast(item)
                }
                while (pendingQueue.size > MAX_QUEUE_SIZE) pendingQueue.removeFirst()
            } catch (t: Throwable) {
                Log.e(TAG, "Could not restore background queue", t)
                pendingQueue.clear()
            }
        }
    }

    private fun queueSize(): Int = synchronized(queueLock) { pendingQueue.size }

    private fun persistQueueLocked() {
        val array = JSONArray()
        pendingQueue.forEach { array.put(it) }
        prefs.edit().putString(KEY_PENDING_QUEUE, array.toString()).commit()
    }

    private fun startBackgroundWorker() {
        mainHandler.post {
            if (backgroundEngine != null || queueSize() == 0) return@post
            val handle = prefs.getLong(KEY_CALLBACK_HANDLE, -1L)
            if (handle <= 0L) {
                Log.w(TAG, "No background callback registered; open Aegis once")
                return@post
            }
            try {
                val callbackInfo = FlutterCallbackInformation.lookupCallbackInformation(handle)
                    ?: throw IllegalStateException("Invalid background callback handle")
                val newEngine = FlutterEngine(applicationContext)
                GeneratedPluginRegistrant.registerWith(newEngine)
                val channel = MethodChannel(newEngine.dartExecutor.binaryMessenger, CALLBACK_CHANNEL)
                backgroundEngine = newEngine
                engineChannel = channel
                channel.setMethodCallHandler { call, result ->
                    when (call.method) {
                        "ready" -> {
                            readyTimeoutRunnable?.let(mainHandler::removeCallbacks)
                            readyTimeoutRunnable = null
                            result.success(null)
                            dispatchNext()
                        }
                        "done" -> { result.success(null); completeJob(call.argument<String>("jobId"), true) }
                        "failed" -> { result.success(null); completeJob(call.argument<String>("jobId"), false) }
                        else -> result.notImplemented()
                    }
                }
                val loader = FlutterInjector.instance().flutterLoader()
                loader.startInitialization(applicationContext)
                loader.ensureInitializationComplete(applicationContext, null)
                readyTimeoutRunnable = Runnable {
                    Log.e(TAG, "Background engine ready handshake timed out")
                    destroyEngine()
                    mainHandler.postDelayed({ startBackgroundWorker() }, 500L)
                }
                mainHandler.postDelayed(readyTimeoutRunnable!!, JOB_TIMEOUT_MS)
                newEngine.dartExecutor.executeDartCallback(
                    DartExecutor.DartCallback(applicationContext.assets, loader.findAppBundlePath(), callbackInfo),
                )
                Log.i(TAG, "Background Flutter engine started")
            } catch (t: Throwable) {
                Log.e(TAG, "Background engine startup failed", t)
                destroyEngine()
                mainHandler.postDelayed({ startBackgroundWorker() }, 1500L)
            }
        }
    }

    private fun dispatchNext() {
        val channel = engineChannel ?: return
        val item: JSONObject
        synchronized(queueLock) {
            if (activeJobId != null || pendingQueue.isEmpty()) return
            item = pendingQueue.first()
            activeJobId = item.optString("jobId")
        }
        val jobId = activeJobId ?: return
        try {
            channel.invokeMethod("scoreNotification", itemToMap(item))
        } catch (t: Throwable) {
            Log.e(TAG, "Could not dispatch job $jobId", t)
            completeJob(jobId, false)
            return
        }
        timeoutRunnable?.let(mainHandler::removeCallbacks)
        timeoutRunnable = Runnable {
            Log.e(TAG, "Background job timed out: $jobId")
            completeJob(jobId, false)
        }
        mainHandler.postDelayed(timeoutRunnable!!, JOB_TIMEOUT_MS)
    }

    private fun completeJob(jobId: String?, success: Boolean) {
        if (jobId.isNullOrBlank()) return
        synchronized(queueLock) {
            if (jobId != activeJobId) return
            val current = pendingQueue.firstOrNull()
            if (current?.optString("jobId") == jobId) {
                if (success) {
                    pendingQueue.removeFirst()
                } else {
                    val attempts = current.optInt("attempts", 0) + 1
                    if (attempts >= 3) {
                        Log.e(TAG, "Dropping failed job after 3 attempts: $jobId")
                        pendingQueue.removeFirst()
                    } else {
                        current.put("attempts", attempts)
                        pendingQueue.removeFirst()
                        pendingQueue.addLast(current)
                    }
                }
            }
            activeJobId = null
            persistQueueLocked()
        }
        timeoutRunnable?.let(mainHandler::removeCallbacks)
        timeoutRunnable = null
        if (queueSize() == 0) {
            destroyEngine()
        } else if (success) {
            dispatchNext()
        } else {
            destroyEngine()
            mainHandler.postDelayed({ startBackgroundWorker() }, 500L)
        }
    }

    private fun destroyEngine() {
        timeoutRunnable?.let(mainHandler::removeCallbacks)
        timeoutRunnable = null
        readyTimeoutRunnable?.let(mainHandler::removeCallbacks)
        readyTimeoutRunnable = null
        engineChannel?.setMethodCallHandler(null)
        engineChannel = null
        backgroundEngine?.destroy()
        backgroundEngine = null
        activeJobId = null
    }

    private fun itemToMap(item: JSONObject): Map<String, Any?> = buildMap {
        val keys = item.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            val value = item.opt(key)
            put(key, if (value == JSONObject.NULL) null else value)
        }
    }

    /**
     * Extracts the most complete title/text Aegis can find from a
     * notification.
     *
     * Titles are commonly CharSequence/SpannableString rather than plain
     * String, and Gmail may store grouped messages in EXTRA_TEXT_LINES.
     */
    private fun extractContent(sbn: StatusBarNotification): Pair<String, String> {
        val extras = sbn.notification.extras

        val title = (extras.getCharSequence(Notification.EXTRA_TITLE)
            ?: extras.getCharSequence(Notification.EXTRA_TITLE_BIG))
            ?.toString()?.trim() ?: ""

        var text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()?.trim() ?: ""

        if (text.isBlank()) {
            text = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()?.trim() ?: ""
        }

        if (text.isBlank()) {
            // InboxStyle / grouped notifications — Gmail bundles multiple
            // emails this way. Join every line into one body.
            val lines = extras.getCharSequenceArray(Notification.EXTRA_TEXT_LINES)
            if (lines != null && lines.isNotEmpty()) {
                text = lines.joinToString(" ") { it.toString() }.trim()
            }
        }

        if (text.isBlank()) {
            text = extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString()?.trim() ?: ""
        }

        if (text.isBlank()) {
            text = extras.getCharSequence(Notification.EXTRA_SUMMARY_TEXT)?.toString()?.trim() ?: ""
        }

        if (text.isBlank()) {
            // MessagingStyle — individual messages as a Parcelable array.
            @Suppress("DEPRECATION")
            val messages = extras.getParcelableArray("android.messages")
            if (messages != null && messages.isNotEmpty()) {
                val last = messages.last() as? Bundle
                text = last?.getCharSequence("text")?.toString()?.trim() ?: ""
            }
        }

        return Pair(title, text)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
    }

    private fun getAppName(packageName: String): String {
        return try {
            val appInfo = packageManager.getApplicationInfo(packageName, 0)
            packageManager.getApplicationLabel(appInfo).toString()
        } catch (e: Exception) {
            packageName
        }
    }

    override fun onDestroy() {
        eventSink = null
        serviceInstance = null
        destroyEngine()
        super.onDestroy()
    }
}