package tv.seans.launcher

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * The home screen's Android half.
 *
 * Nothing but wiring: one method channel for the questions Dart asks, one event
 * channel for the answers that arrive on their own, and the one thing an
 * activity has that neither of those does — knowing that HOME was pressed.
 */
class MainActivity : FlutterActivity() {

    private lateinit var apps: Apps
    private lateinit var installer: Installer
    private lateinit var files: Files
    private lateinit var lan: Lan
    private lateinit var screen: Screen
    private lateinit var events: BoxEvents

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        apps = Apps(applicationContext)
        installer = Installer(applicationContext)
        files = Files(this)
        lan = Lan(applicationContext)
        screen = Screen(this)
        events = BoxEvents(applicationContext)

        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, CALLS).setMethodCallHandler { call, result ->
            when (call.method) {
                "installer" -> result.success(apps.installer())
                "apps" -> result.success(apps.installed())
                "art" -> result.success(apps.art(call.arguments as String))
                "launch" -> result.success(apps.launch(call.arguments as String))
                "settings" -> result.success(apps.settings())
                "wifi" -> result.success(apps.wifi())
                "storage" -> result.success(apps.storage())
                "abis" -> result.success(installer.abis())
                "stagingDir" -> result.success(installer.stagingDir())
                "canInstall" -> result.success(installer.canInstall())
                "requestInstall" -> result.success(installer.requestPermission())
                "install" -> result.success(installer.install(call.arguments as String))
                "clearStaging" -> result.success(installer.clearStaging())
                "canReadFiles" -> result.success(files.canRead())
                "requestReadFiles" -> result.success(files.requestRead())
                "roots" -> result.success(files.roots())
                "listDir" -> result.success(files.list(call.arguments as String))
                "openFile" -> result.success(files.open(call.arguments as String))
                "store" -> result.success(apps.store(call.arguments as String))
                "openWeb" -> {
                    val args = call.arguments as Map<*, *>
                    startActivity(
                        WebActivity.intent(
                            this,
                            args["url"] as String,
                            args["agent"] as? String,
                        )
                    )
                    result.success(true)
                }
                "screen" -> result.success(screen.info())
                "preferMode" -> result.success(
                    screen.preferMode(call.arguments as Int)
                )
                "holdMulticast" -> result.success(lan.holdMulticast())
                "releaseMulticast" -> result.success(lan.releaseMulticast())
                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, EVENTS).setStreamHandler(events)
    }

    /**
     * HOME, pressed on a launcher that is already the thing on screen.
     *
     * `singleTask` means this arrives here rather than starting the activity
     * again, and by then the screen may be scrolled halfway down the rails.
     * Somebody who presses HOME wants the top of it — the same thing HOME does
     * everywhere else.
     */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.hasCategory(Intent.CATEGORY_HOME)) events.home()
    }

    private companion object {
        const val CALLS = "tv.seans/launcher"
        const val EVENTS = "tv.seans/launcher/events"
    }
}
