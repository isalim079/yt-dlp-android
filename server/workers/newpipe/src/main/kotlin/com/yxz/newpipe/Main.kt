package com.yxz.newpipe

import com.google.gson.Gson
import com.google.gson.JsonObject
import com.sun.net.httpserver.HttpExchange
import com.sun.net.httpserver.HttpServer
import org.schabi.newpipe.extractor.NewPipe
import org.schabi.newpipe.extractor.ServiceList
import org.schabi.newpipe.extractor.stream.StreamInfo
import java.io.OutputStreamWriter
import java.net.InetSocketAddress
import java.nio.charset.StandardCharsets
import java.util.concurrent.Executors

private val gson = Gson()

fun main() {
    NewPipe.init(OkHttpDownloader)
    val port = System.getenv("NEWPIPE_PORT")?.toIntOrNull() ?: 8091
    val server = HttpServer.create(InetSocketAddress(port), 0)
    server.executor = Executors.newFixedThreadPool(4)

    server.createContext("/health") { ex ->
        writeJson(ex, 200, """{"status":"ok","adapter":"newpipe"}""")
    }

    server.createContext("/internal/extract") { ex ->
        if (ex.requestMethod != "POST") {
            writeJson(ex, 405, """{"error":"method_not_allowed"}""")
            return@createContext
        }
        try {
            val body = ex.requestBody.bufferedReader().readText()
            val req = gson.fromJson(body, JsonObject::class.java)
            val videoId = req?.get("videoId")?.asString
                ?: throw IllegalArgumentException("videoId required")
            val url = "https://www.youtube.com/watch?v=$videoId"
            val info = StreamInfo.getInfo(ServiceList.YouTube, url)
            val json = ManifestMapper.toPlaybackManifestJson(info, videoId)
            writeJson(ex, 200, json)
        } catch (e: Exception) {
            System.err.println("newpipe extract failed: ${e.message}")
            e.printStackTrace()
            val err = JsonObject()
            err.addProperty("error", "EXTRACTOR_NO_STREAM")
            err.addProperty("message", e.message ?: "extract failed")
            writeJson(ex, 502, gson.toJson(err))
        }
    }

    server.start()
    println("yxz-newpipe listening on :$port")
}

private fun writeJson(ex: HttpExchange, code: Int, body: String) {
    val bytes = body.toByteArray(StandardCharsets.UTF_8)
    ex.responseHeaders.add("Content-Type", "application/json; charset=utf-8")
    ex.sendResponseHeaders(code, bytes.size.toLong())
    OutputStreamWriter(ex.responseBody, StandardCharsets.UTF_8).use { it.write(body) }
    ex.close()
}
