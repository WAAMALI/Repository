package com.tvexp.iptv

import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.net.Uri
import android.os.Environment
import android.database.Cursor
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.tvexp.iptv/downloads"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.tvexp.iptv/player").setMethodCallHandler { call, result ->
            when (call.method) {
                "openExternalPlayer" -> {
                    val rawUrl = call.argument<String>("url")
                    val title = call.argument<String>("title") ?: "TVEXP"
                    val isLocalFile = call.argument<Boolean>("isLocalFile") ?: false

                    if (rawUrl.isNullOrBlank()) {
                        result.error("INVALID_URL", "Playback URL is empty", null)
                        return@setMethodCallHandler
                    }

                    try {
                        val mediaUri = when {
                            rawUrl.startsWith("content://", ignoreCase = true) ->
                                Uri.parse(rawUrl)

                            rawUrl.startsWith("file://", ignoreCase = true) -> {
                                val localFile = java.io.File(Uri.parse(rawUrl).path ?: "")
                                if (!localFile.exists() || !localFile.isFile) {
                                    result.error("FILE_NOT_FOUND", "Local media file was not found", null)
                                    return@setMethodCallHandler
                                }
                                androidx.core.content.FileProvider.getUriForFile(
                                    this,
                                    "$packageName.fileprovider",
                                    localFile
                                )
                            }

                            isLocalFile -> {
                                val localFile = java.io.File(rawUrl)
                                if (!localFile.exists() || !localFile.isFile) {
                                    result.error("FILE_NOT_FOUND", "Local media file was not found", null)
                                    return@setMethodCallHandler
                                }
                                androidx.core.content.FileProvider.getUriForFile(
                                    this,
                                    "$packageName.fileprovider",
                                    localFile
                                )
                            }

                            else -> Uri.parse(rawUrl)
                        }

                        // Determine MIME type from the URL path, excluding query parameters.
                        val path = Uri.parse(rawUrl).path?.lowercase().orEmpty()
                        val mimeType = when {
                            path.endsWith(".m3u8") -> "application/vnd.apple.mpegurl"
                            path.endsWith(".mpd") -> "application/dash+xml"
                            path.endsWith(".mp3") || path.endsWith(".aac") -> "audio/*"
                            else -> "video/*"
                        }

                        // VLC is the default player. If it is unavailable or cannot
                        // handle this URI, fall back to Android's player chooser.
                        val vlcIntent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(mediaUri, mimeType)
                            setPackage("org.videolan.vlc")
                            putExtra("title", title)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }

                        try {
                            startActivity(vlcIntent)
                            result.success(true)
                        } catch (_: android.content.ActivityNotFoundException) {
                            val fallbackIntent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(mediaUri, mimeType)
                                putExtra("title", title)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            try {
                                startActivity(
                                    Intent.createChooser(fallbackIntent, "اختيار مشغل الفيديو")
                                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                )
                                result.success(true)
                            } catch (_: android.content.ActivityNotFoundException) {
                                result.error(
                                    "NO_EXTERNAL_PLAYER",
                                    "VLC is not installed and no compatible video player was found",
                                    null
                                )
                            }
                        }
                    } catch (e: Exception) {
                        result.error("PLAYER_LAUNCH_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.tvexp.iptv/updates").setMethodCallHandler { call, result ->
            when (call.method) {
                "getUpdateConfig" -> {
                    result.success(mapOf(
                        "flavor" to BuildConfig.FLAVOR,
                        "versionName" to BuildConfig.VERSION_NAME,
                        "versionCode" to BuildConfig.VERSION_CODE,
                        "applicationId" to BuildConfig.APPLICATION_ID
                    ))
                }
                "installApk" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrBlank()) {
                        result.error("INVALID_PATH", "APK path is required", null)
                    } else {
                        try {
                            val apk = java.io.File(path)
                            if (!apk.exists() || !apk.isFile) {
                                result.error("APK_NOT_FOUND", "Downloaded update APK not found", null)
                            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                                !packageManager.canRequestPackageInstalls()) {
                                val settingsIntent = Intent(
                                    android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                    Uri.parse("package:$packageName")
                                )
                                startActivity(settingsIntent)
                                result.success("permission_required")
                            } else {
                                val apkUri = androidx.core.content.FileProvider.getUriForFile(
                                    this, "$packageName.fileprovider", apk
                                )
                                val installIntent = Intent(Intent.ACTION_VIEW).apply {
                                    setDataAndType(apkUri, "application/vnd.android.package-archive")
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                }
                                startActivity(installIntent)
                                result.success("installer_opened")
                            }
                        } catch (e: Exception) {
                            result.error("INSTALL_FAILED", e.message, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            val manager = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
            when (call.method) {
                "startInternalForeground" -> {
                    try {
                        val intent = Intent(this, DownloadForegroundService::class.java)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(intent)
                        else startService(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("FOREGROUND_START_FAILED", e.message, null)
                    }
                }
                "stopInternalForeground" -> {
                    stopService(Intent(this, DownloadForegroundService::class.java))
                    result.success(true)
                }
                "enqueue" -> {
                    val url = call.argument<String>("url")
                    val fileName = call.argument<String>("fileName")
                    val title = call.argument<String>("title") ?: fileName
                    if (url.isNullOrBlank() || fileName.isNullOrBlank()) {
                        result.error("INVALID_ARGUMENT", "url and fileName are required", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val uri = Uri.parse(url)
                        if (uri.scheme != "http" && uri.scheme != "https") {
                            result.error("INVALID_URL", "Only HTTP/HTTPS downloads are supported", null)
                            return@setMethodCallHandler
                        }
                        val request = DownloadManager.Request(uri)
                            .setTitle(title)
                            .setDescription("TVEXP IPTV")
                            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                            .setAllowedOverMetered(true)
                            .setAllowedOverRoaming(false)
                            .setDestinationInExternalFilesDir(this, Environment.DIRECTORY_DOWNLOADS, fileName)
                        result.success(manager.enqueue(request))
                    } catch (e: Exception) {
                        result.error("DOWNLOAD_FAILED", e.message, null)
                    }
                }
                "queryAll" -> {
                    val items = mutableListOf<Map<String, Any?>>()
                    var cursor: Cursor? = null
                    try {
                        val c = manager.query(DownloadManager.Query())
                        cursor = c
                        while (c.moveToNext()) {
                            fun longColumn(name: String): Long {
                                val index = c.getColumnIndex(name)
                                return if (index >= 0) c.getLong(index) else 0L
                            }
                            fun stringColumn(name: String): String? {
                                val index = c.getColumnIndex(name)
                                return if (index >= 0) c.getString(index) else null
                            }
                            val status = longColumn(DownloadManager.COLUMN_STATUS).toInt()
                            val reason = longColumn(DownloadManager.COLUMN_REASON).toInt()
                            items.add(mapOf(
                                "id" to longColumn(DownloadManager.COLUMN_ID),
                                "title" to stringColumn(DownloadManager.COLUMN_TITLE),
                                "description" to stringColumn(DownloadManager.COLUMN_DESCRIPTION),
                                "status" to status,
                                "reason" to reason,
                                "downloaded" to longColumn(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR),
                                "total" to longColumn(DownloadManager.COLUMN_TOTAL_SIZE_BYTES),
                                "localUri" to stringColumn(DownloadManager.COLUMN_LOCAL_URI),
                                "contentUri" to manager.getUriForDownloadedFile(longColumn(DownloadManager.COLUMN_ID))?.toString(),
                                "uri" to stringColumn(DownloadManager.COLUMN_URI)
                            ))
                        }
                        result.success(items)
                    } catch (e: Exception) {
                        result.error("QUERY_FAILED", e.message, null)
                    } finally {
                        cursor?.close()
                    }
                }
                "remove" -> {
                    val id = call.argument<Number>("id")?.toLong()
                    if (id == null) {
                        result.error("INVALID_ARGUMENT", "id is required", null)
                    } else {
                        result.success(manager.remove(id))
                    }
                }
                "shareExternal" -> {
                    val url = call.argument<String>("url")
                    val fileName = call.argument<String>("fileName")
                    if (url.isNullOrBlank()) {
                        result.error("INVALID_ARGUMENT", "url is required", null)
                        return@setMethodCallHandler
                    }
                    val intent = Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(Intent.EXTRA_TEXT, url)
                        putExtra(Intent.EXTRA_SUBJECT, fileName ?: "TVEXP download")
                    }
                    startActivity(Intent.createChooser(intent, "فتح باستخدام مدير تحميل خارجي"))
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
}
