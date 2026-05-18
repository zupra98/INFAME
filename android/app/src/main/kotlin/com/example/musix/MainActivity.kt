package com.example.musix

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.util.Log
import androidx.documentfile.provider.DocumentFile
import android.app.Activity
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.Locale
import kotlin.concurrent.thread

class MainActivity : AudioServiceActivity() {
    private val requestPickLocalMusicFolder = 41031
    private val localMusicChannelName = "musix/local_music"
    private var pendingPickResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, localMusicChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickLocalMusicFolder" -> {
                        if (pendingPickResult != null) {
                            result.error(
                                "busy",
                                "A local folder picker is already open.",
                                null,
                            )
                            return@setMethodCallHandler
                        }
                        pendingPickResult = result
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                            addFlags(
                                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
                            )
                        }
                        startActivityForResult(intent, requestPickLocalMusicFolder)
                    }

                    "scanLocalMusicFolder" -> {
                        val folderUri = call.argument<String>("folderUri").orEmpty()
                        thread(name = "LocalMusicScan") {
                            try {
                                val payload = scanLocalMusicFolder(folderUri)
                                runOnUiThread { result.success(payload) }
                            } catch (e: Exception) {
                                runOnUiThread {
                                    result.success(
                                        mapOf(
                                            "pickerType" to "saf",
                                            "androidSdk" to Build.VERSION.SDK_INT,
                                            "permissionStatus" to "error",
                                            "selectedPath" to "",
                                            "selectedUri" to folderUri,
                                            "selectedName" to "",
                                            "usingSaf" to true,
                                            "childCount" to 0,
                                            "entityCount" to 0,
                                            "supportedCount" to 0,
                                            "firstChild" to "",
                                            "firstSupported" to "",
                                            "files" to emptyList<Map<String, Any?>>(),
                                            "error" to (e.message ?: e.toString()),
                                        ),
                                    )
                                }
                            }
                        }
                    }

                    "copyLocalMusicFileToTemp" -> {
                        val uriString = call.argument<String>("uri").orEmpty()
                        val displayName = call.argument<String>("displayName").orEmpty()
                        thread(name = "LocalMusicTempCopy") {
                            try {
                                val payload = copyLocalMusicFileToTemp(uriString, displayName)
                                runOnUiThread { result.success(payload) }
                            } catch (e: Exception) {
                                runOnUiThread {
                                    result.success(
                                        mapOf(
                                            "ok" to false,
                                            "error" to (e.message ?: e.toString()),
                                            "tempPath" to "",
                                        ),
                                    )
                                }
                            }
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != requestPickLocalMusicFolder) return
        if (resultCode == Activity.RESULT_OK) {
            handlePickedLocalMusicFolder(data)
        } else {
            handlePickedLocalMusicFolder(null)
        }
    }

    private fun handlePickedLocalMusicFolder(data: Intent?) {
        val result = pendingPickResult ?: return
        pendingPickResult = null

        val uri = data?.data
        val selectedName = uri?.let {
            DocumentFile.fromTreeUri(this, it)?.name?.trim().orEmpty()
        }.orEmpty()
        if (uri == null) {
            result.success(
                mapOf(
                    "pickerType" to "saf",
                    "androidSdk" to Build.VERSION.SDK_INT,
                    "permissionStatus" to "cancelled",
                    "selectedPath" to "",
                    "selectedUri" to "",
                    "selectedName" to "",
                    "usingSaf" to true,
                    "childCount" to 0,
                    "entityCount" to 0,
                    "supportedCount" to 0,
                    "firstChild" to "",
                    "firstSupported" to "",
                    "files" to emptyList<Map<String, Any?>>(),
                ),
            )
            return
        }

        val dataFlags = data?.flags ?: 0
        val allowedPersistFlags =
            Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        val persistFlags = dataFlags and allowedPersistFlags

        Log.d("LocalImport", "pickerResult uri=$uri")
        Log.d("LocalImport", "pickerResult flags=$dataFlags")
        Log.d("LocalImport", "persistFlags=$persistFlags")

        var permissionPersisted = false
        if (persistFlags != 0) {
            try {
                contentResolver.takePersistableUriPermission(uri, persistFlags)
                permissionPersisted = true
                Log.d(
                    "LocalImport",
                    "permissionPersisted=true flags=$persistFlags",
                )
            } catch (e: SecurityException) {
                Log.w("LocalImport", "permissionPersistError=${e.message}")
                Log.w("LocalImport", "permissionPersisted=false security=${e.message}")
            } catch (e: IllegalArgumentException) {
                Log.w("LocalImport", "permissionPersistError=${e.message}")
                Log.w("LocalImport", "permissionPersisted=false illegal=${e.message}")
            }
        } else {
            Log.w(
                "LocalImport",
                "permissionPersisted=false noPersistableFlags dataFlags=$dataFlags",
            )
        }

        val hasReadPermission = contentResolver.persistedUriPermissions.any {
            it.uri == uri && it.isReadPermission
        }

        result.success(
            mapOf(
                "pickerType" to "saf",
                "androidSdk" to Build.VERSION.SDK_INT,
                "permissionStatus" to if (hasReadPermission || permissionPersisted) "granted" else "pending",
                "selectedPath" to "",
                "selectedUri" to uri.toString(),
                "selectedName" to selectedName,
                "usingSaf" to true,
                "childCount" to 0,
                "entityCount" to 0,
                "supportedCount" to 0,
                "firstChild" to "",
                "firstSupported" to "",
                "files" to emptyList<Map<String, Any?>>(),
            ),
        )
    }

    private fun scanLocalMusicFolder(folderUri: String): Map<String, Any?> {
        if (folderUri.isBlank()) {
            return mapOf(
                "pickerType" to "saf",
                "androidSdk" to Build.VERSION.SDK_INT,
                "permissionStatus" to "missing",
                "selectedPath" to "",
                "selectedUri" to "",
                "selectedName" to "",
                "usingSaf" to true,
                "childCount" to 0,
                "entityCount" to 0,
                "supportedCount" to 0,
                "firstChild" to "",
                "firstSupported" to "",
                "files" to emptyList<Map<String, Any?>>(),
            )
        }

        val uri = try {
            Uri.parse(folderUri)
        } catch (_: Exception) {
            return mapOf(
                "pickerType" to "saf",
                "androidSdk" to Build.VERSION.SDK_INT,
                "permissionStatus" to "invalid_uri",
                "selectedPath" to "",
                "selectedUri" to folderUri,
                "selectedName" to "",
                "usingSaf" to true,
                "childCount" to 0,
                "entityCount" to 0,
                "supportedCount" to 0,
                "firstChild" to "",
                "firstSupported" to "",
                "files" to emptyList<Map<String, Any?>>(),
            )
        }

        val root = DocumentFile.fromTreeUri(this, uri)
            ?: return mapOf(
                "pickerType" to "saf",
                "androidSdk" to Build.VERSION.SDK_INT,
                "permissionStatus" to "unreadable",
                "selectedPath" to "",
                "selectedUri" to folderUri,
                "selectedName" to "",
                "usingSaf" to true,
                "childCount" to 0,
                "entityCount" to 0,
                "supportedCount" to 0,
                "firstChild" to "",
                "firstSupported" to "",
                "files" to emptyList<Map<String, Any?>>(),
            )

        val files = mutableListOf<Map<String, Any?>>()
        var childCount = 0
        var entityCount = 0
        var supportedCount = 0
        var firstChild = ""
        var firstSupported = ""
        val selectedName = root.name?.trim().orEmpty()

        fun walk(directory: DocumentFile, relativePrefix: String) {
            val children = directory.listFiles()
            if (relativePrefix.isEmpty()) {
                childCount = children.size
            }

            children.forEach { child ->
                entityCount++
                val childName = child.name?.trim().orEmpty()
                if (firstChild.isEmpty()) {
                    firstChild = childName.ifEmpty { child.uri.toString() }
                }

                val relativePath = if (relativePrefix.isEmpty()) {
                    childName
                } else if (childName.isEmpty()) {
                    relativePrefix
                } else {
                    "$relativePrefix/$childName"
                }

                if (child.isDirectory) {
                    walk(child, relativePath)
                    return@forEach
                }

                if (!child.isFile) return@forEach
                if (!isSupportedAudioFile(childName)) return@forEach

                if (firstSupported.isEmpty()) {
                    firstSupported = childName.ifEmpty { child.uri.toString() }
                }

                supportedCount++
                files.add(
                    mapOf(
                        "uri" to child.uri.toString(),
                        "name" to childName,
                        "relativePath" to relativePath,
                        "size" to child.length(),
                        "modifiedTimeMs" to child.lastModified(),
                        "mimeType" to (child.type ?: ""),
                    ),
                )
            }
        }

        walk(root, "")

        val hasReadPermission = contentResolver.persistedUriPermissions.any {
            it.uri == uri && it.isReadPermission
        }

        return mapOf(
            "pickerType" to "saf",
            "androidSdk" to Build.VERSION.SDK_INT,
            "permissionStatus" to if (hasReadPermission) "granted" else "pending",
            "selectedPath" to "",
            "selectedUri" to folderUri,
            "selectedName" to selectedName,
            "usingSaf" to true,
            "childCount" to childCount,
            "entityCount" to entityCount,
            "supportedCount" to supportedCount,
            "firstChild" to firstChild,
            "firstSupported" to firstSupported,
            "files" to files,
        )
    }

    private fun copyLocalMusicFileToTemp(uriString: String, displayName: String): Map<String, Any?> {
        if (uriString.isBlank()) {
            return mapOf(
                "ok" to false,
                "error" to "missing_uri",
                "tempPath" to "",
            )
        }

        val uri = try {
            Uri.parse(uriString)
        } catch (_: Exception) {
            return mapOf(
                "ok" to false,
                "error" to "invalid_uri",
                "tempPath" to "",
            )
        }

        return try {
            val input = contentResolver.openInputStream(uri)
                ?: return mapOf(
                    "ok" to false,
                    "error" to "open_input_failed",
                    "tempPath" to "",
                )

            val suffix = when {
                displayName.endsWith(".flac", ignoreCase = true) -> ".flac"
                displayName.endsWith(".mp3", ignoreCase = true) -> ".mp3"
                displayName.endsWith(".m4a", ignoreCase = true) -> ".m4a"
                displayName.endsWith(".aac", ignoreCase = true) -> ".aac"
                displayName.endsWith(".wav", ignoreCase = true) -> ".wav"
                displayName.endsWith(".ogg", ignoreCase = true) -> ".ogg"
                displayName.endsWith(".opus", ignoreCase = true) -> ".opus"
                displayName.endsWith(".wma", ignoreCase = true) -> ".wma"
                displayName.endsWith(".alac", ignoreCase = true) -> ".alac"
                displayName.endsWith(".aiff", ignoreCase = true) -> ".aiff"
                displayName.endsWith(".aif", ignoreCase = true) -> ".aif"
                else -> ""
            }
            val tempFile = File.createTempFile("infame_local_", suffix, cacheDir)
            tempFile.outputStream().use { output ->
                input.use { it.copyTo(output) }
            }
            mapOf(
                "ok" to true,
                "error" to "",
                "tempPath" to tempFile.absolutePath,
            )
        } catch (e: Exception) {
            mapOf(
                "ok" to false,
                "error" to (e.message ?: e.toString()),
                "tempPath" to "",
            )
        }
    }

    private fun isSupportedAudioFile(name: String): Boolean {
        val lower = name.lowercase(Locale.US)
        return lower.endsWith(".mp3") ||
            lower.endsWith(".flac") ||
            lower.endsWith(".m4a") ||
            lower.endsWith(".aac") ||
            lower.endsWith(".wav") ||
            lower.endsWith(".ogg") ||
            lower.endsWith(".opus") ||
            lower.endsWith(".wma") ||
            lower.endsWith(".alac") ||
            lower.endsWith(".aiff") ||
            lower.endsWith(".aif")
    }
}
