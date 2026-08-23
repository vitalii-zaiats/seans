package tv.seans.launcher

import android.app.Activity
import android.content.Context
import android.hardware.display.DisplayManager
import android.os.Build
import android.util.DisplayMetrics
import android.view.Display

/**
 * What the panel is actually running at.
 *
 * Worth asking Android directly rather than trusting what the interface
 * measures: a box can render at 1080p and hand that to a 4K panel to upscale,
 * and from inside the app the two are indistinguishable — everything just looks
 * soft. The mode says which is happening.
 */
class Screen(private val activity: Activity) {

    private val context: Context get() = activity

    fun info(): Map<String, Any?> {
        val display = display() ?: return emptyMap()

        val metrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        display.getRealMetrics(metrics)

        val mode = display.mode

        return mapOf(
            // The HDMI link: what the box is sending to the panel.
            "modeWidth" to mode?.physicalWidth,
            "modeHeight" to mode?.physicalHeight,
            "refreshRate" to (mode?.refreshRate?.toDouble() ?: 0.0),

            // The surface Android hands to the app, in real pixels. Where this
            // is smaller than the mode, something between the two is scaling.
            "surfaceWidth" to metrics.widthPixels,
            "surfaceHeight" to metrics.heightPixels,

            "densityDpi" to metrics.densityDpi,
            "density" to metrics.density.toDouble(),

            // Every mode the panel accepts, so a 4K one sitting unused is
            // visible rather than guessed at.
            "modes" to (display.supportedModes?.map {
                mapOf(
                    "id" to it.modeId,
                    "width" to it.physicalWidth,
                    "height" to it.physicalHeight,
                    "refreshRate" to it.refreshRate.toDouble(),
                    "active" to (it.modeId == mode?.modeId),
                )
            } ?: emptyList()),

            // What this window has asked for, which is not always what it got:
            // the system may refuse, and then the two disagree.
            "preferredModeId" to activity.window.attributes.preferredDisplayModeId,
        )
    }

    /**
     * Asks the system for a particular display mode while this window is up.
     *
     * The documented, permission-free way to change what the box outputs — the
     * same one a video player uses to match a film's frame rate. `0` gives the
     * choice back to the system.
     *
     * A request, not a command: the system may ignore it, which is why the
     * screen shows the mode that is actually running rather than the one asked
     * for.
     */
    fun preferMode(modeId: Int): Boolean {
        val params = activity.window.attributes
        params.preferredDisplayModeId = modeId
        activity.window.attributes = params
        return true
    }

    private fun display(): Display? {
        val manager = context.getSystemService(Context.DISPLAY_SERVICE)
            as? DisplayManager ?: return null

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            manager.getDisplay(Display.DEFAULT_DISPLAY)
        } else {
            @Suppress("DEPRECATION")
            manager.displays.firstOrNull()
        }
    }
}
