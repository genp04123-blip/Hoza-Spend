package com.rahozosman.hozasend

import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.ContentResolver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.provider.Settings
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * The things HozaSend needs from Android that Dart cannot reach.
 *
 * A Wi-Fi multicast lock, because Android filters broadcast packets once Wi-Fi
 * power saving kicks in - which is exactly what silences discovery when the
 * screen dims. MediaStore, because scoped storage means a received file cannot
 * simply be written into the public Downloads folder with a path. And the
 * Storage Access Framework, because a file-sharing app cannot afford to copy
 * every file its user picks before it can send it - see [DocumentFiles].
 */
class MainActivity : FlutterActivity() {

    private var multicastLock: WifiManager.MulticastLock? = null
    private var linkLock: WifiManager.WifiLock? = null

    /** Picking and reading files without copying them first. */
    private val documents: DocumentFiles by lazy { DocumentFiles(this) }

    /** Kept so a share arriving later can be pushed to Dart. */
    private var shareChannel: MethodChannel? = null

    /** One thread, because copying a share is IO and order does not matter. */
    private val shareWorker: ExecutorService = Executors.newSingleThreadExecutor()

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
                    "acquireLink" -> {
                        acquireLinkLock()
                        result.success(true)
                    }
                    "releaseLink" -> {
                        releaseLinkLock()
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
                                    call.argument<String>("subPath").orEmpty(),
                                    // Milliseconds on the wire, seconds in
                                    // MediaStore; converted where it is used.
                                    call.argument<Number>("modified")?.toLong(),
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
                    "deleteFile" -> {
                        val target = call.argument<String>("target")
                        result.success(target != null && deleteReceivedFile(target))
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SETTINGS_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openWifi" -> result.success(openFirst(wifiScreens()))
                    "openHotspot" -> result.success(openFirst(hotspotScreens()))
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SESSION_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // One method for both starting and updating: starting a
                    // service that is already running is how Android delivers
                    // a new intent to it, so the two are the same call.
                    "show" -> result.success(
                        showSession(
                            call.argument<String>("title") ?: "HozaSend",
                            call.argument<String>("text").orEmpty(),
                            call.argument<Int>("progress") ?: -1,
                        ),
                    )
                    "hide" -> {
                        hideSession()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FILES_CHANNEL)
            .setMethodCallHandler { call, result -> documents.handle(call, result) }

        shareChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SHARE_CHANNEL,
        ).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    // Pulled rather than pushed: the share that launched the
                    // app has been sitting in the intent since before Dart
                    // existed, so the app asks for it once it is listening.
                    "consume" -> takeShared { paths -> result.success(paths) }
                    else -> result.notImplemented()
                }
            }
        }
    }

    /**
     * The document picker coming back.
     *
     * Anything that is not ours goes to `super`, which is what hands results to
     * the Flutter plugins - swallowing them here would break every plugin that
     * starts an activity of its own.
     */
    @Deprecated("Matches the FlutterActivity method being overridden")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (documents.onActivityResult(requestCode, resultCode, data)) return
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
    }

    /**
     * A share that arrives while HozaSend is already open.
     *
     * `singleTop` in the manifest is what routes it here rather than starting
     * a second copy of the app - which would be a second copy fighting for the
     * same two ports.
     */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        takeShared { paths ->
            if (paths.isNotEmpty()) shareChannel?.invokeMethod("shared", paths)
        }
    }

    // --- Session lifetime ----------------------------------------------------

    /**
     * Puts up - or refreshes - the notification that keeps this process alive
     * while a session is running.
     *
     * Returns false if Android refused. From Android 12 a foreground service
     * cannot be started from the background, and a session that begins while
     * the app is not on screen (auto-accept, say) will land there. That is not
     * an error worth showing anyone: the transfer proceeds exactly as it did
     * before this existed, and only loses its protection from being frozen.
     */
    private fun showSession(title: String, text: String, progress: Int): Boolean {
        val intent = Intent(this, TransferService::class.java)
            .putExtra(TransferService.EXTRA_TITLE, title)
            .putExtra(TransferService.EXTRA_TEXT, text)
            .putExtra(TransferService.EXTRA_PROGRESS, progress)
        return try {
            ContextCompat.startForegroundService(this, intent)
            true
        } catch (error: Exception) {
            false
        }
    }

    private fun hideSession() {
        try {
            startService(
                Intent(this, TransferService::class.java)
                    .setAction(TransferService.ACTION_STOP),
            )
        } catch (error: Exception) {
            // Already gone, or the process is being torn down anyway.
        }
    }

    // --- Sharing in ----------------------------------------------------------

    /**
     * Hands whatever another app shared to [deliver], as paths this app can
     * read, on the main thread.
     *
     * The intent is cleared once taken. Android keeps handing the same intent
     * back for the life of the activity, so without this a rotation - or the
     * user simply coming back to the app later - would queue the same files
     * again.
     */
    private fun takeShared(deliver: (List<String>) -> Unit) {
        val uris = sharedUris(intent)
        if (uris.isEmpty()) {
            deliver(emptyList())
            return
        }
        setIntent(Intent(Intent.ACTION_MAIN))
        // Off the main thread: a share can be a 2 GB video, and copying it
        // where the frames are drawn is how an app gets killed for not
        // responding.
        shareWorker.execute {
            val paths = materialize(uris)
            runOnUiThread { deliver(paths) }
        }
    }

    /** What was actually shared, whichever way the other app sent it. */
    @Suppress("DEPRECATION")
    private fun sharedUris(source: Intent?): List<Uri> {
        if (source == null) return emptyList()
        return when (source.action) {
            Intent.ACTION_SEND ->
                listOfNotNull(source.getParcelableExtra<Uri>(Intent.EXTRA_STREAM))
            Intent.ACTION_SEND_MULTIPLE ->
                source.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
                    ?: emptyList()
            // "Open with HozaSend" on a file, which is the same request said a
            // different way.
            Intent.ACTION_VIEW -> listOfNotNull(source.data)
            else -> emptyList()
        }
    }

    /**
     * Copies each shared item into this app's cache and returns the paths.
     *
     * A share arrives as a content URI, not a file: there is no path to open,
     * and the permission that came with it dies with the activity. Copying is
     * what turns it into something the transfer engine can stream at any point
     * afterwards - the same trade the file picker already makes on Android.
     *
     * A `file://` share needs none of that and is passed straight through.
     */
    private fun materialize(uris: List<Uri>): List<String> {
        val directory = File(cacheDir, SHARED_DIR)
        if (!directory.exists() && !directory.mkdirs()) return emptyList()
        purge(directory)

        val paths = ArrayList<String>(uris.size)
        for (uri in uris) {
            try {
                if (uri.scheme == "file") {
                    val path = uri.path
                    if (path != null && File(path).canRead()) {
                        paths.add(path)
                        continue
                    }
                }
                val target = unique(File(directory, displayName(uri)))
                val copied = contentResolver.openInputStream(uri)?.use { input ->
                    target.outputStream().use { output ->
                        input.copyTo(output, BUFFER)
                    }
                    true
                } ?: false
                if (copied) paths.add(target.absolutePath)
            } catch (error: Exception) {
                // One item the sender could not actually give us must not lose
                // the rest of the share.
            }
        }
        return paths
    }

    /** The name the other app shows for this item, or something usable. */
    private fun displayName(uri: Uri): String {
        if (uri.scheme == ContentResolver.SCHEME_CONTENT) {
            try {
                contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                    val column = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (column >= 0 && cursor.moveToFirst()) {
                        val name = cursor.getString(column)
                        if (!name.isNullOrBlank()) return sanitize(name)
                    }
                }
            } catch (error: Exception) {
                // Providers are allowed to refuse this; the fallback is fine.
            }
        }
        return sanitize(uri.lastPathSegment ?: "shared")
    }

    /** A URI segment is not a file name; anything path-like is stripped. */
    private fun sanitize(name: String): String {
        val cleaned = name.substringAfterLast('/').substringAfterLast('\\')
            .replace(Regex("""[\\/:*?"<>|]"""), "_")
            .trim()
        return if (cleaned.isEmpty()) "shared" else cleaned.take(120)
    }

    /** Never overwrites: two shares of report.pdf are two files. */
    private fun unique(candidate: File): File {
        if (!candidate.exists()) return candidate
        val stem = candidate.name.substringBeforeLast('.', candidate.name)
        val extension = candidate.name.substringAfterLast('.', "")
        var counter = 1
        while (true) {
            val name =
                if (extension.isEmpty()) "$stem ($counter)"
                else "$stem ($counter).$extension"
            val next = File(candidate.parentFile, name)
            if (!next.exists()) return next
            counter++
        }
    }

    /**
     * Drops copies from earlier shares.
     *
     * These are working copies of files the user already has, and the only
     * thing that would ever notice them missing is a transfer still running -
     * hence a day, rather than clearing the folder on every share.
     */
    private fun purge(directory: File) {
        val cutoff = System.currentTimeMillis() - SHARE_CACHE_MS
        directory.listFiles()?.forEach { file ->
            if (file.isFile && file.lastModified() < cutoff) file.delete()
        }
    }

    // --- System settings -----------------------------------------------------

    /**
     * Takes the user to the Wi-Fi screen.
     *
     * The app cannot switch Wi-Fi on itself - that stopped being something a
     * normal app may do in Android 10, and rightly so. Opening the screen is
     * the whole of what is on offer.
     */
    private fun wifiScreens(): List<Intent> = listOf(
        Intent(Settings.ACTION_WIFI_SETTINGS),
        // Every device has this one, so the list can never come up empty.
        Intent(Settings.ACTION_WIRELESS_SETTINGS),
        Intent(Settings.ACTION_SETTINGS),
    )

    /**
     * Takes the user to the hotspot screen, or as close to it as this device
     * allows.
     *
     * There is no public action for tethering - the constant exists but is
     * hidden - so the exact screen has to be asked for by name, and OEMs move
     * it. The named screens are tried first because they land exactly where
     * the user wants to be; the public wireless-settings screen is the floor,
     * and hotspot is one tap from it on every Android there has ever been.
     */
    private fun hotspotScreens(): List<Intent> = listOf(
        Intent().setComponent(
            ComponentName(SETTINGS_PACKAGE, "com.android.settings.TetherSettings"),
        ),
        Intent().setComponent(
            ComponentName(
                SETTINGS_PACKAGE,
                "com.android.settings.Settings\$TetherSettingsActivity",
            ),
        ),
        Intent(TETHER_ACTION),
        Intent(Settings.ACTION_WIRELESS_SETTINGS),
        Intent(Settings.ACTION_SETTINGS),
    )

    /** Opens the first screen this device is willing to show. */
    private fun openFirst(candidates: List<Intent>): Boolean {
        for (intent in candidates) {
            try {
                startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                return true
            } catch (error: ActivityNotFoundException) {
                // This build of Android does not have that screen under that
                // name. Try the next one.
            } catch (error: SecurityException) {
                // Some OEMs ship the tether screen but do not export it.
            }
        }
        return false
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

    /**
     * Keeps Wi-Fi out of its power-saving duty cycle while a session is live.
     *
     * A different lock from the multicast one and not a substitute for it: the
     * multicast lock decides which packets are delivered, this one decides how
     * awake the radio is. A large transfer with the screen off is throttled
     * hard without it, to the point of missing enough heartbeats to be called
     * a dropped connection.
     */
    private fun acquireLinkLock() {
        if (linkLock?.isHeld == true) return
        val wifi = applicationContext
            .getSystemService(Context.WIFI_SERVICE) as? WifiManager ?: return
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            WifiManager.WIFI_MODE_FULL_LOW_LATENCY
        } else {
            @Suppress("DEPRECATION")
            WifiManager.WIFI_MODE_FULL_HIGH_PERF
        }
        linkLock = wifi.createWifiLock(mode, LINK_TAG).apply {
            setReferenceCounted(false)
            acquire()
        }
    }

    private fun releaseLinkLock() {
        linkLock?.let { if (it.isHeld) it.release() }
        linkLock = null
    }

    override fun onDestroy() {
        shareWorker.shutdown()
        // Closes any file the picker still had open. A stream left behind
        // holds a descriptor on a file the user may be trying to delete.
        documents.dispose()
        // The radio must not be left awake if the activity goes away while
        // discovery or a transfer is still running.
        releaseLock()
        releaseLinkLock()
        // The activity going away takes the Dart isolate with it, so there is
        // no session left for the notification to be about. Leaving it up
        // would be a progress bar for a transfer that has already stopped.
        hideSession()
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
        subPath: String,
        modifiedMs: Long?,
    ): Map<String, String?>? {
        val source = File(sourcePath)
        if (!source.exists()) return null

        // Already sanitised on the Dart side, and sanitised again here: this
        // path began life on another device, and it is about to be turned into
        // a directory. Anything that could climb out of Downloads/HozaSend is
        // dropped rather than trusted twice.
        val folder = subPath.split('/', '\\')
            .filter { it.isNotEmpty() && it != "." && it != ".." }
            .joinToString("/")

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            publishViaMediaStore(source, displayName, mimeType, folder, modifiedMs)
        } else {
            publishViaFile(source, displayName, folder, modifiedMs)
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

    /**
     * Removes a received file from Downloads/HozaSend.
     *
     * [target] is the MediaStore URI the file was published as under scoped
     * storage, or a plain path on older phones. Either way it is a file this
     * app wrote, which is the one kind an app may delete without asking:
     * MediaStore lets the owner of a row remove it. A file that is already
     * gone counts as deleted - the point is the end state, not the act.
     */
    private fun deleteReceivedFile(target: String): Boolean {
        if (!target.startsWith("content://")) {
            val file = File(target)
            if (!file.exists()) return true
            return try {
                file.delete()
            } catch (error: SecurityException) {
                false
            }
        }

        val uri = Uri.parse(target)
        val resolver = applicationContext.contentResolver
        return try {
            if (resolver.delete(uri, null, null) > 0) return true
            // Zero rows: the entry is already gone. Confirm rather than assume,
            // since zero is also what a row the app no longer owns returns.
            resolver.query(uri, arrayOf(MediaStore.MediaColumns._ID), null, null, null)
                ?.use { cursor -> cursor.count == 0 } ?: true
        } catch (error: SecurityException) {
            // Published by an earlier install of the app, so the ownership
            // that would have allowed this was lost with it.
            false
        } catch (error: Exception) {
            false
        }
    }

    private fun publishViaMediaStore(
        source: File,
        displayName: String,
        mimeType: String?,
        subPath: String,
        modifiedMs: Long?,
    ): Map<String, String?>? {
        val resolver = applicationContext.contentResolver
        val relative = if (subPath.isEmpty()) {
            "${Environment.DIRECTORY_DOWNLOADS}/$FOLDER"
        } else {
            "${Environment.DIRECTORY_DOWNLOADS}/$FOLDER/$subPath"
        }
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, displayName)
            put(MediaStore.Downloads.RELATIVE_PATH, relative)
            if (mimeType != null) put(MediaStore.Downloads.MIME_TYPE, mimeType)
            // Seconds here, unlike everywhere else in the app. A file keeps the
            // age it had on the device that sent it, so a folder of photos
            // still sorts by when they were taken.
            if (modifiedMs != null) {
                put(MediaStore.Downloads.DATE_MODIFIED, modifiedMs / 1000L)
            }
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
                "location" to "$relative/$displayName",
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
        subPath: String,
        modifiedMs: Long?,
    ): Map<String, String?>? {
        val root = File(
            Environment.getExternalStoragePublicDirectory(
                Environment.DIRECTORY_DOWNLOADS,
            ),
            FOLDER,
        )
        val directory = if (subPath.isEmpty()) root else File(root, subPath)
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
            if (modifiedMs != null) target.setLastModified(modifiedMs)
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
        private const val SETTINGS_CHANNEL = "hozasend/system_settings"
        private const val SESSION_CHANNEL = "hozasend/session"
        private const val SHARE_CHANNEL = "hozasend/share"
        private const val FILES_CHANNEL = "hozasend/files"
        private const val SETTINGS_PACKAGE = "com.android.settings"

        /** Working copies of shared files, inside the app own cache. */
        private const val SHARED_DIR = "shared"

        /** How long a working copy is kept before it is cleared. */
        private const val SHARE_CACHE_MS = 24L * 60 * 60 * 1000

        /** Hidden in the SDK, so it has to be written out. */
        private const val TETHER_ACTION = "android.settings.TETHER_SETTINGS"
        private const val LOCK_TAG = "hozasend.discovery"
        private const val LINK_TAG = "hozasend.transfer"
        private const val FOLDER = "HozaSend"
        private const val BUFFER = 64 * 1024
    }
}
