package tv.seans.launcher

import android.content.Context
import android.content.Intent
import android.content.pm.ResolveInfo
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.os.StatFs
import android.os.storage.StorageManager
import android.provider.Settings
import androidx.core.net.toUri
import java.io.ByteArrayOutputStream

/**
 * What is installed on this box, and how to start it.
 *
 * All of it is `PackageManager`, which is the only thing that knows. The apps
 * screen is one query; the rest here is the two shapes an app's artwork comes
 * in and the difference between them.
 */
class Apps(private val context: Context) {

    /**
     * Who installed this copy of the launcher.
     *
     * `com.android.vending` when it came from Google Play, another package when
     * it came from another shop, `null` for a sideload — Android reports no
     * installer at all for one, and that is the honest answer rather than a
     * missing one.
     *
     * The server decides two things from it, and neither is cosmetic: where an
     * update comes from, and which sections this build may show. A Play build
     * that sideloaded its own APK is a build that gets pulled from the shop.
     *
     * `getInstallSourceInfo` is the API that replaced the deprecated one, and
     * `initiatingPackageName` is the field that means what the old one meant:
     * who actually started the install, not who the package claims it came
     * from.
     */
    fun installer(): String? = runCatching {
        val packages = context.packageManager
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
            packages.getInstallSourceInfo(context.packageName).initiatingPackageName
        } else {
            @Suppress("DEPRECATION")
            packages.getInstallerPackageName(context.packageName)
        }
    }.getOrNull()

    /**
     * Everything with a way in, by label, this launcher excepted.
     *
     * Both categories, unioned. A television app files its entry under
     * `LEANBACK_LAUNCHER` and a phone app under `LAUNCHER`, and a box has both
     * on it — half of what anybody sideloads onto one of these was written for
     * a phone. A launcher that queried only the first would hide it, and the
     * owner would have installed something they cannot open.
     */
    fun installed(): List<Map<String, Any>> {
        val leanback = query(Intent.CATEGORY_LEANBACK_LAUNCHER).associateBy { it.packageName() }
        val plain = query(Intent.CATEGORY_LAUNCHER).associateBy { it.packageName() }

        return (leanback.keys + plain.keys)
            .asSequence()
            .filter { it != context.packageName }
            .mapNotNull { name ->
                val entry = leanback[name] ?: plain[name] ?: return@mapNotNull null
                mapOf(
                    "package" to name,
                    "label" to entry.loadLabel(context.packageManager).toString(),
                    "leanback" to (name in leanback),
                )
            }
            .sortedBy { (it["label"] as String).lowercase() }
            .toList()
    }

    /**
     * One app's artwork, already a PNG.
     *
     * A banner is what Android asks a television app for — 320×180, drawn to be
     * a tile — and where there is one it is the whole answer. Where there isn't,
     * the icon is, and the caller is told which it got, because the two want
     * laying out differently and stretching an icon into a banner's shape is
     * how a launcher fills up with blurry squares.
     */
    fun art(name: String): Map<String, Any>? {
        val packages = context.packageManager
        val entry = entry(name) ?: return null

        val banner = entry.activityInfo.loadBanner(packages)
        val drawable = banner ?: entry.loadIcon(packages) ?: return null
        val bytes = when (banner) {
            null -> drawable.fitted(ICON, ICON)
            else -> drawable.png(BANNER, BANNER * 9 / 16)
        } ?: return null

        return mapOf("bytes" to bytes, "banner" to (banner != null))
    }

    /** True when there was something to start. */
    fun launch(name: String): Boolean = start(intent(name))

    /**
     * The box's own settings. There is no version of these a launcher could
     * draw itself — inputs, network and storage all belong to the system.
     */
    fun settings(): Boolean =
        start(Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))

    /**
     * The Wi-Fi picker, as close to in-app as Android allows.
     *
     * Drawing our own list is possible — `getScanResults` — but pointless: since
     * Android 10 a third-party app cannot join the *system* to a network.
     * `WifiNetworkSpecifier` binds the result to this app alone, which is no use
     * to a box whose whole job is to be online. So the system picker it is.
     *
     * `Settings.Panel.ACTION_WIFI` slides over the app rather than throwing the
     * viewer out to Settings, but it is a phone-shaped API and plenty of
     * televisions do not implement it — hence the fallback, and hence returning
     * which one was reached so the screen can word itself honestly.
     */
    fun wifi(): Boolean {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
            val panel = Intent(Settings.Panel.ACTION_WIFI)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (start(panel)) return true
        }
        return start(
            Intent(Settings.ACTION_WIFI_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
    }

    /**
     * The volumes this box can write to, with how full each one is.
     *
     * `getExternalFilesDirs` is what gives the *set* of volumes — internal
     * emulated storage first, then an SD card or a stick if one is mounted.
     * `StatFs` then reports on the filesystem each path sits on, so asking
     * about the app's own directory answers for the whole volume.
     *
     * The labels come from `StorageManager`, which knows what the owner calls
     * these; falling back to a positional guess only when it declines to say.
     */
    fun storage(): List<Map<String, Any>> {
        val manager = context.getSystemService(Context.STORAGE_SERVICE) as? StorageManager

        return context.getExternalFilesDirs(null)
            .filterNotNull()
            .mapIndexedNotNull { index, dir ->
                val stats = runCatching { StatFs(dir.absolutePath) }.getOrNull()
                    ?: return@mapIndexedNotNull null

                val described = runCatching {
                    manager?.getStorageVolume(dir)?.getDescription(context)
                }.getOrNull()

                mapOf(
                    "label" to (described
                        ?: if (index == 0) "Внутрішня пам'ять" else "Знімний носій"),
                    "path" to dir.absolutePath,
                    // Where browsing this drive starts. Android hands out
                    // `…/Android/data/<package>/files` per volume, and
                    // everything before that is the volume itself — the only
                    // way to learn a stick's path without root.
                    "root" to dir.absolutePath.substringBefore("/Android/data/"),
                    "removable" to (index > 0),
                    // Longs, because a 1 TB drive overflows an Int of bytes.
                    "total" to stats.totalBytes,
                    "free" to stats.availableBytes,
                )
            }
    }

    /**
     * Opens an app's page in whatever store the box has.
     *
     * For apps the launcher cannot fetch itself — Steam Link is on Play and
     * nowhere else, so F-Droid is no help. `market://` is what a store
     * registers for; the https address is the fallback for a box with no
     * store, where at least a browser may answer.
     */
    fun store(name: String): Boolean {
        val market = Intent(Intent.ACTION_VIEW, "market://details?id=$name".toUri())
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        val web = Intent(
            Intent.ACTION_VIEW,
            "https://play.google.com/store/apps/details?id=$name".toUri(),
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

        return runCatching { context.startActivity(market) }
            .recoverCatching { context.startActivity(web) }
            .isSuccess
    }

    private fun intent(name: String): Intent? {
        val packages = context.packageManager
        val intent = packages.getLeanbackLaunchIntentForPackage(name)
            ?: packages.getLaunchIntentForPackage(name)
            ?: return null
        // Each app gets its own task. Without this they stack on the
        // launcher's, and Back out of one lands on another rather than at home.
        return intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }

    private fun start(intent: Intent?): Boolean {
        if (intent == null) return false
        return try {
            context.startActivity(intent)
            true
        } catch (_: android.content.ActivityNotFoundException) {
            // Uninstalled between the grid being drawn and the tile being
            // pressed. The package receiver is about to redraw it anyway.
            false
        } catch (_: SecurityException) {
            false
        }
    }

    private fun entry(name: String): ResolveInfo? =
        query(Intent.CATEGORY_LEANBACK_LAUNCHER).firstOrNull { it.packageName() == name }
            ?: query(Intent.CATEGORY_LAUNCHER).firstOrNull { it.packageName() == name }

    private fun query(category: String): List<ResolveInfo> {
        val intent = Intent(Intent.ACTION_MAIN, null).addCategory(category)
        return context.packageManager.queryIntentActivities(intent, 0)
    }

    private fun ResolveInfo.packageName(): String = activityInfo.packageName

    /**
     * A drawable rasterised at exactly this size, whatever it thinks its own
     * size is.
     *
     * Which is what a banner wants, and the intrinsic size is what makes it
     * necessary. A banner is 16:9 by Android's own contract and is drawn 16:9
     * by the tile, but plenty of them are drawn rather than shipped — a shape,
     * a layer-list, a vector — and a `LayerDrawable`'s intrinsic size is the
     * largest of its layers, which for a gradient with a rule across it is the
     * rule: 400×16. Fit *that* inside a box and the banner comes back as a
     * stripe, which stretched across a tile is a flat block of colour. So the
     * box wins, and the drawable is asked to draw itself into the shape it will
     * be seen in.
     */
    private fun Drawable.png(width: Int, height: Int): ByteArray? {
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        setBounds(0, 0, width, height)
        draw(Canvas(bitmap))

        val bytes = bitmap.png()
        bitmap.recycle()
        return bytes
    }

    /**
     * The same, for something whose own proportions are the point.
     *
     * An icon is square-ish and drawn small, so it is fitted inside the box and
     * never enlarged — an icon blown up to banner size is a blurry square,
     * which is the thing the two shapes exist to avoid. An adaptive icon has no
     * intrinsic size and takes the box.
     */
    private fun Drawable.fitted(boxWidth: Int, boxHeight: Int): ByteArray? {
        if (intrinsicWidth <= 0 || intrinsicHeight <= 0) return png(boxWidth, boxHeight)

        if (this is BitmapDrawable && bitmap != null && bitmap.width <= boxWidth) {
            return bitmap.png()
        }

        val scale = minOf(
            1f,
            boxWidth.toFloat() / intrinsicWidth,
            boxHeight.toFloat() / intrinsicHeight,
        )
        return png(
            (intrinsicWidth * scale).toInt().coerceAtLeast(1),
            (intrinsicHeight * scale).toInt().coerceAtLeast(1),
        )
    }

    private fun Bitmap.png(): ByteArray {
        val out = ByteArrayOutputStream()
        compress(Bitmap.CompressFormat.PNG, 100, out)
        return out.toByteArray()
    }

    private companion object {
        /** 320×180 is what Android asks a television app for; this is that,
         *  doubled, so a tile on a 4K panel has pixels to spend. */
        const val BANNER = 640

        /** An icon is drawn small in the tile and never wants more than this. */
        const val ICON = 192
    }
}
