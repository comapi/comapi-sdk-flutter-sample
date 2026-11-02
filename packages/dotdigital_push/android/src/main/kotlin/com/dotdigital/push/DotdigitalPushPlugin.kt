package com.dotdigital.push

// ============================================================================
// DOTDIGITAL PUSH PLUGIN - ANDROID IMPLEMENTATION (COMAPI FOUNDATION)
// ============================================================================
// This native plugin connects Flutter to the Dotdigital (Comapi Foundation 1.8.1)
// Android SDK and Firebase Cloud Messaging (FCM).
//
// HIGH LEVEL NARRATIVE:
// 1. SDK INITIALIZATION (`initializeSdk`):
//    Calls `Comapi.initialiseShared(context, config, callback)` using the Dotdigital
//    API Space ID. Configures the authenticator and push message listener.
// 2. AUTHENTICATION CHALLENGE:
//    When a session starts, Comapi raises `onAuthenticationChallenge` with a nonce.
//    This plugin calls Dart over the MethodChannel to acquire a signed JWT (HS256).
// 3. INTENT & CLICK TRACKING (`handleIncomingIntent`):
//    When a user taps a notification from the Android system tray, `MainActivity` passes
//    the Intent to `client.handlePushNotification()`. This notifies Dotdigital's analytics
//    gateway that a push click occurred, then returns deep link URLs and custom data.
// 4. FOREGROUND VS SILENT PUSH (`handleRemoteMessage`):
//    If `message.notification != null`: A foreground push arrived; posts an OS channel alert
//    and emits `onPushReceived` to show an in-app Toast banner.
//    If `message.notification == null`: A silent data push arrived; emits `onSilentPushReceived`
//    without alerting the user.
// 5. CONTACT DISCOVERY (`updateProfileEmail`):
//    Fetches profile to obtain the current `eTag`, then patches the profile with `email`.
//    This allows Dotdigital Marketing to associate the FCM push token with an email contact.
//
// ⚠️ SECURITY WARNING:
// Storing Shared Secrets in mobile application packages is UNSAFE in production.
// This example app supports client-side JWT generation solely for demonstration,
// sandbox evaluation, and documentation validation. In production environments,
// JWTs must be requested from an authenticated server-side API.
// ============================================================================

import android.Manifest
import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.comapi.Callback
import com.comapi.Comapi
import com.comapi.ComapiAuthenticator
import com.comapi.ComapiClient
import com.comapi.ComapiConfig
import com.comapi.PushDetails
import com.comapi.PushHandleResult
import com.comapi.Session
import com.comapi.internal.network.AuthClient
import com.comapi.internal.network.ChallengeOptions
import com.comapi.internal.network.ComapiResult
import com.comapi.internal.push.PushMessageListener
import com.google.firebase.messaging.FirebaseMessaging
import com.google.firebase.messaging.RemoteMessage
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import org.json.JSONException
import org.json.JSONObject

class DotdigitalPushPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware,
    PluginRegistry.NewIntentListener, PluginRegistry.RequestPermissionsResultListener {

    private lateinit var channel: MethodChannel
    private var applicationContext: Context? = null
    private var currentActivity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null

    private var initialTapEvent: Map<String, Any?>? = null
    private var pendingTrackingIntent: Intent? = null
    private var pendingPermissionResult: MethodChannel.Result? = null

    private val mainHandler = Handler(Looper.getMainLooper())
    private var currentEmail: String? = null
    private var currentApiSpaceId: String? = null
    private var isSdkInitialized = false
    @Volatile
    private var cachedFcmToken: String? = null
    private var lastHandledMessageId: String? = null
    private var lastHandledMessageTime: Long = 0L

    companion object {
        private const val CHANNEL_NAME = "com.dotdigital.push/methods"
        private const val NOTIFICATION_CHANNEL_ID = "dotdigital_push_default"
        private const val PERMISSION_REQUEST_CODE = 9081
    }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        applicationContext = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        currentActivity = binding.activity
        activityBinding = binding
        binding.addOnNewIntentListener(this)
        binding.addRequestPermissionsResultListener(this)

        binding.activity.intent?.let { intent ->
            handleIncomingIntent(intent, isInitial = true)
        }
    }

    override fun onDetachedFromActivityForConfigChanges() {
        currentActivity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        currentActivity = binding.activity
        activityBinding = binding
        binding.addOnNewIntentListener(this)
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeOnNewIntentListener(this)
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        currentActivity = null
    }

    override fun onNewIntent(intent: Intent): Boolean {
        handleIncomingIntent(intent, isInitial = false)
        return false
    }

    /**
     * Intercepts an incoming Android [Intent] to determine if it originated from a Dotdigital push notification
     * or deep link.
     *
     * If the Comapi client is initialized, invokes [client.handlePushNotification] to trigger
     * Dotdigital click-tracking analytics, resolves deep links or URLs from `dd_deepLink`, `dd_data`,
     * or intent data, and forwards the event to Flutter via [MethodChannel] so it opens automatically.
     */
    private fun handleIncomingIntent(intent: Intent, isInitial: Boolean) {
        val activity = currentActivity ?: return

        // Avoid processing the exact same notification tap intent more than once
        if (intent.getBooleanExtra("_dd_handled", false)) {
            return
        }

        val extras = intent.extras
        val intentDataUrl = intent.dataString?.takeIf { it.isNotBlank() }

        val rawMap = mutableMapOf<String, Any?>()
        if (extras != null) {
            for (key in extras.keySet()) {
                val value = extras.get(key)
                if (value is String || value is Number || value is Boolean) {
                    rawMap[key] = value.toString()
                }
            }
        }
        if (intentDataUrl != null && !rawMap.containsKey("url")) {
            rawMap["url"] = intentDataUrl
        }

        val fallbackUrl = extractUrlFromMap(rawMap) ?: intentDataUrl
        val fallbackCustomData = extractCustomDataFromMap(rawMap)

        val hasDdPayload = intentDataUrl != null ||
            rawMap.containsKey("dd_deepLink") ||
            rawMap.containsKey("dd_data") ||
            !fallbackUrl.isNullOrBlank()

        if (!hasDdPayload) return

        intent.putExtra("_dd_handled", true)

        // Verify if Comapi has been initialized
        val client = try {
            Comapi.getShared()
        } catch (e: Exception) {
            null
        }

        if (client == null) {
            val event = mapOf(
                "url" to fallbackUrl,
                "customData" to fallbackCustomData.ifEmpty { rawMap },
                "isClickRecorded" to false,
                "isDeepLinkCalled" to false,
                "isDdOriginated" to true,
                "rawPayload" to rawMap
            )
            if (isInitial) {
                initialTapEvent = event
                pendingTrackingIntent = Intent(intent)
            }
            mainHandler.post {
                channel.invokeMethod("onNotificationTapped", event)
            }
            return
        }

        val dispatched = java.util.concurrent.atomic.AtomicBoolean(false)

        // Use SDK to handle notification intent to trigger click tracking analytics
        client.handlePushNotification(activity, intent, false, object : Callback<PushHandleResult> {
            override fun success(result: PushHandleResult?) {
                if (!dispatched.compareAndSet(false, true)) return
                val resolvedUrl = result?.url?.takeIf { it.isNotBlank() } ?: fallbackUrl
                val sdkCustomData = jsonObjectToMap(result?.data)
                val resolvedCustomData = if (sdkCustomData.isNotEmpty()) sdkCustomData else fallbackCustomData
                val isClickRecorded = result?.isClickRecorded == true
                val isDeepLinkCalled = result?.isDeepLinkCalled == true

                val event = mapOf(
                    "url" to resolvedUrl,
                    "customData" to resolvedCustomData,
                    "isClickRecorded" to isClickRecorded,
                    "isDeepLinkCalled" to isDeepLinkCalled,
                    "isDdOriginated" to true,
                    "rawPayload" to if (rawMap.isNotEmpty()) rawMap else resolvedCustomData
                )

                if (isInitial) {
                    initialTapEvent = event
                }

                mainHandler.post {
                    channel.invokeMethod("onNotificationTapped", event)
                }
            }

            override fun error(t: Throwable) {
                // Even if click tracking HTTP request fails (e.g. test push trackingUrl or offline),
                // still emit the tap event so the URL or deep link opens automatically!
                if (!dispatched.compareAndSet(false, true)) return
                val event = mapOf(
                    "url" to fallbackUrl,
                    "customData" to fallbackCustomData,
                    "isClickRecorded" to false,
                    "isDeepLinkCalled" to false,
                    "isDdOriginated" to true,
                    "rawPayload" to if (rawMap.isNotEmpty()) rawMap else fallbackCustomData
                )

                if (isInitial) {
                    initialTapEvent = event
                }

                mainHandler.post {
                    channel.invokeMethod("onNotificationTapped", event)
                }
            }
        })
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> {
                val apiSpaceId = call.argument<String>("apiSpaceId")
                if (apiSpaceId.isNullOrBlank()) {
                    result.error("INVALID_ARGS", "apiSpaceId is required", null)
                    return
                }
                val email = call.argument<String>("contactEmail")
                if (!email.isNullOrBlank()) {
                    currentEmail = email
                }
                initializeSdk(apiSpaceId, result)
            }
            "requestNotificationPermissions" -> {
                requestPermissions(result)
            }
            "getNotificationPermissionStatus" -> {
                val context = applicationContext
                val status = when {
                    context == null -> "unknown"
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                        context.getSystemService(NotificationManager::class.java)
                            ?.getNotificationChannel(NOTIFICATION_CHANNEL_ID)?.importance == NotificationManager.IMPORTANCE_NONE -> "denied"
                    NotificationManagerCompat.from(context).areNotificationsEnabled() -> "authorized"
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                        !context.getSharedPreferences("dotdigital_push", Context.MODE_PRIVATE)
                            .getBoolean("permission_requested", false) -> "notDetermined"
                    else -> "denied"
                }
                result.success(status)
            }
            "openNotificationSettings" -> {
                val context = currentActivity ?: applicationContext
                try {
                    val intent = Intent(android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                        putExtra(android.provider.Settings.EXTRA_APP_PACKAGE, context?.packageName)
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    context?.startActivity(intent)
                    result.success(context != null)
                } catch (_: Exception) {
                    result.success(false)
                }
            }
            "registerPushToken" -> {
                fetchFcmToken { token -> result.success(!token.isNullOrBlank()) }
            }
            "startSession" -> {
                startSession(result)
            }
            "endSession" -> {
                endSession(result)
            }
            "updateUserEmail" -> {
                val email = call.argument<String>("email")
                if (email.isNullOrBlank()) {
                    result.error("INVALID_ARGS", "email cannot be empty", null)
                    return
                }
                currentEmail = email
                updateProfileEmail(email, result)
            }
            "getPushToken" -> {
                getPushToken(result)
            }
            "getSessionState" -> {
                getSessionState(result)
            }
            "getInitialNotification" -> {
                val event = initialTapEvent
                initialTapEvent = null
                result.success(event)
            }
            "openDeepLink" -> {
                val url = call.argument<String>("url")
                if (url.isNullOrBlank()) {
                    result.error("INVALID_ARGS", "url cannot be empty", null)
                    return
                }
                val rawPayload = call.argument<Map<String, Any?>>("rawPayload")
                val launchExternal = call.argument<Boolean>("launchExternal") ?: true
                openDeepLink(url, rawPayload, launchExternal, result)
            }
            else -> result.notImplemented()
        }
    }

    /**
     * Opens a deep link or external URL in the browser, and triggers Dotdigital click tracking
     * if [rawPayload] contains `dd_deepLink`.
     */
    private fun openDeepLink(
        url: String,
        rawPayload: Map<String, Any?>?,
        launchExternal: Boolean,
        result: MethodChannel.Result
    ) {
        val activity = currentActivity
        val client = try {
            Comapi.getShared()
        } catch (e: Exception) {
            null
        }

        // If rawPayload contains dd_deepLink, pass a synthetic Intent to Comapi SDK
        // so that any trackingUrl is reported to Dotdigital Marketing analytics.
        val ddDeepLinkObj = rawPayload?.get("dd_deepLink")
        val ddDeepLinkJson: String? = when (ddDeepLinkObj) {
            is String -> ddDeepLinkObj
            is Map<*, *> -> JSONObject(ddDeepLinkObj).toString()
            else -> null
        }

        if (client != null && activity != null && !ddDeepLinkJson.isNullOrBlank()) {
            val trackingIntent = Intent().apply {
                putExtra("dd_deepLink", ddDeepLinkJson)
            }
            client.handlePushNotification(activity, trackingIntent, false, object : Callback<PushHandleResult> {
                override fun success(res: PushHandleResult?) {
                    // Click tracking completed
                }

                override fun error(t: Throwable) {
                    // Ignore tracking failure so navigation still proceeds
                }
            })
        }

        if (launchExternal) {
            val launched = launchExternalUrl(url)
            result.success(launched)
        } else {
            result.success(true)
        }
    }

    /**
     * Launches an external URL (e.g. http/https) in the system's default web browser.
     */
    private fun launchExternalUrl(urlString: String): Boolean {
        return try {
            val trimmed = urlString.trim()
            val normalized = if (!trimmed.contains("://") && (trimmed.startsWith("www.", ignoreCase = true) || trimmed.contains("."))) {
                "https://$trimmed"
            } else {
                trimmed
            }
            val uri = android.net.Uri.parse(normalized)
            val viewIntent = Intent(Intent.ACTION_VIEW, uri).apply {
                addCategory(Intent.CATEGORY_DEFAULT)
                addCategory(Intent.CATEGORY_BROWSABLE)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            val targetContext = currentActivity ?: applicationContext ?: return false
            targetContext.startActivity(viewIntent)
            true
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Initializes the Comapi Foundation SDK using the provided [apiSpaceId].
     * Configures the [ComapiAuthenticator] challenge listener and [PushMessageListener].
     */
    private fun initializeSdk(apiSpaceId: String, result: MethodChannel.Result) {
        if (currentApiSpaceId != null) {
            if (currentApiSpaceId == apiSpaceId && isSdkInitialized) {
                result.success(true)
            } else {
                result.error("RESTART_REQUIRED", "Restart the app before initializing the SDK again.", null)
            }
            return
        }
        val context = applicationContext ?: run {
            result.error("NO_CONTEXT", "Application context is null", null)
            return
        }

        val app = (context.applicationContext as? android.app.Application)
            ?: (context as? android.app.Application)
            ?: run {
                result.error("NO_APPLICATION", "Application instance not found", null)
                return
            }

        currentApiSpaceId = apiSpaceId
        createNotificationChannel()

        val authenticator = object : ComapiAuthenticator() {
            override fun onAuthenticationChallenge(authClient: AuthClient, challengeOptions: ChallengeOptions) {
                val nonce = challengeOptions.nonce
                mainHandler.post {
                    channel.invokeMethod(
                        "onAuthenticationChallenge",
                        mapOf("nonce" to nonce),
                        object : MethodChannel.Result {
                            override fun success(jwtResult: Any?) {
                                if (jwtResult is String && jwtResult.isNotBlank()) {
                                    authClient.authenticateWithToken(jwtResult)
                                } else {
                                    authClient.authenticateWithToken(null)
                                }
                            }

                            override fun error(code: String, msg: String?, details: Any?) {
                                authClient.authenticateWithToken(null)
                            }

                            override fun notImplemented() {
                                authClient.authenticateWithToken(null)
                            }
                        }
                    )
                }
            }
        }

        val pushHandler = object : PushMessageListener {
            override fun onMessageReceived(message: RemoteMessage) {
                handleRemoteMessage(message)
            }
        }

        val config = ComapiConfig()
            .apiSpaceId(apiSpaceId)
            .authenticator(authenticator)
            .pushMessageListener(pushHandler)

        val replied = java.util.concurrent.atomic.AtomicBoolean(false)

        Comapi.initialiseShared(app, config, object : Callback<ComapiClient> {
            override fun success(client: ComapiClient) {
                isSdkInitialized = true
                // If the app was cold-started by tapping a notification before the SDK was initialized,
                // report the click tracking data to Dotdigital now.
                val pendingIntent = pendingTrackingIntent
                val activity = currentActivity
                if (pendingIntent != null && activity != null) {
                    pendingTrackingIntent = null
                    client.handlePushNotification(activity, pendingIntent, false, object : Callback<PushHandleResult> {
                        override fun success(res: PushHandleResult?) {}
                        override fun error(t: Throwable) {}
                    })
                }
                if (replied.compareAndSet(false, true)) {
                    mainHandler.post {
                        result.success(true)
                    }
                }
            }

            override fun error(t: Throwable) {
                if (replied.compareAndSet(false, true)) {
                    mainHandler.post {
                        result.error("INIT_FAILED", t.message, null)
                    }
                }
            }
        })
    }

    /**
     * Handles an incoming FCM [RemoteMessage].
     * Distinguishes between visual/foreground notifications and silent background data pushes (`dd_data`).
     */
    private fun handleRemoteMessage(message: RemoteMessage) {
        // Ignore incoming push messages if there is no active Comapi session
        val client = try {
            Comapi.getShared()
        } catch (e: Exception) {
            null
        }
        if (client?.session?.isSuccessfullyCreated != true) {
            return
        }

        // Deduplicate in case multiple broadcast receivers were registered before re-init
        val now = System.currentTimeMillis()
        val msgId = message.messageId ?: "${message.notification?.title}_${message.data}"
        if (msgId == lastHandledMessageId && (now - lastHandledMessageTime) < 2000L) {
            return
        }
        lastHandledMessageId = msgId
        lastHandledMessageTime = now

        val details: PushDetails? = try {
            ComapiClient.parsePushMessage(message)
        } catch (e: JSONException) {
            null
        }

        val notification = message.notification
        val rawData = HashMap<String, Any?>(message.data)
        val sdkCustomData = jsonObjectToMap(details?.data)
        val customDataMap = if (sdkCustomData.isNotEmpty()) sdkCustomData else extractCustomDataFromMap(rawData)
        val resolvedUrl = details?.url?.takeIf { it.isNotBlank() } ?: extractUrlFromMap(rawData)

        if (notification == null) {
            // Silent / Data-only Push
            val silentEvent = mapOf(
                "customData" to customDataMap,
                "rawPayload" to message.data,
                "timestamp" to now
            )
            mainHandler.post {
                channel.invokeMethod("onSilentPushReceived", silentEvent)
            }
        } else {
            // Foreground / Displayable Push Notification
            val pushEvent = mapOf(
                "title" to notification.title,
                "body" to notification.body,
                "deepLinkUrl" to resolvedUrl,
                "customData" to customDataMap,
                "rawPayload" to message.data,
                "timestamp" to now
            )

            mainHandler.post {
                channel.invokeMethod("onPushReceived", pushEvent)
            }

            // Post to Android System Tray as documented in Dotdigital foreground guide
            postForegroundNotification(notification.title, notification.body, resolvedUrl, customDataMap, message.data)
        }
    }

    /**
     * Posts a foreground notification to the Android System Tray using [NotificationCompat.Builder],
     * ensuring users receive notifications even while the app is active in the foreground.
     */
    private fun postForegroundNotification(
        title: String?,
        body: String?,
        deepLinkUrl: String?,
        customData: Map<String, Any?>,
        rawData: Map<String, String> = emptyMap()
    ) {
        val context = applicationContext ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS)
            != PackageManager.PERMISSION_GRANTED
        ) {
            return
        }

        val notificationId = (System.currentTimeMillis() and 0x7FFFFFFF).toInt()

        // IMPORTANT: Do NOT use packageManager.getLaunchIntentForPackage() with CATEGORY_LAUNCHER,
        // because Android ignores launcher intents and drops their extras when the Activity is already
        // in the foreground. Target the Activity class directly with a unique action so MainActivity.onNewIntent()
        // is always invoked when the user clicks the system-tray notification.
        val act = currentActivity
        val baseIntent = if (act != null) {
            Intent(context, act.javaClass)
        } else {
            context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
                removeCategory(Intent.CATEGORY_LAUNCHER)
            }
        }

        val launchIntent = baseIntent?.apply {
            action = "com.dotdigital.push.NOTIFICATION_TAP_$notificationId"
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            deepLinkUrl?.let { putExtra("url", it) }
            // Preserve raw Dotdigital extras (e.g. dd_deepLink, dd_data, dd_originated)
            // so client.handlePushNotification can track clicks if tapped from the system tray
            for ((key, value) in rawData) {
                putExtra(key, value)
            }
            for ((key, value) in customData) {
                if (value != null) putExtra(key, value.toString())
            }
        }

        val pendingIntent = PendingIntent.getActivity(
            context,
            notificationId,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val smallIconRes = context.resources.getIdentifier(
            "ic_notification",
            "drawable",
            context.packageName
        ).let { if (it != 0) it else android.R.drawable.ic_dialog_info }

        val builder = NotificationCompat.Builder(context, NOTIFICATION_CHANNEL_ID)
            .setAutoCancel(true)
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .setWhen(System.currentTimeMillis())
            .setSmallIcon(smallIconRes)
            .setContentTitle(title ?: "Dotdigital Push")
            .setContentText(body ?: "")
            .setContentIntent(pendingIntent)

        NotificationManagerCompat.from(context).notify(notificationId, builder.build())
    }

    /**
     * Creates the Android [NotificationChannel] required on Android 8.0 (API level 26) and higher.
     */
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val context = applicationContext ?: return
            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "Dotdigital Notifications",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Default channel for Dotdigital mobile push notifications"
            }
            val manager = context.getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }
    }

    /**
     * Requests runtime notification permission on Android 13+ (POST_NOTIFICATIONS).
     */
    private fun requestPermissions(result: MethodChannel.Result) {
        val activity = currentActivity
        if (activity == null) {
            result.error("NO_ACTIVITY", "Cannot request permissions without active Activity", null)
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val granted = ContextCompat.checkSelfPermission(
                activity,
                Manifest.permission.POST_NOTIFICATIONS
            ) == PackageManager.PERMISSION_GRANTED

            if (granted) {
                result.success(true)
            } else {
                pendingPermissionResult = result
                activity.getSharedPreferences("dotdigital_push", Context.MODE_PRIVATE)
                    .edit().putBoolean("permission_requested", true).apply()
                ActivityCompat.requestPermissions(
                    activity,
                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                    PERMISSION_REQUEST_CODE
                )
            }
        } else {
            result.success(true)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ): Boolean {
        if (requestCode == PERMISSION_REQUEST_CODE) {
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            val pending = pendingPermissionResult
            pendingPermissionResult = null
            pending?.success(granted)
            return true
        }
        return false
    }

    private fun fetchFcmToken(onComplete: (String?) -> Unit) {
        FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
            val freshToken = if (task.isSuccessful) task.result else null
            if (!freshToken.isNullOrBlank()) {
                cachedFcmToken = freshToken
            }
            onComplete(freshToken)
        }
    }

    /**
     * Starts a push session using [ComapiClient.service().session().startSession].
     */
    private fun startSession(result: MethodChannel.Result) {
        val client = getComapiClientOrError(result) ?: return
        val replied = java.util.concurrent.atomic.AtomicBoolean(false)

        client.service().session().startSession(object : Callback<Session> {
            override fun success(session: Session) {
                if (replied.compareAndSet(false, true)) {
                    mainHandler.post { result.success(session.isSuccessfullyCreated) }
                }
            }

            override fun error(t: Throwable) {
                if (replied.compareAndSet(false, true)) {
                    mainHandler.post { result.error("START_SESSION_FAILED", t.message, null) }
                }
            }
        })
    }

    /** Ends the push session while leaving the device's FCM token valid. */
    private fun endSession(result: MethodChannel.Result) {
        val client = getComapiClientOrError(result) ?: return
        val replied = java.util.concurrent.atomic.AtomicBoolean(false)

        if (client.session?.isSuccessfullyCreated != true) {
            if (replied.compareAndSet(false, true)) {
                mainHandler.post { result.success(true) }
            }
            return
        }

        client.service().session().endSession(object : Callback<ComapiResult<Void>> {
            override fun success(res: ComapiResult<Void>?) {
                if (res?.isSuccessful != true) {
                    if (replied.compareAndSet(false, true)) {
                        mainHandler.post { result.error("END_SESSION_FAILED", res?.message, null) }
                    }
                    return
                }
                if (replied.compareAndSet(false, true)) {
                    mainHandler.post { result.success(true) }
                }
            }

            override fun error(t: Throwable) {
                if (replied.compareAndSet(false, true)) {
                    mainHandler.post { result.error("END_SESSION_FAILED", t.message, null) }
                }
            }
        })
    }

    /**
     * Public method channel handler to patch the user profile with an email address.
     */
    private fun updateProfileEmail(email: String, result: MethodChannel.Result) {
        val client = getComapiClientOrError(result) ?: return
        val session = client.session

        if (session == null || !session.isSuccessfullyCreated) {
            result.error("NO_ACTIVE_SESSION", "An active session is required before updating email", null)
            return
        }

        updateProfileEmailInternal(client, session.profileId, email, result)
    }

    /**
     * Executes the 2-step profile update required by the Comapi Foundation SDK:
     * 1. Fetches current profile to obtain the latest `eTag`.
     * 2. Patches profile with the email and `eTag`.
     */
    private fun updateProfileEmailInternal(
        client: ComapiClient,
        profileId: String,
        email: String,
        resultCallback: MethodChannel.Result?
    ) {
        val replied = java.util.concurrent.atomic.AtomicBoolean(false)

        // Step 1: Retrieve profile to get current eTag
        client.service().profile().getProfile(
            profileId,
            object : Callback<ComapiResult<Map<String, Any>>> {
                override fun success(getRes: ComapiResult<Map<String, Any>>) {
                    if (!getRes.isSuccessful) {
                        if (replied.compareAndSet(false, true)) {
                            mainHandler.post { resultCallback?.error("GET_PROFILE_FAILED", getRes.message, null) }
                        }
                        return
                    }
                    val eTag = getRes.getETag()
                    val patchMap = mapOf<String, Any>("email" to email)

                    // Step 2: Patch profile with eTag and email
                    client.service().profile().patchMyProfile(
                        patchMap,
                        eTag,
                        object : Callback<ComapiResult<Map<String, Any>>> {
                            override fun success(patchRes: ComapiResult<Map<String, Any>>) {
                                if (replied.compareAndSet(false, true)) {
                                    mainHandler.post {
                                        if (patchRes.isSuccessful) resultCallback?.success(true)
                                        else resultCallback?.error("PATCH_PROFILE_FAILED", patchRes.message, null)
                                    }
                                }
                            }

                            override fun error(t: Throwable) {
                                if (replied.compareAndSet(false, true)) {
                                    mainHandler.post {
                                        resultCallback?.error("PATCH_PROFILE_FAILED", t.message, null)
                                    }
                                }
                            }
                        }
                    )
                }

                override fun error(t: Throwable) {
                    if (replied.compareAndSet(false, true)) {
                        mainHandler.post {
                            resultCallback?.error("GET_PROFILE_FAILED", t.message, null)
                        }
                    }
                }
            }
        )
    }

    /**
     * Retrieves the active FCM registration token via [FirebaseMessaging.getInstance().token].
     */
    private fun getPushToken(result: MethodChannel.Result) {
        FirebaseMessaging.getInstance().token
            .addOnCompleteListener { task ->
                if (task.isSuccessful) {
                    cachedFcmToken = task.result
                    result.success(task.result)
                } else {
                    result.error("TOKEN_ERROR", task.exception?.message, null)
                }
            }
    }

    /**
     * Retrieves current session state and the device's FCM token.
     */
    private fun getSessionState(result: MethodChannel.Result) {
        val client = try {
            Comapi.getShared()
        } catch (e: Exception) {
            null
        }

        val session = client?.session
        val isActive = session?.isSuccessfullyCreated == true
        val profileId = session?.profileId

        fetchFcmToken { token ->
            result.success(mapOf(
                "isSessionActive" to isActive,
                "profileId" to profileId,
                "pushToken" to (token ?: cachedFcmToken),
                "currentEmail" to currentEmail
            ))
        }
    }

    /**
     * Returns the shared [ComapiClient] singleton, or sends an error to Flutter if not initialized.
     */
    private fun getComapiClientOrError(result: MethodChannel.Result): ComapiClient? {
        return try {
            Comapi.getShared()
        } catch (e: Exception) {
            result.error("NOT_INITIALIZED", "Dotdigital SDK has not been initialized. Call initialize() first.", null)
            null
        }
    }

    /**
     * Extracts a URL or deep link from `dd_deepLink`, `dd_data`, or top-level payload keys
     * (`url`, `deepLink`, `deeplink`, `link`, `uri`).
     */
    private fun extractUrlFromMap(map: Map<String, Any?>): String? {
        val urlKeys = listOf("url", "deepLink", "deeplink", "link", "uri")
        for (key in urlKeys) {
            val direct = (map[key] as? String)?.trim()
            if (!direct.isNullOrBlank()) return direct
        }

        val ddDeepLink = map["dd_deepLink"]
        when (ddDeepLink) {
            is String -> {
                try {
                    val json = JSONObject(ddDeepLink)
                    for (key in urlKeys) {
                        val v = json.optString(key, "").trim()
                        if (v.isNotEmpty()) return v
                    }
                } catch (_: Exception) {}
            }
            is Map<*, *> -> {
                for (key in urlKeys) {
                    val v = (ddDeepLink[key] as? String)?.trim()
                    if (!v.isNullOrBlank()) return v
                }
            }
        }

        val ddData = map["dd_data"]
        when (ddData) {
            is String -> {
                val trimmed = ddData.trim()
                if (trimmed.startsWith("http://", ignoreCase = true) ||
                    trimmed.startsWith("https://", ignoreCase = true) ||
                    trimmed.startsWith("ddexample://", ignoreCase = true)
                ) {
                    return trimmed
                }
                try {
                    val json = JSONObject(trimmed)
                    for (key in urlKeys) {
                        val v = json.optString(key, "").trim()
                        if (v.isNotEmpty()) return v
                    }
                } catch (_: Exception) {}
            }
            is Map<*, *> -> {
                for (key in urlKeys) {
                    val v = (ddData[key] as? String)?.trim()
                    if (!v.isNullOrBlank()) return v
                }
            }
        }

        return null
    }

    /**
     * Extracts custom data map from `dd_data` (whether JSON string or nested map).
     */
    private fun extractCustomDataFromMap(map: Map<String, Any?>): Map<String, Any?> {
        val ddData = map["dd_data"] ?: return emptyMap()
        return when (ddData) {
            is String -> {
                try {
                    jsonObjectToMap(JSONObject(ddData))
                } catch (_: Exception) {
                    mapOf("value" to ddData)
                }
            }
            is JSONObject -> jsonObjectToMap(ddData)
            is Map<*, *> -> {
                val res = mutableMapOf<String, Any?>()
                for ((k, v) in ddData) {
                    if (k != null) res[k.toString()] = v
                }
                res
            }
            else -> emptyMap()
        }
    }

    /**
     * Converts a native [JSONObject] into a nested [Map] compatible with Flutter's platform channel codec.
     */
    private fun jsonObjectToMap(json: JSONObject?): Map<String, Any?> {
        if (json == null) return emptyMap()
        val map = mutableMapOf<String, Any?>()
        val keys = json.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            val value = json.opt(key)
            if (value is JSONObject) {
                map[key] = jsonObjectToMap(value)
            } else {
                map[key] = value
            }
        }
        return map
    }
}
