package com.ytdownloader.app

import android.annotation.SuppressLint
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.webkit.ConsoleMessage
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.nio.charset.StandardCharsets
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/**
 * Mints YouTube web PO tokens the same way youtube.com does:
 * WAA Create → BotGuard VM snapshot → GenerateIT → WebPoMinter.
 *
 * BotGuard (web), not DroidGuard (official Android YouTube).
 */
class BotGuardMinter(private val context: Context) {
    private val main = Handler(Looper.getMainLooper())
    private val lock = Any()
    @Volatile private var webView: WebView? = null
    @Volatile private var pageReady = false
    @Volatile private var integrityUntilMs: Long = 0
    @Volatile private var visitorData: String = ""
    private val jsResult = AtomicReference<JsOutcome?>(null)
    private var jsLatch: CountDownLatch? = null

    private class JsOutcome(val ok: Boolean, val value: String)

    inner class JsBridge {
        @JavascriptInterface
        fun ok(value: String?) {
            jsResult.set(JsOutcome(true, value ?: ""))
            jsLatch?.countDown()
        }

        @JavascriptInterface
        fun err(value: String?) {
            jsResult.set(JsOutcome(false, value ?: "js error"))
            jsLatch?.countDown()
        }
    }

    fun ensure() {
        synchronized(lock) {
            val now = System.currentTimeMillis()
            if (pageReady && webView != null && now < integrityUntilMs - 60_000L) {
                return
            }
            ensureWebViewLocked()
            warmLocked()
        }
    }

    fun mint(videoId: String): Map<String, String> {
        synchronized(lock) {
            ensure()
            val player = callAsync("botguardMint(${JSONObject.quote(videoId)})")
            if (player.isBlank()) {
                throw IllegalStateException("BotGuard mint(player) empty")
            }
            val visitor = visitorData.ifBlank {
                throw IllegalStateException("visitorData empty")
            }
            val gvs = callAsync("botguardMint(${JSONObject.quote(visitor)})")
            if (gvs.isBlank()) {
                throw IllegalStateException("BotGuard mint(gvs) empty")
            }
            Log.i(TAG, "BotGuard minted player+GVS tokens")
            return mapOf(
                "player" to player,
                "gvs" to gvs,
                "visitorData" to visitor,
            )
        }
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun ensureWebViewLocked() {
        if (webView != null && pageReady) {
            return
        }
        val latch = CountDownLatch(1)
        val error = AtomicReference<String?>(null)
        main.post {
            try {
                val view = WebView(context.applicationContext)
                val settings = view.settings
                settings.javaScriptEnabled = true
                settings.domStorageEnabled = true
                settings.allowFileAccess = true
                @Suppress("DEPRECATION")
                settings.allowFileAccessFromFileURLs = true
                @Suppress("DEPRECATION")
                settings.allowUniversalAccessFromFileURLs = true
                settings.cacheMode = WebSettings.LOAD_NO_CACHE
                settings.userAgentString = USER_AGENT
                view.addJavascriptInterface(JsBridge(), "BotGuardBridge")
                view.webChromeClient = object : WebChromeClient() {
                    override fun onConsoleMessage(consoleMessage: ConsoleMessage): Boolean {
                        Log.d(TAG, "js: ${consoleMessage.message()}")
                        return true
                    }
                }
                view.webViewClient = object : WebViewClient() {
                    override fun onPageFinished(view: WebView?, url: String?) {
                        pageReady = true
                        latch.countDown()
                    }
                }
                webView = view
                pageReady = false
                view.loadUrl("file:///android_asset/botguard/index.html")
            } catch (e: Exception) {
                error.set(e.message)
                latch.countDown()
            }
        }
        if (!latch.await(15, TimeUnit.SECONDS)) {
            throw IllegalStateException("BotGuard WebView timed out")
        }
        error.get()?.let { throw IllegalStateException("BotGuard WebView: $it") }
        if (!pageReady) {
            throw IllegalStateException("BotGuard page not ready")
        }
    }

    private fun warmLocked() {
        Log.i(TAG, "BotGuard Create")
        val challenge = fetchChallenge()
        if (challenge.interpreterJavascript.isBlank() ||
            challenge.program.isBlank() ||
            challenge.globalName.isBlank()
        ) {
            throw IllegalStateException("Create failed: missing VM/program/globalName")
        }
        callAsync(
            "botguardInjectInterpreter(${JSONObject.quote(challenge.interpreterJavascript)})",
        )
        callAsync(
            "botguardLoad(${JSONObject.quote(challenge.program)}, " +
                JSONObject.quote(challenge.globalName) + ")",
        )
        val snapshot = callAsync("botguardSnapshot()")
        if (snapshot.isBlank()) {
            throw IllegalStateException("snapshot failed")
        }
        Log.i(TAG, "BotGuard GenerateIT")
        val integrity = generateIntegrityToken(snapshot)
        callAsync("botguardSetIntegrityToken(${JSONObject.quote(integrity.token)})")
        integrityUntilMs = System.currentTimeMillis() + integrity.ttlSec * 1000L
        if (visitorData.isBlank()) {
            visitorData = fetchVisitorData()
        }
        if (visitorData.isBlank()) {
            throw IllegalStateException("Could not read VISITOR_DATA")
        }
        Log.i(TAG, "BotGuard minter ready ttl=${integrity.ttlSec}s")
    }

    private data class Challenge(
        val interpreterJavascript: String,
        val program: String,
        val globalName: String,
    )

    private data class Integrity(val token: String, val ttlSec: Long)

    private fun fetchChallenge(): Challenge {
        val body = postJson(CREATE_URL, """["$REQUEST_KEY"]""")
        val parsed = try {
            BotGuardChallengeParser.parse(body)
        } catch (e: Exception) {
            Log.w(TAG, "Create payload (truncated): ${body.take(200)}")
            throw e
        }
        var js = parsed.interpreterJavascript
        if (js.isBlank() && parsed.interpreterUrl.isNotBlank()) {
            if (BotGuardChallengeParser.isInterpreterUrl(parsed.interpreterUrl)) {
                js = fetchText(absoluteInterpreterUrl(parsed.interpreterUrl))
            } else {
                js = parsed.interpreterUrl
            }
        }
        if (js.isBlank() || parsed.program.isBlank() || parsed.globalName.isBlank()) {
            throw IllegalStateException("Create missing fields program/globalName/js")
        }
        return Challenge(js, parsed.program, parsed.globalName)
    }

    private fun generateIntegrityToken(botguardResponse: String): Integrity {
        val payload = JSONArray().put(REQUEST_KEY).put(botguardResponse).toString()
        val raw = postJson(GENERATE_IT_URL, payload)
        val arr = JSONArray(raw)
        val token = arr.optString(0)
        if (token.isBlank()) {
            throw IllegalStateException("GenerateIT empty: $raw")
        }
        val ttl = arr.optLong(1, 21600L)
        return Integrity(token, if (ttl > 0) ttl else 21600L)
    }

    private fun fetchVisitorData(): String {
        val conn = URL("https://www.youtube.com").openConnection() as HttpURLConnection
        conn.requestMethod = "GET"
        conn.connectTimeout = 15_000
        conn.readTimeout = 15_000
        conn.instanceFollowRedirects = true
        conn.setRequestProperty("User-Agent", USER_AGENT)
        conn.setRequestProperty("Accept-Language", "en-US,en;q=0.9")
        val html = conn.inputStream.bufferedReader().use { it.readText() }
        conn.disconnect()
        val match = Regex("\"VISITOR_DATA\"\\s*:\\s*\"([^\"]+)\"").find(html)
            ?: Regex("'VISITOR_DATA'\\s*:\\s*'([^']+)'").find(html)
        return match?.groupValues?.get(1).orEmpty()
    }

    private fun postJson(url: String, body: String): String {
        val conn = URL(url).openConnection() as HttpURLConnection
        conn.requestMethod = "POST"
        conn.doOutput = true
        conn.connectTimeout = 20_000
        conn.readTimeout = 20_000
        conn.setRequestProperty("Content-Type", "application/json+protobuf")
        conn.setRequestProperty("Accept", "application/json+protobuf")
        conn.setRequestProperty("User-Agent", USER_AGENT)
        conn.setRequestProperty("x-goog-api-key", API_KEY)
        conn.setRequestProperty("x-user-agent", "grpc-web-javascript/0.1")
        conn.outputStream.use { it.write(body.toByteArray(StandardCharsets.UTF_8)) }
        val stream = if (conn.responseCode in 200..299) conn.inputStream else conn.errorStream
        val text = stream?.bufferedReader()?.use { it.readText() }.orEmpty()
        val code = conn.responseCode
        conn.disconnect()
        if (code !in 200..299) {
            throw IllegalStateException("HTTP $code $url: $text")
        }
        return text
    }

    private fun absoluteInterpreterUrl(raw: String): String {
        val trimmed = raw.trim()
        if (!BotGuardChallengeParser.isInterpreterUrl(trimmed)) {
            throw IllegalStateException("Interpreter URL is not a host")
        }
        return when {
            trimmed.startsWith("//") -> "https:$trimmed"
            trimmed.startsWith("http://") || trimmed.startsWith("https://") -> trimmed
            else -> "https://www.youtube.com/$trimmed"
        }
    }

    private fun fetchText(url: String): String {
        val conn = try {
            URL(url).openConnection() as HttpURLConnection
        } catch (e: Exception) {
            throw IllegalStateException("Invalid interpreter URL: ${url.take(80)}")
        }
        conn.requestMethod = "GET"
        conn.connectTimeout = 20_000
        conn.readTimeout = 20_000
        conn.instanceFollowRedirects = true
        conn.setRequestProperty("User-Agent", USER_AGENT)
        val stream = if (conn.responseCode in 200..299) conn.inputStream else conn.errorStream
        val text = stream?.bufferedReader()?.use { it.readText() }.orEmpty()
        val code = conn.responseCode
        conn.disconnect()
        if (code !in 200..299) {
            throw IllegalStateException("HTTP $code $url: ${text.take(200)}")
        }
        return text
    }

    private fun callAsync(promiseExpr: String): String {
        jsResult.set(null)
        jsLatch = CountDownLatch(1)
        val script =
            "(function(){$promiseExpr.then(function(v){BotGuardBridge.ok(String(v));})" +
                ".catch(function(e){BotGuardBridge.err(String(e&&e.message?e.message:e));});})();"
        evalRaw(script)
        if (jsLatch?.await(25, TimeUnit.SECONDS) != true) {
            throw IllegalStateException("JS promise timed out: $promiseExpr")
        }
        val outcome = jsResult.get() ?: throw IllegalStateException("JS produced no result")
        if (!outcome.ok) {
            throw IllegalStateException(outcome.value)
        }
        return outcome.value
    }

    private fun evalRaw(source: String) {
        val view = webView ?: throw IllegalStateException("WebView missing")
        val latch = CountDownLatch(1)
        main.post {
            view.evaluateJavascript(source) { latch.countDown() }
        }
        if (!latch.await(20, TimeUnit.SECONDS)) {
            throw IllegalStateException("evaluateJavascript timed out")
        }
    }

    companion object {
        private const val TAG = "BotGuardMinter"
        private const val REQUEST_KEY = "O43z0dpjhgX20SCx4KAo"
        private const val API_KEY = "AIzaSyDyT5W0Jh49F30Pqqtyfdf7pDLFKLJoAnw"
        private const val CREATE_URL =
            "https://jnn-pa.googleapis.com/\$rpc/google.internal.waa.v1.Waa/Create"
        private const val GENERATE_IT_URL =
            "https://jnn-pa.googleapis.com/\$rpc/google.internal.waa.v1.Waa/GenerateIT"
        private const val USER_AGENT =
            "Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 " +
                "(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36"
    }
}
