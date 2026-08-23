package tv.seans.launcher

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import java.io.File

/**
 * Putting an APK on the box.
 *
 * Not a silent install: without Device Owner — which means a factory-fresh box
 * and `adb dpm set-device-owner` — no third-party app may install another one
 * on its own. What it can do is hand the file to the system's own installer,
 * which asks the owner and does the work. That confirmation is the only thing
 * standing between a launcher and the ability to install anything it likes, so
 * it is not something to route around.
 */
class Installer(private val context: Context) {

    /**
     * The processor architectures this box runs, best first.
     *
     * The catalogue builds a separate APK per architecture and suggests one of
     * them for every device there is, so this is what decides which download is
     * the right one. Get it wrong and Android refuses the install with
     * `INSTALL_FAILED_NO_MATCHING_ABIS` after the whole file has come down.
     */
    fun abis(): List<String> = Build.SUPPORTED_ABIS.toList()

    /**
     * Where a download should land.
     *
     * Inside the app's own cache: no storage permission, cleaned up by the
     * system under pressure, and reachable by the installer only through the
     * provider below.
     */
    fun stagingDir(): String =
        File(context.cacheDir, "apk").apply { mkdirs() }.absolutePath

    /**
     * Whether the owner has already allowed this app to install others.
     *
     * Before Android 8 the permission was granted at install time and there was
     * no per-app switch, so there is nothing to ask about.
     */
    fun canInstall(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            context.packageManager.canRequestPackageInstalls()

    /** Opens the settings screen that grants it. */
    fun requestPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return true
        return start(
            Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:${context.packageName}"),
            )
        )
    }

    /** Hands a downloaded APK to the system installer. */
    fun install(path: String): Boolean {
        val file = File(path)
        if (!file.isFile) return false

        val uri = FileProvider.getUriForFile(context, AUTHORITY, file)
        return start(
            Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
        )
    }

    /** Removes everything staged. Called once an install has been handed over. */
    fun clearStaging(): Boolean {
        File(context.cacheDir, "apk").listFiles()?.forEach { it.delete() }
        return true
    }

    private fun start(intent: Intent): Boolean = try {
        context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        true
    } catch (_: Exception) {
        // No installer, or the box's ROM removed the settings screen. Either
        // way the caller wants to hear about it rather than crash.
        false
    }

    private companion object {
        /** Must match the provider declared in the manifest. */
        const val AUTHORITY = "tv.seans.launcher.files"
    }
}
