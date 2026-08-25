package com.example.hoza_send

import android.content.ActivityNotFoundException
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * The two things HozaSend needs from Android that Dart cannot reach.
 *
 * A Wi-Fi multicast lock, because Android filters broadcast packets once Wi-Fi
 * power saving kicks in - which is exactly what silences discovery when the
 * screen dims. And MediaStore, because scoped storage means a received file
 * cannot simply be written into the public Downloads folder with a path.
 */
class MainActivity : FlutterActivity() {

    private var multicastLock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WIFI_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "acquire" -> {
                        acquireLock()
                        result.success(true)
                    }
                    "release" -> {
                        releaseLock()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, STORAGE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "publishToDownloads" -> {
                        val path = call.argument<String>("path")
                        val name = call.argument<String>("name")
                        if (path == null || name == null) {
                            result.success(null)
                        } else {
                            result.success(
                                publishToDownloads(
                                    path,
                                    name,
                                    call.argument<String>("mimeType"),
                                ),
                            )
                        }
                    }
                    "openFile" -> {
                        val target = call.argument<String>("target")
                        result.success(
                            target != null &&
                                openFile(target, call.argument<String>("mimeType")),
                        )
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // --- Discovery -----------------------------------------------------------

    private fun acquireLock() {
        if (multicastLock?.isHeld == true) return
        val wifi = applicationContext
            .getSystemService(Context.WIFI_SERVICE) as? WifiManager ?: return
        // Not reference counted: acquire and release are driven by one caller,
        // and a leaked count would keep the radio awake for the whole session.
        multicastLock = wifi.createMulticastLock(LOCK_TAG).apply {
            setReferenceCounted(false)
            acquire()
        }
    }

    private fun releaseLock() {
        multicastLock?.let { if (it.isHeld) it.release() }
        multicastLock = null
    }

    override fun onDestroy() {
        // The radio must not be left awake if the activity goes away while
        // discovery is still running.
        releaseLock()
        super.onDestroy()
    }

    // --- Storage -------------------------------------------------------------

    /**
     * Moves a finished file from the app's own folder into Downloads/HozaSend,
     * and returns where it landed, or null if it could not be published.
     *
     * The transfer is streamed and verified into private storage first, so this
     * only ever runs on a complete, checked file. That costs one extra copy,
     * which is the price of scoped storage: MediaStore hands back a stream, not
     * a path, so there is nothing for the receiver to have written into
     * directly.
     */
    private fun publishToDownloads(
        sourcePath: String,
        displayName: String,
        mimeType: String?,
    ): Map<String, String?>? {
        val source = File(sourcePath)
        if (!source.exists()) return null

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            publishViaMediaStore(source, displayName, mimeType)
        } else {
            publishViaFile(source, displayName)
        }
    }

    /**
     * Opens a received file in whatever app the device uses for its kind.
     *
     * The type decides everything: an image goes to the gallery, a PDF to a
     * reader, an archive to a file manager. Android already knows which app
     * that is, so this only has to say what is being offered and let the
     * system pick.
     *
     * [target] is a MediaStore URI for anything published under scoped
     * storage, and a plain path on the older phones where Downloads was still
     * a folder. A path has to be handed over as a content URI either way -
     * since API 24 passing a file:// URI to another app throws.
     */
    private fun openFile(target: String, mimeType: String?): Boolean {
        val uri: Uri = if (target.startsWith("content://")) {
            Uri.parse(target)
        } else {
            val file = File(target)
            if (!file.exists()) return false
            try {
                FileProvider.getUriForFile(
                    applicationContext,
                    "$packageName.fileprovider",
                    file,
                )
            } catch (error: IllegalArgumentException) {
                // Outside every path the provider is willing to share.
                return false
            }
        }

        // An unknown extension arrives as "some binary", which matches almost
        // nothing. Offering it as any type instead is the difference between a
        // chooser with every reader in it and a chooser with nothing in it.
        val type = if (mimeType.isNullOrEmpty() ||
            mimeType == "application/octet-stream"
        ) {
            "*/*"
        } else {
            mimeType
        }

        val view = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, type)
            // The receiving app is a different process; without this it gets a
            // URI it is not allowed to read.
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }

        // Asked first, so "nothing here opens this" comes back as an answer the
        // app can say out loud. A chooser with no apps in it would otherwise
        // open anyway and leave the user staring at an empty sheet.
        @Suppress("DEPRECATION")
        if (packageManager.queryIntentActivities(view, 0).isEmpty()) return false

        // Always the chooser, never a silent hand-off. A photo should reach the
        // gallery and an APK the installer - but which gallery, and whether
        // this time it should go to an editor instead, is the user's call, and
        // a default set once months ago is not an answer to that.
        val chooser = Intent.createChooser(view, "Open with").apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

        return try {
            startActivity(chooser)
            true
        } catch (error: ActivityNotFoundException) {
            false
        }
    }

    private fun publishViaMediaStore(
        source: File,
        displayName: String,
        mimeType: String?,
    ): Map<String, String?>? {
        val resolver = applicationContext.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, displayName)
            put(
                MediaStore.Downloads.RELATIVE_PATH,
                "${Environment.DIRECTORY_DOWNLOADS}/$FOLDER",
            )
            if (mimeType != null) put(MediaStore.Downloads.MIME_TYPE, mimeType)
            // Hidden from other apps until the bytes are all there, so nothing
            // can pick up a half-written file.
            put(MediaStore.Downloads.IS_PENDING, 1)
        }

        val uri: Uri = resolver.insert(
            MediaStore.Downloads.EXTERNAL_CONTENT_URI,
            values,
        ) ?: return null

        return try {
            resolver.openOutputStream(uri)?.use { output ->
                source.inputStream().use { input -> input.copyTo(output, BUFFER) }
            } ?: throw IllegalStateException("no output stream")

            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            source.delete()
            // Two answers, because the file now has two identities. The first
            // is where a person would say it is - MediaStore renames on
            // collision, so it is a description rather than a guarantee. The
            // second is the row it was written as, which is the only handle
            // that can open it again: under scoped storage there is no path
            // back to a published file.
            mapOf(
                "location" to "${Environment.DIRECTORY_DOWNLOADS}/$FOLDER/$displayName",
                "uri" to uri.toString(),
            )
        } catch (error: Exception) {
            // Leaving a pending row behind would be an invisible file the user
            // could never clear.
            resolver.delete(uri, null, null)
            null
        }
    }

    /** Pre-scoped-storage path: a plain move, under WRITE_EXTERNAL_STORAGE. */
    private fun publishViaFile(
        source: File,
        displayName: String,
    ): Map<String, String?>? {
        val directory = File(
            Environment.getExternalStoragePublicDirectory(
                Environment.DIRECTORY_DOWNLOADS,
            ),
            FOLDER,
        )
        if (!directory.exists() && !directory.mkdirs()) return null

        val stem = displayName.substringBeforeLast('.', displayName)
        val extension = displayName.substringAfterLast('.', "")
        var target = File(directory, displayName)
        var counter = 1
        while (target.exists()) {
            val candidate =
                if (extension.isEmpty()) "$stem ($counter)"
                else "$stem ($counter).$extension"
            target = File(directory, candidate)
            counter++
        }

        return try {
            source.copyTo(target, overwrite = false)
            source.delete()
            // Here the path is both answers at once: on these versions the
            // file really is where it says it is, and the app may still open
            // it by path.
            mapOf("location" to target.absolutePath, "uri" to null)
        } catch (error: Exception) {
            null
        }
    }

    companion object {
        private const val WIFI_CHANNEL = "hozasend/wifi_lock"
        private const val STORAGE_CHANNEL = "hozasend/storage"
        private const val LOCK_TAG = "hozasend.discovery"
        private const val FOLDER = "HozaSend"
        private const val BUFFER = 64 * 1024
    }
}
