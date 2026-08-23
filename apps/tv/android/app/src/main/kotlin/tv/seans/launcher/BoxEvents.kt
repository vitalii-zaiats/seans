package tv.seans.launcher

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

/**
 * Everything the box has to say without being asked.
 *
 * Two sources, one stream: a broadcast receiver for apps arriving and leaving,
 * and a network callback for what the box is connected by. Both are registered
 * only while somebody is listening — a launcher is the one app that is always
 * running, so a receiver it forgets to unregister is one that outlives every
 * reason it existed.
 */
class BoxEvents(private val context: Context) : EventChannel.StreamHandler {

    private val main = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null

    /** What was last reported, so an unchanged network isn't sent twice. */
    private var link: String? = null

    private val packages = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            // `replaced` arrives as a REMOVED with a flag on it, immediately
            // followed by an ADDED. Both mean the same thing to a grid.
            send(mapOf("kind" to "packages"))
        }
    }

    private val networks = object : ConnectivityManager.NetworkCallback() {
        override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) =
            report(caps)

        override fun onLost(network: Network) = report(null)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events

        context.registerReceiver(
            packages,
            IntentFilter().apply {
                addAction(Intent.ACTION_PACKAGE_ADDED)
                addAction(Intent.ACTION_PACKAGE_REMOVED)
                addAction(Intent.ACTION_PACKAGE_REPLACED)
                addAction(Intent.ACTION_PACKAGE_CHANGED)
                // Without this the filter matches nothing: these four all carry
                // their subject as a `package:` URI rather than as an extra.
                addDataScheme("package")
            },
        )

        // Says the current state as soon as it is registered, which is what
        // puts the right icon in the corner on the first frame rather than
        // leaving it blank until the cable is pulled out.
        connectivity()?.registerDefaultNetworkCallback(networks)
    }

    override fun onCancel(arguments: Any?) {
        runCatching { context.unregisterReceiver(packages) }
        runCatching { connectivity()?.unregisterNetworkCallback(networks) }
        sink = null
        link = null
    }

    /** HOME, pressed while this already was home. */
    fun home() = send(mapOf("kind" to "home"))

    private fun report(caps: NetworkCapabilities?) {
        val kind = when {
            caps == null -> "none"
            !caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) -> "none"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
            // A transport this doesn't name — USB tethering, VPN — is still a
            // network, and the corner should not claim the box is offline.
            else -> "ethernet"
        }
        if (kind == link) return
        link = kind
        send(mapOf("kind" to "link", "link" to kind))
    }

    /**
     * Both callbacks arrive on a binder thread, and a sink may only be touched
     * on the main one.
     */
    private fun send(event: Map<String, Any>) = main.post { sink?.success(event) }

    private fun connectivity() =
        context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
}
