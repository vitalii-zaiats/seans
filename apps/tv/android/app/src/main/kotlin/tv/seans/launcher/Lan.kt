package tv.seans.launcher

import android.content.Context
import android.net.wifi.WifiManager

/**
 * The one thing looking for devices on the network needs from Android.
 *
 * Broadcast and multicast datagrams are dropped before an app ever sees them
 * unless something holds a multicast lock. Over Ethernet they arrive anyway,
 * which is what makes the absence of this look like a protocol bug rather than
 * a missing lock: the same code works on a wired box and finds nothing on a
 * wireless one.
 */
class Lan(private val context: Context) {

    private var lock: WifiManager.MulticastLock? = null

    /** Held only for the length of a scan — it costs battery and radio time. */
    fun holdMulticast(): Boolean {
        if (lock?.isHeld == true) return true

        val wifi = context.applicationContext
            .getSystemService(Context.WIFI_SERVICE) as? WifiManager ?: return false

        return runCatching {
            val held = wifi.createMulticastLock("seans-discovery")
            held.setReferenceCounted(false)
            held.acquire()
            lock = held
            true
        }.getOrDefault(false)
    }

    fun releaseMulticast(): Boolean {
        val held = lock ?: return true
        runCatching { if (held.isHeld) held.release() }
        lock = null
        return true
    }
}
