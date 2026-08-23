package tv.seans.launcher

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.storage.StorageManager
import android.provider.Settings
import android.webkit.MimeTypeMap
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import java.io.File

/**
 * Reading what is on the box's own drives.
 *
 * Takes the Activity rather than the application context: asking for the
 * legacy storage permission needs one, and this object never outlives the
 * screen that owns it anyway.
 */
class Files(private val activity: Activity) {

    /**
     * Whether this app may read the drives at all.
     *
     * Two different permissions depending on the box's age. Up to Android 10 it
     * is the ordinary runtime one. From Android 11 the ordinary one grants
     * media only — photos, video, audio — and browsing a stick means *All
     * files access*, which has no dialog: only a settings screen the owner has
     * to walk into.
     */
    fun canRead(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            ContextCompat.checkSelfPermission(
                activity,
                Manifest.permission.READ_EXTERNAL_STORAGE,
            ) == PackageManager.PERMISSION_GRANTED
        }

    /** Asks for it, whichever of the two this box wants. */
    fun requestRead(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            ActivityCompat.requestPermissions(
                activity,
                arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE),
                READ_REQUEST,
            )
            return true
        }

        return runCatching {
            activity.startActivity(
                Intent(
                    Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                    Uri.parse("package:${activity.packageName}"),
                )
            )
        }.recoverCatching {
            // Some boxes ship without the per-app screen; the list of every app
            // is the fallback, and the owner finds this one in it.
            activity.startActivity(
                Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)
            )
        }.isSuccess
    }

    /**
     * Where browsing starts: one entry per drive, at the drive's own root.
     *
     * Derived from the app's own directories rather than guessed. Android hands
     * out `…/Android/data/<package>/files` per volume, and everything before
     * that is the volume — which is the documented layout and the only way to
     * learn a removable drive's path without root.
     */
    fun roots(): List<Map<String, Any?>> {
        val manager = activity.getSystemService(Context.STORAGE_SERVICE)
            as? StorageManager

        return activity.getExternalFilesDirs(null)
            .filterNotNull()
            .mapIndexedNotNull { index, dir ->
                val path = dir.absolutePath.substringBefore("/Android/data/")
                if (path.isEmpty() || !File(path).isDirectory) {
                    return@mapIndexedNotNull null
                }

                val described = runCatching {
                    manager?.getStorageVolume(dir)?.getDescription(activity)
                }.getOrNull()

                mapOf(
                    "label" to (described
                        ?: if (index == 0) "Внутрішня пам'ять" else "Знімний носій"),
                    "path" to path,
                    "removable" to (index > 0),
                )
            }
    }

    /**
     * One directory, folders first and then by name.
     *
     * Sorted here rather than in Dart because the comparison is on the file
     * system's own names, and sending an unsorted list of a thousand entries
     * across the channel only to sort it there is work for nothing.
     */
    fun list(path: String): List<Map<String, Any?>> {
        val dir = File(path)
        if (!dir.isDirectory) return emptyList()

        return dir.listFiles().orEmpty()
            .filter { !it.isHidden }
            .sortedWith(
                compareByDescending<File> { it.isDirectory }
                    .thenBy { it.name.lowercase() }
            )
            .map {
                mapOf(
                    "name" to it.name,
                    "path" to it.absolutePath,
                    "dir" to it.isDirectory,
                    // Long: a film is bigger than an Int of bytes.
                    "size" to it.length(),
                    "modified" to it.lastModified(),
                )
            }
    }

    /** Hands a file to whatever on the box claims to open its kind. */
    fun open(path: String): Boolean {
        val file = File(path)
        if (!file.isFile) return false

        val uri = FileProvider.getUriForFile(activity, AUTHORITY, file)
        val type = MimeTypeMap.getSingleton()
            .getMimeTypeFromExtension(file.extension.lowercase())
            ?: "*/*"

        return runCatching {
            activity.startActivity(
                Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(uri, type)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
            )
        }.isSuccess
    }

    private companion object {
        const val AUTHORITY = "tv.seans.launcher.files"
        const val READ_REQUEST = 41
    }
}
