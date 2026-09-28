package com.ytdownloader.app

import org.json.JSONArray
import org.json.JSONObject
import java.nio.charset.StandardCharsets
import java.util.Base64

/**
 * Parsed WAA Create challenge: BotGuard VM source plus bytecode program.
 *
 * [interpreterJavascript] is inline VM source. When empty, [interpreterUrl]
 * is a trusted-resource URL the client must fetch.
 */
data class BotGuardChallenge(
    val interpreterJavascript: String,
    val program: String,
    val globalName: String,
    val interpreterUrl: String = "",
)

/**
 * Parses YouTube WAA Create json+protobuf the same way BgUtils does:
 * scrambled string at index 1 (base64url, each byte + 97) or a nested JSPB
 * array `[messageId, wrappedScript, wrappedUrl, hash, program, globalName]`.
 */
object BotGuardChallengeParser {
    fun parse(raw: String): BotGuardChallenge {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) {
            throw IllegalStateException("Unrecognised Create payload: empty")
        }
        val parsed = try {
            when {
                trimmed.startsWith("[") -> parseRootArray(JSONArray(trimmed))
                trimmed.startsWith("{") -> fromNamedObject(JSONObject(trimmed))
                else -> throw IllegalStateException(unrecognised(trimmed))
            }
        } catch (e: IllegalStateException) {
            throw e
        } catch (e: Exception) {
            throw IllegalStateException(unrecognised(trimmed), e)
        }
        if (parsed.program.isBlank() || parsed.globalName.isBlank()) {
            throw IllegalStateException("Create missing fields program/globalName")
        }
        if (parsed.interpreterJavascript.isBlank() && parsed.interpreterUrl.isBlank()) {
            throw IllegalStateException("Create missing interpreter JS/URL")
        }
        return parsed
    }

    fun descramble(scrambled: String): String? {
        val decoded = decodeBase64(scrambled) ?: return null
        if (decoded.isEmpty()) {
            return null
        }
        val shifted = ByteArray(decoded.size) { i -> (decoded[i] + 97).toByte() }
        return String(shifted, StandardCharsets.UTF_8)
    }

    /** Test helper: reverse of [descramble] using URL-safe Base64 without padding. */
    fun scramble(plain: String): String {
        val bytes = plain.toByteArray(StandardCharsets.UTF_8)
        val shifted = ByteArray(bytes.size) { i -> (bytes[i] - 97).toByte() }
        return Base64.getUrlEncoder().withoutPadding().encodeToString(shifted)
    }

    internal fun unrecognised(raw: String): String {
        val preview = raw.replace('\n', ' ').take(200)
        return "Unrecognised Create payload: $preview"
    }

    private fun parseRootArray(root: JSONArray): BotGuardChallenge {
        if (root.length() > 1 && root.opt(1) is String) {
            val scrambled = root.optString(1)
            if (scrambled.length > 8) {
                val descrambled = descramble(scrambled)
                    ?: throw IllegalStateException("Create descramble failed")
                return parseDescrambled(descrambled)
            }
        }
        if (root.length() > 0) {
            when (val first = root.opt(0)) {
                is JSONObject -> return fromNamedObject(first)
                is JSONArray -> return fromJspb(first)
            }
        }
        val asJspb = fromJspb(root)
        if (asJspb.program.isNotBlank() && asJspb.globalName.isNotBlank()) {
            return asJspb
        }
        throw IllegalStateException(unrecognised(root.toString()))
    }

    private fun parseDescrambled(descrambled: String): BotGuardChallenge {
        val trimmed = descrambled.trim()
        if (trimmed.startsWith("{")) {
            return fromNamedObject(JSONObject(trimmed))
        }
        if (trimmed.startsWith("[")) {
            val arr = JSONArray(trimmed)
            if (arr.length() > 0 && arr.opt(0) is JSONObject) {
                return fromNamedObject(arr.getJSONObject(0))
            }
            return fromJspb(arr)
        }
        throw IllegalStateException(unrecognised(trimmed))
    }

    private fun fromJspb(arr: JSONArray): BotGuardChallenge {
        val js = firstString(arr.opt(1)).orEmpty()
        val url = firstString(arr.opt(2)).orEmpty()
        return splitScriptAndUrl(
            js = js,
            url = url,
            program = arr.optString(4),
            globalName = arr.optString(5),
        )
    }

    private fun fromNamedObject(obj: JSONObject): BotGuardChallenge {
        val interp = obj.optJSONObject("interpreterJavascript")
        val namedJs = interp?.optString("privateDoNotAccessOrElseSafeScriptWrappedValue")
            ?.takeIf { it.isNotBlank() }
            ?: obj.optString("interpreterJavascript").takeIf { it.isNotBlank() }
            ?: ""
        val urlFromInterp = interp
            ?.optString("privateDoNotAccessOrElseTrustedResourceUrlWrappedValue")
            ?.takeIf { it.isNotBlank() }
            .orEmpty()
        val urlObj = obj.optJSONObject("interpreterUrl")
        val namedUrl = urlObj
            ?.optString("privateDoNotAccessOrElseTrustedResourceUrlWrappedValue")
            ?.takeIf { it.isNotBlank() }
            ?: obj.optString("interpreterUrl").takeIf { it.isNotBlank() }
            ?: urlFromInterp
        return splitScriptAndUrl(
            js = namedJs,
            url = namedUrl,
            program = obj.optString("program"),
            globalName = obj.optString("globalName"),
        )
    }

    /**
     * Trusted-resource URLs are short, single-line, and have a hostname.
     * BotGuard VM source often starts with `//# sourceMappingURL=...` — that is
     * a JS comment, not a protocol-relative URL.
     */
    fun isInterpreterUrl(value: String): Boolean {
        val trimmed = value.trim()
        if (trimmed.isEmpty() ||
            trimmed.length > 2048 ||
            trimmed.contains('\n') ||
            trimmed.contains('\r')
        ) {
            return false
        }
        if (trimmed.startsWith("//#") ||
            trimmed.startsWith("// ") ||
            trimmed.startsWith("/*")
        ) {
            return false
        }
        return HOST_URL.matches(trimmed)
    }

    private fun splitScriptAndUrl(
        js: String,
        url: String,
        program: String,
        globalName: String,
    ): BotGuardChallenge {
        val jsIsUrl = isInterpreterUrl(js)
        val urlIsUrl = isInterpreterUrl(url)
        return if (jsIsUrl && !urlIsUrl) {
            BotGuardChallenge(
                interpreterJavascript = "",
                program = program,
                globalName = globalName,
                interpreterUrl = js.trim(),
            )
        } else {
            BotGuardChallenge(
                interpreterJavascript = js,
                program = program,
                globalName = globalName,
                interpreterUrl = if (urlIsUrl) url.trim() else "",
            )
        }
    }

    private fun firstString(value: Any?): String? {
        when (value) {
            is String -> if (value.isNotBlank() && value != "null") {
                return value
            }
            is JSONArray -> {
                for (i in 0 until value.length()) {
                    firstString(value.opt(i))?.let { return it }
                }
            }
            is JSONObject -> {
                val named = value.optString("privateDoNotAccessOrElseSafeScriptWrappedValue")
                    .takeIf { it.isNotBlank() }
                    ?: value.optString("privateDoNotAccessOrElseTrustedResourceUrlWrappedValue")
                        .takeIf { it.isNotBlank() }
                if (named != null) {
                    return named
                }
                val keys = value.keys()
                while (keys.hasNext()) {
                    firstString(value.opt(keys.next()))?.let { return it }
                }
            }
        }
        return null
    }

    private fun decodeBase64(value: String): ByteArray? {
        val cleaned = value.trim()
        val urlAttempt = runCatching {
            Base64.getUrlDecoder().decode(cleaned)
        }.getOrNull()
        if (urlAttempt != null) {
            return urlAttempt
        }
        return runCatching {
            Base64.getDecoder().decode(cleaned)
        }.getOrNull()
    }

    private val HOST_URL = Regex(
        "^(https?:)?//[A-Za-z0-9][A-Za-z0-9.-]*(:[0-9]+)?(/\\S*)?$",
    )
}
