package com.ytdownloader.app

import android.util.Log
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.util.UUID

class MainActivity : FlutterActivity() {
    private val channel = "com.ytdownloader.app/ytdlp"
    private val progressChannel = "com.ytdownloader.app/ytdlp_progress"
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val activeJobs = mutableMapOf<String, Job>()
    private var progressSink: EventChannel.EventSink? = null
    private lateinit var botGuardMinter: BotGuardMinter

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        botGuardMinter = BotGuardMinter(this)

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            progressChannel,
        ).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    progressSink = events
                }

                override fun onCancel(arguments: Any?) {
                    progressSink = null
                }
            },
        )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel).setMethodCallHandler { call, result ->
            when (call.method) {
                "initialize" -> {
                    scope.launch {
                        try {
                            YoutubeDL.getInstance().init(this@MainActivity)
                            withContext(Dispatchers.Main) {
                                result.success("ok")
                            }
                        } catch (e: Exception) {
                            withContext(Dispatchers.Main) {
                                result.error("INIT_ERROR", e.message, null)
                            }
                        }
                    }
                }

                "getVersion" -> {
                    try {
                        val version = YoutubeDL.getInstance().version(this) ?: "unknown"
                        result.success(version)
                    } catch (e: Exception) {
                        result.error("VERSION_ERROR", e.message, null)
                    }
                }

                "fetchFormats" -> {
                    val url = call.argument<String>("url") ?: ""
                    val playerClient = call.argument<String>("playerClient") ?: "default"
                    val poToken = call.argument<String>("poToken")
                    val visitorData = call.argument<String>("visitorData")
                    scope.launch {
                        try {
                            val extractorArgs =
                                youtubeExtractorArgs(playerClient, poToken, visitorData)
                            Log.i(
                                "YTDownloader",
                                "fetchFormats client=$playerClient " +
                                    "hasPo=${!poToken.isNullOrBlank()} " +
                                    "hasVisitor=${!visitorData.isNullOrBlank()} " +
                                    "args=${extractorArgs.take(120)}",
                            )
                            val request = YoutubeDLRequest(url)
                            // Dump metadata only — never ask yt-dlp to download a
                            // specific format. ignore-no-formats-error returns JSON
                            // even when the selected client has zero HTTPS URLs.
                            request.addOption("--dump-single-json")
                            request.addOption("--no-playlist")
                            request.addOption("--no-warnings")
                            request.addOption("--ignore-no-formats-error")
                            request.addOption("--extractor-args", extractorArgs)
                            val response = YoutubeDL.getInstance().execute(request)
                            val out = response.out
                            val formatCount = try {
                                JSONObject(out).optJSONArray("formats")?.length() ?: 0
                            } catch (_: Exception) {
                                -1
                            }
                            Log.i(
                                "YTDownloader",
                                "fetchFormats done formats_found=$formatCount " +
                                    "outChars=${out.length}",
                            )
                            withContext(Dispatchers.Main) {
                                result.success(out)
                            }
                        } catch (e: Exception) {
                            Log.e("YTDownloader", "fetchFormats failed: ${e.message}")
                            withContext(Dispatchers.Main) {
                                result.error("FETCH_ERROR", e.message, null)
                            }
                        }
                    }
                }

                "isPlaylist" -> {
                    val url = call.argument<String>("url") ?: ""
                    scope.launch {
                        try {
                            val request = YoutubeDLRequest(url)
                            request.addOption("--flat-playlist")
                            request.addOption("--dump-single-json")
                            request.addOption("--playlist-items", "1")
                            request.addOption("--no-warnings")
                            request.addOption("--no-update")
                            val response = YoutubeDL.getInstance().execute(request)
                            val json = JSONObject(response.out)
                            val isPlaylist = json.optString("_type") == "playlist"
                            withContext(Dispatchers.Main) {
                                result.success(isPlaylist)
                            }
                        } catch (_: Exception) {
                            withContext(Dispatchers.Main) {
                                result.success(false)
                            }
                        }
                    }
                }

                "fetchPlaylistInfo" -> {
                    val url = call.argument<String>("url") ?: ""
                    scope.launch {
                        try {
                            val request = YoutubeDLRequest(url)
                            request.addOption("--flat-playlist")
                            request.addOption("--dump-single-json")
                            request.addOption("--no-warnings")
                            request.addOption("--no-update")
                            request.addOption("--playlist-end", "40")
                            val response = YoutubeDL.getInstance().execute(request)
                            withContext(Dispatchers.Main) {
                                result.success(response.out)
                            }
                        } catch (e: Exception) {
                            withContext(Dispatchers.Main) {
                                result.error("PLAYLIST_INFO_ERROR", e.message, null)
                            }
                        }
                    }
                }

                "download" -> {
                    val url = call.argument<String>("url") ?: ""
                    val formatId = call.argument<String>("formatId") ?: "best"
                    val outputPath = call.argument<String>("outputPath") ?: ""
                    val isPlaylist = call.argument<Boolean>("isPlaylist") ?: false
                    val embedThumbnail = call.argument<Boolean>("embedThumbnail") ?: false
                    val addMetadata = call.argument<Boolean>("addMetadata") ?: false
                    val downloadSubtitles = call.argument<Boolean>("downloadSubtitles") ?: false
                    val subtitleLanguage = call.argument<String>("subtitleLanguage") ?: "en"
                    val skipExisting = call.argument<Boolean>("skipExisting") ?: true
                    val rateLimit = call.argument<String>("rateLimit") ?: ""
                    val playerClient = call.argument<String>("playerClient") ?: "android,web"
                    val processId = call.argument<String>("processId") ?: UUID.randomUUID().toString()
                    Log.d("YTDownloader", "Starting download: url=$url format=$formatId output=$outputPath")

                    val request = YoutubeDLRequest(url)
                    request.addOption("-f", formatId)
                    configureDownloadRequest(
                        request = request,
                        outputPath = outputPath,
                        isPlaylist = isPlaylist,
                        embedThumbnail = embedThumbnail,
                        addMetadata = addMetadata,
                        downloadSubtitles = downloadSubtitles,
                        subtitleLanguage = subtitleLanguage,
                        skipExisting = skipExisting,
                        rateLimit = rateLimit,
                        playerClient = playerClient,
                    )

                    val job = scope.launch {
                        try {
                            Log.d("YTDownloader", "Executing yt-dlp for processId=$processId")
                            executeWithProgress(request, processId)
                            val completionData = mapOf(
                                "processId" to processId,
                                "status" to "completed",
                            )
                            Log.d("YTDownloader", "Download completed: processId=$processId")
                            withContext(Dispatchers.Main) {
                                progressSink?.success(completionData)
                            }
                        } catch (e: Exception) {
                            val message = e.message ?: "Unknown error"
                            val lower = message.lowercase()
                            val shouldFallback =
                                lower.contains("403") || lower.contains("forbidden")
                            if (shouldFallback && formatId != "best") {
                                try {
                                    Log.w(
                                        "YTDownloader",
                                        "403 detected for processId=$processId, retrying with format=best",
                                    )
                                    withContext(Dispatchers.Main) {
                                        progressSink?.success(
                                            mapOf(
                                                "processId" to processId,
                                                "percent" to -1.0,
                                                "eta" to "-1",
                                                "line" to "[download] 403 fallback retry with best format",
                                            ),
                                        )
                                    }
                                    val fallbackRequest = YoutubeDLRequest(url)
                                    fallbackRequest.addOption("-f", "best")
                                    configureDownloadRequest(
                                        request = fallbackRequest,
                                        outputPath = outputPath,
                                        isPlaylist = isPlaylist,
                                        embedThumbnail = embedThumbnail,
                                        addMetadata = addMetadata,
                                        downloadSubtitles = downloadSubtitles,
                                        subtitleLanguage = subtitleLanguage,
                                        skipExisting = skipExisting,
                                        rateLimit = rateLimit,
                                        playerClient = playerClient,
                                    )
                                    executeWithProgress(fallbackRequest, processId)
                                    val completionData = mapOf(
                                        "processId" to processId,
                                        "status" to "completed",
                                    )
                                    withContext(Dispatchers.Main) {
                                        progressSink?.success(completionData)
                                    }
                                    return@launch
                                } catch (fallbackError: Exception) {
                                    Log.e(
                                        "YTDownloader",
                                        "Fallback retry failed: processId=$processId error=${fallbackError.message}",
                                    )
                                }
                            }
                            Log.e("YTDownloader", "Download failed: processId=$processId error=$message")
                            val errorData = mapOf(
                                "processId" to processId,
                                "status" to "failed",
                                "error" to message,
                            )
                            withContext(Dispatchers.Main) {
                                progressSink?.success(errorData)
                            }
                        } finally {
                            activeJobs.remove(processId)
                            if (activeJobs.isEmpty()) {
                                DownloadForegroundService.stop(this@MainActivity)
                            }
                        }
                    }

                    activeJobs[processId] = job
                    DownloadForegroundService.start(this@MainActivity, activeJobs.size)
                    result.success(processId)
                }

                "cancel" -> {
                    val processId = call.argument<String>("processId") ?: ""
                    try {
                        YoutubeDL.getInstance().destroyProcessById(processId)
                        activeJobs[processId]?.cancel()
                        activeJobs.remove(processId)
                        if (activeJobs.isEmpty()) {
                            DownloadForegroundService.stop(this@MainActivity)
                        } else {
                            DownloadForegroundService.start(
                                this@MainActivity,
                                activeJobs.size,
                            )
                        }
                        result.success("ok")
                    } catch (e: Exception) {
                        result.error("CANCEL_ERROR", e.message, null)
                    }
                }

                "openFile" -> {
                    val path = call.argument<String>("path") ?: ""
                    try {
                        val file = java.io.File(path)
                        val uri = androidx.core.content.FileProvider.getUriForFile(
                            this,
                            "${packageName}.fileprovider",
                            file
                        )
                        val mimeType = getMimeTypeForPath(path)
                        val intent = android.content.Intent(android.content.Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, mimeType)
                            addFlags(android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        val chooser = android.content.Intent.createChooser(intent, "Open with")
                        startActivity(chooser)
                        result.success("ok")
                    } catch (e: Exception) {
                        result.error("OPEN_ERROR", e.message, null)
                    }
                }

                "shareFile" -> {
                    val path = call.argument<String>("path") ?: ""
                    try {
                        val file = java.io.File(path)
                        val uri = androidx.core.content.FileProvider.getUriForFile(
                            this,
                            "${packageName}.fileprovider",
                            file
                        )
                        val mimeType = getMimeTypeForPath(path)
                        val intent = android.content.Intent(android.content.Intent.ACTION_SEND).apply {
                            type = mimeType
                            putExtra(android.content.Intent.EXTRA_STREAM, uri)
                            addFlags(android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                        val chooser = android.content.Intent.createChooser(intent, "Share via")
                        chooser.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(chooser)
                        result.success("ok")
                    } catch (e: Exception) {
                        result.error("SHARE_ERROR", e.message, null)
                    }
                }

                "updateYoutubeDL" -> {
                    scope.launch {
                        try {
                            val status = YoutubeDL.getInstance().updateYoutubeDL(
                                this@MainActivity,
                                YoutubeDL.UpdateChannel.STABLE,
                            )
                            withContext(Dispatchers.Main) {
                                result.success(status.toString())
                            }
                        } catch (e: Exception) {
                            withContext(Dispatchers.Main) {
                                result.error("UPDATE_ERROR", e.message, null)
                            }
                        }
                    }
                }

                "enterPip" -> {
                    try {
                        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                            val params = android.app.PictureInPictureParams.Builder()
                                .setAspectRatio(android.util.Rational(16, 9))
                                .build()
                            val entered = enterPictureInPictureMode(params)
                            result.success(entered)
                        } else {
                            result.success(false)
                        }
                    } catch (e: Exception) {
                        result.error("PIP_ERROR", e.message, null)
                    }
                }

                "setPlaybackService" -> {
                    val active = call.argument<Boolean>("active") ?: false
                    try {
                        if (active) {
                            PlaybackForegroundService.start(this)
                        } else {
                            PlaybackForegroundService.stop(this)
                        }
                        result.success("ok")
                    } catch (e: Exception) {
                        result.error("PLAYBACK_SERVICE_ERROR", e.message, null)
                    }
                }

                "ensurePoMinter" -> {
                    scope.launch {
                        try {
                            botGuardMinter.ensure()
                            withContext(Dispatchers.Main) {
                                result.success("ok")
                            }
                        } catch (e: Exception) {
                            Log.e("YTDownloader", "BotGuard ensure failed", e)
                            withContext(Dispatchers.Main) {
                                result.error("POT_ERROR", e.message, null)
                            }
                        }
                    }
                }

                "mintPoTokens" -> {
                    val videoId = call.argument<String>("videoId") ?: ""
                    scope.launch {
                        try {
                            val tokens = botGuardMinter.mint(videoId)
                            withContext(Dispatchers.Main) {
                                result.success(tokens)
                            }
                        } catch (e: Exception) {
                            Log.e("YTDownloader", "BotGuard mint failed", e)
                            withContext(Dispatchers.Main) {
                                result.error("POT_ERROR", e.message, null)
                            }
                        }
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun getMimeTypeForPath(path: String): String {
        val lower = path.lowercase()
        return when {
            lower.endsWith(".mp3") -> "audio/mpeg"
            lower.endsWith(".m4a") -> "audio/mp4"
            lower.endsWith(".opus") -> "audio/opus"
            lower.endsWith(".ogg") -> "audio/ogg"
            lower.endsWith(".flac") -> "audio/flac"
            lower.endsWith(".wav") -> "audio/wav"
            lower.endsWith(".mp4") -> "video/mp4"
            lower.endsWith(".mkv") -> "video/x-matroska"
            lower.endsWith(".webm") -> "video/webm"
            lower.endsWith(".mov") -> "video/quicktime"
            else -> "*/*"
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        if (isFinishing) {
            scope.cancel()
            DownloadForegroundService.stop(this)
        }
    }

    private fun executeWithProgress(request: YoutubeDLRequest, processId: String) {
        YoutubeDL.getInstance().execute(request, processId) { progress, etaInSeconds, line ->
            Log.d("YTDownloader", "Progress: $progress% eta=$etaInSeconds line=$line")
            val progressData = mapOf(
                "processId" to processId,
                "percent" to progress.toDouble(),
                "eta" to etaInSeconds.toString(),
                "line" to line,
            )
            CoroutineScope(Dispatchers.Main).launch {
                progressSink?.success(progressData)
            }
        }
    }

    private fun configureDownloadRequest(
        request: YoutubeDLRequest,
        outputPath: String,
        isPlaylist: Boolean,
        embedThumbnail: Boolean,
        addMetadata: Boolean,
        downloadSubtitles: Boolean,
        subtitleLanguage: String,
        skipExisting: Boolean,
        rateLimit: String,
        playerClient: String = "android,web",
    ) {
        request.addOption("-o", "$outputPath/%(title)s.%(ext)s")
        request.addOption("--no-warnings")
        request.addOption("--extractor-args", youtubeExtractorArgs(playerClient))
        request.addOption("--parse-metadata", ":(?P<comment>Downloaded with yt-dlp App)")
        if (!isPlaylist) {
            request.addOption("--no-playlist")
        } else {
            request.addOption("--yes-playlist")
        }
        if (embedThumbnail) {
            request.addOption("--embed-thumbnail")
            request.addOption("--convert-thumbnails", "jpg")
            Log.d("YTDownloader", "Thumbnail embedding enabled with jpg conversion")
        }
        if (addMetadata) {
            request.addOption("--add-metadata")
        }
        if (downloadSubtitles) {
            request.addOption("--write-auto-sub")
            request.addOption("--sub-lang", subtitleLanguage)
        }
        if (skipExisting) {
            request.addOption("--no-overwrites")
        }
        if (rateLimit.isNotEmpty()) {
            request.addOption("--rate-limit", rateLimit)
        }
    }

    private fun youtubeExtractorArgs(
        playerClient: String,
        poToken: String? = null,
        visitorData: String? = null,
    ): String {
        val client = playerClient.trim()
        val parts = mutableListOf<String>()
        // "default" / blank → let yt-dlp pick its built-in YouTube clients.
        if (client.isNotEmpty() && !client.equals("default", ignoreCase = true)) {
            parts += "player_client=$client"
        }
        val token = poToken?.trim().orEmpty()
        if (token.isNotEmpty()) {
            parts += "po_token=$token"
        }
        val visitor = visitorData?.trim().orEmpty()
        if (visitor.isNotEmpty()) {
            parts += "visitor_data=$visitor"
        }
        return if (parts.isEmpty()) {
            "youtube:"
        } else {
            "youtube:" + parts.joinToString(";")
        }
    }
}
