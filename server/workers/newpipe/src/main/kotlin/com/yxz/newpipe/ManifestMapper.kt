package com.yxz.newpipe

import com.google.gson.Gson
import com.google.gson.JsonArray
import com.google.gson.JsonObject
import org.schabi.newpipe.extractor.stream.AudioStream
import org.schabi.newpipe.extractor.stream.StreamInfo
import org.schabi.newpipe.extractor.stream.VideoStream
import java.time.Instant

object ManifestMapper {
    private val gson = Gson()

    fun toPlaybackManifestJson(info: StreamInfo, videoId: String): String {
        val now = Instant.now()
        val expires = now.plusSeconds(5 * 60)

        val videoStreams = JsonArray()
        val audioStreams = JsonArray()

        for (s in info.videoOnlyStreams) {
            videoStreams.add(videoToJson(s, isVideoOnly = true))
        }
        for (s in info.videoStreams) {
            videoStreams.add(videoToJson(s, isVideoOnly = false))
        }
        for (s in info.audioStreams) {
            audioStreams.add(audioToJson(s))
        }

        val delivery = JsonObject()
        val hls = info.hlsUrl
        val dash = info.dashMpdUrl
        when {
            !hls.isNullOrBlank() -> {
                delivery.addProperty("type", "hls")
                delivery.addProperty("manifestUrl", hls)
            }
            !dash.isNullOrBlank() -> {
                delivery.addProperty("type", "dash")
                delivery.addProperty("manifestUrl", dash)
            }
            info.videoOnlyStreams.isNotEmpty() && info.audioStreams.isNotEmpty() -> {
                delivery.addProperty("type", "adaptive")
            }
            else -> delivery.addProperty("type", "progressive")
        }

        val root = JsonObject()
        root.addProperty("schemaVersion", 1)
        root.addProperty("videoId", videoId)
        root.addProperty("title", info.name ?: videoId)
        root.addProperty("source", "youtube")
        root.addProperty("durationMs", info.duration * 1000L)
        root.addProperty("resolvedAt", now.toString())
        root.addProperty("expiresAt", expires.toString())
        root.add("delivery", delivery)
        root.add("videoStreams", videoStreams)
        root.add("audioStreams", audioStreams)
        root.add("subtitles", JsonArray())
        root.add("headers", JsonObject())
        info.uploaderName?.let { root.addProperty("uploader", it) }
        runCatching {
            info.thumbnails.firstOrNull()?.url
        }.getOrNull()?.let { root.addProperty("thumbnail", it) }
        info.url?.let { root.addProperty("webpageUrl", it) }

        return gson.toJson(root)
    }

    private fun videoToJson(s: VideoStream, isVideoOnly: Boolean): JsonObject {
        val o = JsonObject()
        val height = when {
            s.height > 0 -> s.height
            else -> parseHeight(s.resolution)
        }
        val formatId = runCatching { s.format?.id }.getOrNull() ?: 0
        o.addProperty("id", "np-v-$height-$formatId")
        o.addProperty("url", s.content)
        o.addProperty("height", height.coerceAtLeast(1))
        if (s.width > 0) o.addProperty("width", s.width)
        if (s.fps > 0) o.addProperty("fps", s.fps.toDouble())
        runCatching {
            val br = s.bitrate
            if (br > 0) o.addProperty("bitrate", br)
        }
        o.addProperty("codec", s.codec ?: s.format?.name)
        o.addProperty("mimeType", s.format?.mimeType)
        o.addProperty("ext", s.format?.suffix)
        o.addProperty("isVideoOnly", isVideoOnly)
        o.addProperty("hdr", false)
        return o
    }

    private fun audioToJson(s: AudioStream): JsonObject {
        val o = JsonObject()
        val formatId = runCatching { s.format?.id }.getOrNull() ?: 0
        o.addProperty("id", "np-a-${s.averageBitrate}-$formatId")
        o.addProperty("url", s.content)
        if (s.averageBitrate > 0) o.addProperty("bitrate", s.averageBitrate)
        o.addProperty("codec", s.codec ?: s.format?.name)
        o.addProperty("mimeType", s.format?.mimeType)
        o.addProperty("ext", s.format?.suffix)
        return o
    }

    private fun parseHeight(resolution: String?): Int {
        if (resolution.isNullOrBlank()) return 360
        val m = Regex("""(\d+)""").find(resolution)
        return m?.groupValues?.get(1)?.toIntOrNull() ?: 360
    }
}
