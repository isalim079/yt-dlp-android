package com.ytdownloader.app.feed

import android.util.Base64
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import org.schabi.newpipe.extractor.InfoItem
import org.schabi.newpipe.extractor.ListExtractor
import org.schabi.newpipe.extractor.NewPipe
import org.schabi.newpipe.extractor.Page
import org.schabi.newpipe.extractor.ServiceList
import org.schabi.newpipe.extractor.stream.StreamInfoItem
import java.util.concurrent.atomic.AtomicBoolean

/**
 * NewPipe Extractor bridge for Home (trending kiosk) and Shorts feeds.
 */
object FeedBridge {
    private const val TAG = "FeedBridge"
    private const val MAX_SKIP_EMPTY = 5
    private val initialized = AtomicBoolean(false)

    fun ensureInit() {
        if (initialized.compareAndSet(false, true)) {
            NewPipe.init(NewPipeDownloader)
            Log.i(TAG, "NewPipe initialized")
        }
    }

    fun fetchHomeFeed(continuation: String?): Map<String, Any?> {
        ensureInit()
        val service = ServiceList.YouTube
        val kioskList = service.kioskList
        val extractor = kioskList.defaultKioskExtractor
            ?: throw IllegalStateException("No default YouTube kiosk")
        return if (continuation.isNullOrBlank()) {
            extractor.fetchPage()
            pageToMap(extractor.initialPage, shortsOnly = false)
        } else {
            // Continuation only — never re-fetchPage() (that resets to page 1).
            pageToMap(extractor.getPage(decodePage(continuation)), shortsOnly = false)
        }
    }

    fun fetchShortsFeed(continuation: String?): Map<String, Any?> {
        ensureInit()
        val service = ServiceList.YouTube
        return try {
            collectNonEmpty(
                shortsOnly = true,
                startContinuation = continuation,
            ) { token ->
                val extractor = service.getSearchExtractor("#shorts")
                if (token.isNullOrBlank()) {
                    extractor.fetchPage()
                    extractor.initialPage
                } else {
                    extractor.getPage(decodePage(token))
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Shorts search failed, using home short filter: ${e.message}")
            val home = fetchHomeFeed(continuation)
            @Suppress("UNCHECKED_CAST")
            val items = (home["items"] as? List<Map<String, Any?>>) ?: emptyList()
            val shorts = items.filter { row ->
                (row["isShort"] as? Boolean) == true ||
                    ((row["duration"] as? Number)?.toInt() ?: 0) in 1..60
            }
            mapOf(
                "items" to if (shorts.isNotEmpty()) shorts else items.take(20),
                "continuation" to home["continuation"],
            )
        }
    }

    /**
     * Follows up to [MAX_SKIP_EMPTY] continuations until the batch has items
     * (after Shorts filter / in-page dedupe).
     */
    private fun collectNonEmpty(
        shortsOnly: Boolean,
        startContinuation: String?,
        load: (String?) -> ListExtractor.InfoItemsPage<out InfoItem>,
    ): Map<String, Any?> {
        val seen = LinkedHashSet<String>()
        val accumulated = ArrayList<Map<String, Any?>>()
        var token: String? = startContinuation
        var pages = 0
        var nextOut: String? = null

        while (pages < MAX_SKIP_EMPTY) {
            pages += 1
            val previousToken = token
            val page = load(token)
            val mapped = pageToMap(page, shortsOnly = shortsOnly)
            @Suppress("UNCHECKED_CAST")
            val items = (mapped["items"] as? List<Map<String, Any?>>) ?: emptyList()
            for (row in items) {
                val id = row["id"] as? String ?: continue
                if (seen.add(id)) {
                    accumulated.add(row)
                }
            }
            nextOut = mapped["continuation"] as? String
            if (accumulated.isNotEmpty()) {
                break
            }
            if (nextOut.isNullOrBlank()) {
                break
            }
            // Stuck continuation with nothing new — stop.
            if (nextOut == previousToken) {
                nextOut = null
                break
            }
            token = nextOut
        }

        Log.i(
            TAG,
            "collectNonEmpty pages=$pages unique=${accumulated.size} hasMore=${!nextOut.isNullOrBlank()}",
        )
        return mapOf(
            "items" to accumulated,
            "continuation" to nextOut,
        )
    }

    private fun pageToMap(
        page: ListExtractor.InfoItemsPage<out InfoItem>,
        shortsOnly: Boolean,
    ): Map<String, Any?> {
        val list = ArrayList<Map<String, Any?>>()
        val seenIds = LinkedHashSet<String>()
        for (item in page.items) {
            if (item !is StreamInfoItem) {
                continue
            }
            val duration = item.duration
            // Unknown duration (<= 0) is common for Shorts search — keep it.
            // Only drop clearly long videos when building a Shorts feed.
            if (shortsOnly && duration > 60) {
                continue
            }
            val id = videoIdFromUrl(item.url) ?: continue
            if (!seenIds.add(id)) {
                continue
            }
            val isShort = duration in 1..60 || shortsOnly
            val thumb = try {
                item.thumbnails.firstOrNull()?.url
            } catch (_: Exception) {
                null
            }
            val row = HashMap<String, Any?>()
            row["id"] = id
            row["title"] = item.name ?: id
            row["url"] = item.url
            row["thumbnail"] = thumb
            row["uploader"] = item.uploaderName
            if (duration > 0) {
                row["duration"] = duration
            }
            row["channelUrl"] = item.uploaderUrl
            row["isShort"] = isShort
            list.add(row)
        }
        val next = page.nextPage
        val continuation =
            if (next != null && Page.isValid(next)) encodePage(next) else null
        Log.i(TAG, "page items=${list.size} hasMore=${continuation != null}")
        return mapOf(
            "items" to list,
            "continuation" to continuation,
        )
    }

    private fun videoIdFromUrl(url: String?): String? {
        if (url.isNullOrBlank()) {
            return null
        }
        val patterns = listOf(
            Regex("""[?&]v=([A-Za-z0-9_-]{11})"""),
            Regex("""/shorts/([A-Za-z0-9_-]{11})"""),
            Regex("""youtu\.be/([A-Za-z0-9_-]{11})"""),
        )
        for (p in patterns) {
            val m = p.find(url)
            if (m != null) {
                return m.groupValues[1]
            }
        }
        return null
    }

    private fun encodePage(page: Page): String {
        val json = JSONObject()
        if (!page.url.isNullOrEmpty()) {
            json.put("url", page.url)
        }
        if (!page.id.isNullOrEmpty()) {
            json.put("id", page.id)
        }
        page.body?.let { json.put("body", String(it, Charsets.UTF_8)) }
        val ids = page.ids
        if (!ids.isNullOrEmpty()) {
            val arr = JSONArray()
            ids.forEach { arr.put(it) }
            json.put("ids", arr)
        }
        return Base64.encodeToString(
            json.toString().toByteArray(Charsets.UTF_8),
            Base64.NO_WRAP,
        )
    }

    private fun decodePage(token: String): Page {
        val raw = String(Base64.decode(token, Base64.NO_WRAP), Charsets.UTF_8)
        val json = JSONObject(raw)
        val url = if (json.has("url")) json.getString("url") else null
        val id = if (json.has("id")) json.getString("id") else null
        val body = if (json.has("body")) {
            json.getString("body").toByteArray(Charsets.UTF_8)
        } else {
            null
        }
        val ids = ArrayList<String>()
        val arr = json.optJSONArray("ids")
        if (arr != null) {
            for (i in 0 until arr.length()) {
                ids.add(arr.getString(i))
            }
        }
        return Page(
            url,
            id,
            if (ids.isEmpty()) null else ids,
            null,
            body,
        )
    }
}
