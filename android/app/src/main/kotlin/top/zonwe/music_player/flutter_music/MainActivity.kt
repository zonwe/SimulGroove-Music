package top.zonwe.music_player.flutter_music

import android.app.Activity
import android.content.ContentUris
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.util.Size
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.ArrayDeque
import java.util.concurrent.Executors
import kotlin.math.min

class MainActivity : AudioServiceActivity() {
    private val channelName = "top.zonwe.music_player/media_store"
    private val pickDirectoryRequest = 4812
    private val scanExecutor = Executors.newSingleThreadExecutor()
    private var pendingDirectoryResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickAudioDirectory" -> pickAudioDirectory(result)
                    "scanAudioTree" -> {
                        val uri = call.argument<String>("uri")
                        if (uri == null) {
                            result.error("INVALID_DIRECTORY", "没有收到音乐目录", null)
                        } else {
                            runScan(result) { scanAudioTree(Uri.parse(uri)) }
                        }
                    }
                    "scanAudio" -> runScan(result) { scanMediaStore() }
                    else -> result.notImplemented()
                }
            }
    }

    private fun runScan(
        result: MethodChannel.Result,
        scan: () -> List<Map<String, Any?>>,
    ) {
        scanExecutor.execute {
            try {
                val songs = scan()
                runOnUiThread { result.success(songs) }
            } catch (error: Exception) {
                runOnUiThread {
                    result.error("MEDIA_SCAN_FAILED", error.message, null)
                }
            }
        }
    }

    private fun pickAudioDirectory(result: MethodChannel.Result) {
        if (pendingDirectoryResult != null) {
            result.error("PICKER_BUSY", "目录选择器已经打开", null)
            return
        }
        pendingDirectoryResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PREFIX_URI_PERMISSION,
            )
        }
        startActivityForResult(intent, pickDirectoryRequest)
    }

    @Deprecated("Uses the compatible document-tree result API for FlutterActivity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != pickDirectoryRequest) return

        val pending = pendingDirectoryResult ?: return
        pendingDirectoryResult = null
        val treeUri = data?.data
        if (resultCode != Activity.RESULT_OK || treeUri == null) {
            pending.success(null)
            return
        }

        val flags = data.flags and
            (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        try {
            contentResolver.takePersistableUriPermission(
                treeUri,
                flags and Intent.FLAG_GRANT_READ_URI_PERMISSION,
            )
        } catch (_: SecurityException) {
            // Some providers grant the directory for this session but do not persist it.
        }
        pending.success(
            mapOf(
                "uri" to treeUri.toString(),
                "label" to treeDisplayPath(treeUri),
            ),
        )
    }

    private data class TreeEntry(
        val documentId: String,
        val uri: Uri,
        val name: String,
        val mimeType: String,
        val size: Long?,
        val modifiedAt: Long?,
    )

    private fun scanAudioTree(treeUri: Uri): List<Map<String, Any?>> {
        val entries = collectTreeEntries(treeUri)
        val lyrics = entries
            .filter { it.name.substringAfterLast('.', "").equals("lrc", ignoreCase = true) }
            .associateBy { sidecarKey(it) }

        return entries
            .asSequence()
            .filter(::isAudioEntry)
            .map { entry ->
                val retriever = MediaMetadataRetriever()
                try {
                    retriever.setDataSource(applicationContext, entry.uri)
                    val duration = retriever
                        .extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                        ?.toLongOrNull()
                    mapOf(
                        "id" to entry.documentId,
                        "uri" to entry.uri.toString(),
                        "displayName" to entry.name,
                        "title" to retriever.extractMetadata(
                            MediaMetadataRetriever.METADATA_KEY_TITLE,
                        ),
                        "artist" to retriever.extractMetadata(
                            MediaMetadataRetriever.METADATA_KEY_ARTIST,
                        ),
                        "album" to retriever.extractMetadata(
                            MediaMetadataRetriever.METADATA_KEY_ALBUM,
                        ),
                        "duration" to duration,
                        "size" to entry.size,
                        "dateModifiedMs" to entry.modifiedAt,
                        "artwork" to compactArtwork(retriever.embeddedPicture),
                        "lyrics" to lyrics[sidecarKey(entry)]?.let(::readText),
                    )
                } finally {
                    retriever.release()
                }
            }
            .sortedBy { (it["title"] as? String) ?: (it["displayName"] as? String) }
            .toList()
    }

    private fun collectTreeEntries(treeUri: Uri): List<TreeEntry> {
        val rootId = DocumentsContract.getTreeDocumentId(treeUri)
        val rootDocument = DocumentsContract.buildDocumentUriUsingTree(treeUri, rootId)
        val directories = ArrayDeque<Uri>().apply { add(rootDocument) }
        val entries = mutableListOf<TreeEntry>()
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
        )

        while (directories.isNotEmpty()) {
            val directory = directories.removeFirst()
            val children = DocumentsContract.buildChildDocumentsUriUsingTree(
                treeUri,
                DocumentsContract.getDocumentId(directory),
            )
            contentResolver.query(children, projection, null, null, null)?.use { cursor ->
                val idIndex = cursor.getColumnIndexOrThrow(projection[0])
                val nameIndex = cursor.getColumnIndexOrThrow(projection[1])
                val mimeIndex = cursor.getColumnIndexOrThrow(projection[2])
                val sizeIndex = cursor.getColumnIndexOrThrow(projection[3])
                val modifiedIndex = cursor.getColumnIndexOrThrow(projection[4])
                while (cursor.moveToNext()) {
                    val documentId = cursor.getString(idIndex)
                    val documentUri = DocumentsContract.buildDocumentUriUsingTree(
                        treeUri,
                        documentId,
                    )
                    val mimeType = cursor.getString(mimeIndex).orEmpty()
                    if (mimeType == DocumentsContract.Document.MIME_TYPE_DIR) {
                        directories.add(documentUri)
                    } else {
                        entries.add(
                            TreeEntry(
                                documentId = documentId,
                                uri = documentUri,
                                name = cursor.getString(nameIndex).orEmpty(),
                                mimeType = mimeType,
                                size = cursor.longOrNull(sizeIndex),
                                modifiedAt = cursor.longOrNull(modifiedIndex),
                            ),
                        )
                    }
                }
            }
        }
        return entries
    }

    private fun android.database.Cursor.longOrNull(index: Int): Long? =
        if (isNull(index)) null else getLong(index)

    private fun isAudioEntry(entry: TreeEntry): Boolean {
        val extension = entry.name.substringAfterLast('.', "").lowercase()
        return entry.mimeType.startsWith("audio/") ||
            extension in setOf("mp3", "flac", "m4a", "aac", "wav", "ogg", "opus", "wma")
    }

    private fun sidecarKey(entry: TreeEntry): String {
        val parent = entry.documentId.substringBeforeLast('/', "")
        val stem = entry.name.substringBeforeLast('.').lowercase()
        return "$parent/$stem"
    }

    private fun readText(entry: TreeEntry): String? = try {
        contentResolver.openInputStream(entry.uri)?.bufferedReader()?.use {
            it.readText().take(512 * 1024).trim().ifEmpty { null }
        }
    } catch (_: Exception) {
        null
    }

    private fun treeDisplayPath(treeUri: Uri): String {
        val documentId = DocumentsContract.getTreeDocumentId(treeUri)
        val volume = documentId.substringBefore(':', documentId)
        val path = documentId.substringAfter(':', "").trim('/')
        val root = if (volume.equals("primary", ignoreCase = true)) "内部存储" else volume
        return if (path.isEmpty()) root else "$root/$path"
    }

    private fun scanMediaStore(): List<Map<String, Any?>> {
        val resolver = applicationContext.contentResolver
        val collection = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        val projection = arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.DISPLAY_NAME,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.ALBUM_ID,
            MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.SIZE,
            MediaStore.Audio.Media.DATE_MODIFIED,
            MediaStore.Audio.Media.DATA,
        )
        val selection =
            "${MediaStore.Audio.Media.IS_MUSIC} != 0 AND ${MediaStore.Audio.Media.DURATION} > 0"
        val albumArtwork = mutableMapOf<Long, ByteArray?>()
        val songs = mutableListOf<Map<String, Any?>>()

        resolver.query(
            collection,
            projection,
            selection,
            null,
            "${MediaStore.Audio.Media.TITLE} COLLATE NOCASE ASC",
        )?.use { cursor ->
            val idColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
            val displayNameColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DISPLAY_NAME)
            val titleColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
            val artistColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
            val albumColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
            val albumIdColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM_ID)
            val durationColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
            val sizeColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.SIZE)
            val modifiedColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATE_MODIFIED)
            val dataColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA)

            while (cursor.moveToNext()) {
                val id = cursor.getLong(idColumn)
                val albumId = cursor.getLong(albumIdColumn)
                val uri = ContentUris.withAppendedId(collection, id)
                val artwork = albumArtwork.getOrPut(albumId) {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        try {
                            val bitmap = resolver.loadThumbnail(uri, Size(256, 256), null)
                            ByteArrayOutputStream().use { output ->
                                bitmap.compress(Bitmap.CompressFormat.JPEG, 70, output)
                                output.toByteArray()
                            }
                        } catch (_: Exception) {
                            null
                        }
                    } else {
                        null
                    }
                }
                songs.add(
                    mapOf(
                        "id" to id,
                        "uri" to uri.toString(),
                        "displayName" to cursor.getString(displayNameColumn),
                        "title" to cursor.getString(titleColumn),
                        "artist" to cursor.getString(artistColumn),
                        "album" to cursor.getString(albumColumn),
                        "duration" to cursor.getLong(durationColumn),
                        "size" to cursor.getLong(sizeColumn),
                        "dateModified" to cursor.getLong(modifiedColumn),
                        "path" to cursor.getString(dataColumn),
                        "artwork" to artwork,
                    ),
                )
            }
        }
        return songs
    }

    private fun compactArtwork(bytes: ByteArray?): ByteArray? {
        if (bytes == null || bytes.isEmpty()) return null
        val source = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return null
        val largestSide = maxOf(source.width, source.height)
        val scale = min(1.0, 256.0 / largestSide)
        val outputBitmap = if (scale < 1.0) {
            Bitmap.createScaledBitmap(
                source,
                (source.width * scale).toInt().coerceAtLeast(1),
                (source.height * scale).toInt().coerceAtLeast(1),
                true,
            )
        } else {
            source
        }
        return ByteArrayOutputStream().use { output ->
            outputBitmap.compress(Bitmap.CompressFormat.JPEG, 70, output)
            if (outputBitmap !== source) outputBitmap.recycle()
            source.recycle()
            output.toByteArray()
        }
    }

    override fun onDestroy() {
        scanExecutor.shutdownNow()
        pendingDirectoryResult?.success(null)
        pendingDirectoryResult = null
        super.onDestroy()
    }
}
