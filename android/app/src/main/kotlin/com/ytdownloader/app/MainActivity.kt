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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

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
                    try {
                        YoutubeDL.getInstance().init(this)
                        result.success("ok")
                    } catch (e: Exception) {
                        result.error("INIT_ERROR", e.message, null)
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
                    scope.launch {
                        try {
                            val request = YoutubeDLRequest(url)
                            request.addOption("-J")
                            request.addOption("--no-playlist")
                            request.addOption("--no-warnings")
                            val response = YoutubeDL.getInstance().execute(request)
                            withContext(Dispatchers.Main) {
                                result.success(response.out)
                            }
                        } catch (e: Exception) {
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
                    val processId = call.argument<String>("processId") ?: UUID.randomUUID().toString()
                    Log.d("YTDownloader", "Starting download: url=$url format=$formatId output=$outputPath")

                    val request = YoutubeDLRequest(url)
                    request.addOption("-f", formatId)
                    request.addOption("-o", "$outputPath/%(title)s.%(ext)s")
                    request.addOption("--no-warnings")
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

                    val job = scope.launch {
                        try {
                            Log.d("YTDownloader", "Executing yt-dlp for processId=$processId")
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
                            val completionData = mapOf(
                                "processId" to processId,
                                "status" to "completed",
                            )
                            Log.d("YTDownloader", "Download completed: processId=$processId")
                            withContext(Dispatchers.Main) {
                                progressSink?.success(completionData)
                            }
                        } catch (e: Exception) {
                            Log.e("YTDownloader", "Download failed: processId=$processId error=${e.message}")
                            val errorData = mapOf(
                                "processId" to processId,
                                "status" to "failed",
                                "error" to (e.message ?: "Unknown error"),
                            )
                            withContext(Dispatchers.Main) {
                                progressSink?.success(errorData)
                            }
                        } finally {
                            activeJobs.remove(processId)
                        }
                    }

                    activeJobs[processId] = job
                    result.success(processId)
                }

                "cancel" -> {
                    val processId = call.argument<String>("processId") ?: ""
                    try {
                        YoutubeDL.getInstance().destroyProcessById(processId)
                        activeJobs[processId]?.cancel()
                        activeJobs.remove(processId)
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
                        val intent = android.content.Intent(android.content.Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, "video/*")
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

                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        scope.cancel()
    }
}
