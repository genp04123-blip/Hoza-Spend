package com.rahozosman.hozasend

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.res.AssetFileDescriptor
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.util.Size
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicLong

/**
 * Choosing files on Android, and reading them where they already are.
 *
 * Every Flutter file picker answers a selection by copying the chosen file into
 * the app's cache and handing back the copy. For most apps that is a reasonable
 * shortcut - it buys a real path, which almost everything expects. For an app
 * whose whole job is moving large files it is the wrong trade twice: choosing a
 * 4 GB video needs 4 GB of free space before a single byte is sent, takes as
 * long as the copy takes, and leaves the copy behind afterwards.
 *
 * The Storage Access Framework will stream the original perfectly well. What it
 * will not hand over is a path, so this exists to do the two things that need
 * one: ask for documents, and read them back in chunks as the transfer asks for
 * them. Nothing is filtered - the picker is opened for any type the device is
 * willing to offer.
 *
 * Every failure here is answered with null rather than an exception. The Dart
 * side reads that as "use the other picker", which still works: it is only
 * slower and hungrier. A device that refuses any of this loses performance,
 * never the ability to send a file.
 */
class DocumentFiles(private val activity: Activity) {

    /**
     * One thread for all of it. Reads have to be serialised per stream anyway,
     * and the app streams one file at a time, so a pool would buy nothing but
     * a way to interleave two reads on the same descriptor.
     */
    private val worker: ExecutorService = Executors.newSingleThreadExecutor()

    /** Open read streams, by the handle Dart holds. */
    private val streams = ConcurrentHashMap<String, InputStream>()

    private val nextHandle = AtomicLong()

    /** The picker that is on screen, waiting for the user to choose. */
    private var pending: MethodChannel.Result? = null

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickFiles" -> startPick(result, folder = false)
            "pickFolder" -> startPick(result, folder = true)
            "openStream" -> openStream(call.argument<String>("uri"), result)
            "readStream" -> readStream(
                call.argument<String>("handle"),
                call.argument<Int>("max") ?: DEFAULT_READ,
                result,
            )
            "closeStream" -> {
                closeStream(call.argument<String>("handle"))
                result.success(true)
            }
            "thumbnail" -> thumbnail(
                call.argument<String>("uri"),
                call.argument<Int>("size") ?: THUMBNAIL_SIZE,
                result,
            )
            else -> result.notImplemented()
        }
    }

    /** Closes anything still open. The process may be going away. */
    fun dispose() {
        for (stream in streams.values) {
            try {
                stream.close()
            } catch (error: Exception) {
                // Being torn down anyway.
            }
        }
        streams.clear()
        worker.shutdown()
    }

    // --- Picking -------------------------------------------------------------

    private fun startPick(result: MethodChannel.Result, folder: Boolean) {
        if (pending != null) {
            // A picker is already up. Answering null rather than replacing the
            // waiting result keeps the first one able to complete.
            result.success(null)
            return
        }

        val intent = if (folder) {
            Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
        } else {
            Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                // Any type, and nothing narrower. Filtering here is what turns
                // a file-sharing app into a photo-sharing app.
                type = ANY_TYPE
                putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
            }
        }.apply {
            // Persistable, so a file queued now is still readable after the
            // app is backgrounded, killed and reopened mid-transfer.
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
            )
        }

        pending = result
        try {
            activity.startActivityForResult(
                intent,
                if (folder) REQUEST_FOLDER else REQUEST_FILES,
            )
        } catch (error: ActivityNotFoundException) {
            // A device with no document provider at all. Rare, but the other
            // picker may still manage it.
            pending = null
            result.success(null)
        }
    }

    /** True when this was our result and nothing else should look at it. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_FILES && requestCode != REQUEST_FOLDER) {
            return false
        }
        val result = pending ?: return true
        pending = null

        if (resultCode != Activity.RESULT_OK || data == null) {
            // Cancelled. An empty list, not null: null means "fall back", and
            // falling back would reopen a picker the user just dismissed.
            result.success(emptyList<Any>())
            return true
        }

        val folder = requestCode == REQUEST_FOLDER
        // Off the main thread: describing two hundred files means two hundred
        // provider queries, and a folder walk is deeper than that.
        worker.execute {
            val described = try {
                if (folder) describeTree(data.data) else describeFiles(data)
            } catch (error: Exception) {
                null
            }
            activity.runOnUiThread { result.success(described) }
        }
        return true
    }

    private fun describeFiles(data: Intent): List<Map<String, Any?>> {
        val uris = ArrayList<Uri>()
        val clip = data.clipData
        if (clip != null) {
            for (i in 0 until clip.itemCount) uris.add(clip.getItemAt(i).uri)
        } else {
            data.data?.let(uris::add)
        }
        return uris.map { uri ->
            persist(uri)
            describe(uri, null)
        }
    }

    private fun describeTree(tree: Uri?): List<Map<String, Any?>> {
        if (tree == null) return emptyList()
        persist(tree)

        val rootId = DocumentsContract.getTreeDocumentId(tree)
        val rootUri = DocumentsContract.buildDocumentUriUsingTree(tree, rootId)
        // The folder's own name leads every relative path, so the other device
        // rebuilds the folder rather than emptying it into Downloads.
        val rootName = nameOf(rootUri) ?: "Folder"

        val files = ArrayList<Map<String, Any?>>()
        walk(tree, rootId, rootName, files, 0)
        return files
    }

    private fun walk(
        tree: Uri,
        parentId: String,
        prefix: String,
        into: MutableList<Map<String, Any?>>,
        depth: Int,
    ) {
        if (depth > MAX_DEPTH || into.size >= MAX_FILES) return

        val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, parentId)
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
        )

        try {
            activity.contentResolver
                .query(children, projection, null, null, null)
                ?.use { cursor ->
                    while (cursor.moveToNext()) {
                        if (into.size >= MAX_FILES) return
                        val id = cursor.getString(0) ?: continue
                        val name = cursor.getString(1) ?: continue
                        // Hidden entries are skipped, the same as on desktop.
                        if (name.startsWith(".")) continue

                        if (cursor.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR) {
                            walk(tree, id, "$prefix/$name", into, depth + 1)
                            continue
                        }

                        into.add(
                            mapOf(
                                "uri" to DocumentsContract
                                    .buildDocumentUriUsingTree(tree, id)
                                    .toString(),
                                "name" to name,
                                "size" to if (cursor.isNull(3)) -1L else cursor.getLong(3),
                                "modified" to
                                    if (cursor.isNull(4)) 0L else cursor.getLong(4),
                                "rel" to "$prefix/$name",
                            ),
                        )
                    }
                }
        } catch (error: Exception) {
            // A provider that will not be listed. Whatever was found already
            // still counts; losing the rest of a folder beats losing all of it.
        }
    }

    /**
     * What Dart needs to offer a file: a stable handle, a name, a byte count
     * and an age.
     *
     * A size of -1 is deliberate rather than a dropped entry. The receiver is
     * promised a byte count before the first byte arrives, so a file whose size
     * the provider will not report cannot be sent this way - and Dart answers
     * that by falling back to the picker that copies, which always knows.
     */
    private fun describe(uri: Uri, relativePath: String?): Map<String, Any?> {
        val resolver = activity.contentResolver
        var name: String? = null
        var size = -1L
        var modified = 0L

        try {
            resolver.query(uri, null, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val nameColumn = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (nameColumn >= 0 && !cursor.isNull(nameColumn)) {
                        name = cursor.getString(nameColumn)
                    }
                    val sizeColumn = cursor.getColumnIndex(OpenableColumns.SIZE)
                    if (sizeColumn >= 0 && !cursor.isNull(sizeColumn)) {
                        size = cursor.getLong(sizeColumn)
                    }
                    val timeColumn = cursor.getColumnIndex(
                        DocumentsContract.Document.COLUMN_LAST_MODIFIED,
                    )
                    if (timeColumn >= 0 && !cursor.isNull(timeColumn)) {
                        modified = cursor.getLong(timeColumn)
                    }
                }
            }
        } catch (error: Exception) {
            // Providers are allowed to refuse a query; the descriptor below is
            // the second way to ask.
        }

        if (size < 0) {
            size = try {
                resolver.openAssetFileDescriptor(uri, "r")?.use { it.length } ?: -1L
            } catch (error: Exception) {
                -1L
            }
            if (size == AssetFileDescriptor.UNKNOWN_LENGTH) size = -1L
        }

        return mapOf(
            "uri" to uri.toString(),
            "name" to (name ?: uri.lastPathSegment?.substringAfterLast('/') ?: ""),
            "size" to size,
            "modified" to modified,
            "rel" to relativePath,
        )
    }

    private fun nameOf(uri: Uri): String? {
        return try {
            activity.contentResolver
                .query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { cursor ->
                    if (cursor.moveToFirst() && !cursor.isNull(0)) {
                        cursor.getString(0)
                    } else {
                        null
                    }
                }
        } catch (error: Exception) {
            null
        }
    }

    /**
     * Keeps the grant past this activity.
     *
     * Without it the URI is readable only while the activity that received it
     * lives, and a transfer that outlasts a rotation - or the app being
     * backgrounded and reclaimed - would fail halfway through with a security
     * error. Not every provider offers a persistable grant, and one that does
     * not is not an error: the transient grant still covers the common case.
     */
    private fun persist(uri: Uri) {
        trimGrants()
        try {
            activity.contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION,
            )
        } catch (error: SecurityException) {
            // Nothing to take. The transient grant stands.
        } catch (error: Exception) {
            // Some providers throw other things here; none of them are fatal.
        }
    }

    /**
     * Gives back the oldest grants once there are too many.
     *
     * Android caps how many URI permissions one app may hold, and a grant taken
     * here lasts until it is given back - so without this, an app whose whole
     * purpose is picking files would spend its allowance over a few weeks of
     * ordinary use and then quietly stop being able to take new ones. The
     * oldest go first: a file picked months ago has already been sent.
     */
    private fun trimGrants() {
        try {
            val resolver = activity.contentResolver
            val held = resolver.persistedUriPermissions
            if (held.size < MAX_GRANTS) return
            held.sortedBy { it.persistedTime }
                .take(held.size - MAX_GRANTS + GRANT_HEADROOM)
                .forEach { permission ->
                    try {
                        resolver.releasePersistableUriPermission(
                            permission.uri,
                            Intent.FLAG_GRANT_READ_URI_PERMISSION,
                        )
                    } catch (error: Exception) {
                        // Already gone, or never ours to release.
                    }
                }
        } catch (error: Exception) {
            // Not being able to tidy up is not a reason to fail a pick.
        }
    }

    // --- Reading -------------------------------------------------------------

    private fun openStream(uri: String?, result: MethodChannel.Result) {
        if (uri == null) {
            result.success(null)
            return
        }
        worker.execute {
            val handle = try {
                val stream = activity.contentResolver.openInputStream(Uri.parse(uri))
                if (stream == null) {
                    null
                } else {
                    val id = nextHandle.incrementAndGet().toString()
                    streams[id] = stream
                    id
                }
            } catch (error: Exception) {
                null
            }
            activity.runOnUiThread { result.success(handle) }
        }
    }

    /**
     * The next chunk, or null at the end of the file.
     *
     * The buffer is filled as far as it will go rather than returned at the
     * first short read. A content stream routinely hands back far less than
     * asked for, and one channel round trip per few kilobytes would cost more
     * than the transfer itself.
     */
    private fun readStream(handle: String?, max: Int, result: MethodChannel.Result) {
        val stream = if (handle == null) null else streams[handle]
        if (stream == null) {
            result.error("closed", "That file is no longer open.", null)
            return
        }
        val size = max.coerceIn(1, MAX_READ)

        worker.execute {
            try {
                val buffer = ByteArray(size)
                var filled = 0
                while (filled < size) {
                    val read = stream.read(buffer, filled, size - filled)
                    if (read < 0) break
                    filled += read
                }
                val chunk = when (filled) {
                    0 -> null
                    size -> buffer
                    else -> buffer.copyOf(filled)
                }
                activity.runOnUiThread { result.success(chunk) }
            } catch (error: Exception) {
                activity.runOnUiThread {
                    result.error("read", error.message ?: "Could not read the file.", null)
                }
            }
        }
    }

    /**
     * A small preview of [uri], as JPEG bytes, or null if there is none.
     *
     * Asked of the provider rather than made here, which is the whole point.
     * The alternative - reading the file and decoding it - means pulling a
     * 6 MB photo across the platform channel for a 46-pixel square, and doing
     * it once per card on a screen that can hold a hundred of them. This costs
     * about ten kilobytes each, and it works for video as well as stills,
     * which reading the file never could without a decoder.
     *
     * API 29 and up. Below that there is no such call, and a kind icon is the
     * honest answer.
     */
    private fun thumbnail(uri: String?, size: Int, result: MethodChannel.Result) {
        if (uri == null || Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.success(null)
            return
        }
        val side = size.coerceIn(32, 512)

        // On the same single thread as the reads, so a screen full of cards
        // asks for its previews one at a time instead of a hundred at once.
        worker.execute {
            val bytes = try {
                val bitmap = activity.contentResolver.loadThumbnail(
                    Uri.parse(uri),
                    Size(side, side),
                    null,
                )
                ByteArrayOutputStream().use { out ->
                    bitmap.compress(Bitmap.CompressFormat.JPEG, THUMBNAIL_QUALITY, out)
                    bitmap.recycle()
                    out.toByteArray()
                }
            } catch (error: Exception) {
                // No thumbnail for this one - an odd format, or a provider that
                // does not make them. The card falls back to its kind icon.
                null
            } catch (error: OutOfMemoryError) {
                null
            }
            activity.runOnUiThread { result.success(bytes) }
        }
    }

    private fun closeStream(handle: String?) {
        val stream = if (handle == null) null else streams.remove(handle)
        if (stream == null) return
        worker.execute {
            try {
                stream.close()
            } catch (error: Exception) {
                // Already gone.
            }
        }
    }

    companion object {
        /** Distinct enough not to collide with a plugin's own request codes. */
        private const val REQUEST_FILES = 0x487A
        private const val REQUEST_FOLDER = 0x487B

        private const val ANY_TYPE = "*/*"

        private const val DEFAULT_READ = 512 * 1024

        /** A ceiling on what one call may allocate. */
        private const val MAX_READ = 8 * 1024 * 1024

        /** How deep a folder selection will walk. */
        private const val MAX_DEPTH = 16

        /**
         * How many files one folder selection may queue.
         *
         * A limit rather than a judgement: past this the offer message, the
         * file list on screen and the walk itself all stop being reasonable,
         * and picking a whole storage root by accident should not hang the app.
         */
        private const val MAX_FILES = 5000

        /**
         * How many persisted URI grants to hold before giving the oldest back.
         *
         * Comfortably under the platform ceiling, which has been 128 on most
         * releases and is not promised anywhere.
         */
        private const val MAX_GRANTS = 96

        /** Released in batches, so this is not done on every single pick. */
        private const val GRANT_HEADROOM = 32

        /** Comfortably above the card size on any density. */
        private const val THUMBNAIL_SIZE = 256

        private const val THUMBNAIL_QUALITY = 80
    }
}
