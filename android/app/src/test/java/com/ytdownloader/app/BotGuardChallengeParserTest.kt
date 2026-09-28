package com.ytdownloader.app

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BotGuardChallengeParserTest {
    @Test
    fun parseScrambledJspbArray() {
        val jspb = JSONArray()
            .put("msg-id")
            .put(JSONArray().put("var bg = {a:function(){}};"))
            .put(JSONArray().put(JSONObject.NULL).put("//www.google.com/js/bg/test.js"))
            .put("hash123")
            .put("PROGRAM_BYTES")
            .put("enforcementV3")
            .put(JSONObject.NULL)
            .put("blob")
        val envelope = JSONArray()
            .put(JSONObject.NULL)
            .put(BotGuardChallengeParser.scramble(jspb.toString()))

        val parsed = BotGuardChallengeParser.parse(envelope.toString())

        assertEquals("PROGRAM_BYTES", parsed.program)
        assertEquals("enforcementV3", parsed.globalName)
        assertEquals("var bg = {a:function(){}};", parsed.interpreterJavascript)
        assertEquals("//www.google.com/js/bg/test.js", parsed.interpreterUrl)
    }

    @Test
    fun parseNamedObjectEnvelope() {
        val interp = JSONObject()
            .put(
                "privateDoNotAccessOrElseSafeScriptWrappedValue",
                "var x=1;",
            )
        val named = JSONObject()
            .put("program", "PROG")
            .put("globalName", "bg")
            .put("interpreterJavascript", interp)
        val envelope = JSONArray().put(named)

        val parsed = BotGuardChallengeParser.parse(envelope.toString())

        assertEquals("PROG", parsed.program)
        assertEquals("bg", parsed.globalName)
        assertEquals("var x=1;", parsed.interpreterJavascript)
    }

    @Test
    fun parseNestedJspbWithoutScramble() {
        val jspb = JSONArray()
            .put("msg-id")
            .put(JSONArray().put(JSONArray().put("inlineVM();")))
            .put(JSONObject.NULL)
            .put("hash")
            .put("NESTED_PROGRAM")
            .put("enforcementV3")
        val envelope = JSONArray().put(jspb)

        val parsed = BotGuardChallengeParser.parse(envelope.toString())

        assertEquals("NESTED_PROGRAM", parsed.program)
        assertEquals("enforcementV3", parsed.globalName)
        assertEquals("inlineVM();", parsed.interpreterJavascript)
    }

    @Test
    fun parseUrlOnlyInterpreter() {
        val jspb = JSONArray()
            .put("msg-id")
            .put(JSONObject.NULL)
            .put(JSONArray().put("//youtube.com/s/player/bg.js"))
            .put("hash")
            .put("URL_PROGRAM")
            .put("bg")
        val envelope = JSONArray()
            .put(JSONObject.NULL)
            .put(BotGuardChallengeParser.scramble(jspb.toString()))

        val parsed = BotGuardChallengeParser.parse(envelope.toString())

        assertEquals("URL_PROGRAM", parsed.program)
        assertEquals("bg", parsed.globalName)
        assertEquals("", parsed.interpreterJavascript)
        assertEquals("//youtube.com/s/player/bg.js", parsed.interpreterUrl)
    }

    @Test
    fun sourceMappingCommentIsJavascriptNotUrl() {
        val vm = """
            //# sourceMappingURL=data:application/json;charset=utf-8;base64,eyJ2ZXJzaW9uIjogM30=
            (function(){var p=221;})();
        """.trimIndent()
        val jspb = JSONArray()
            .put("msg-id")
            .put(JSONArray().put(vm))
            .put(JSONObject.NULL)
            .put("hash")
            .put("PROGRAM_BYTES")
            .put("enforcementV3")
        val envelope = JSONArray()
            .put(JSONObject.NULL)
            .put(BotGuardChallengeParser.scramble(jspb.toString()))

        val parsed = BotGuardChallengeParser.parse(envelope.toString())

        assertEquals("PROGRAM_BYTES", parsed.program)
        assertEquals("enforcementV3", parsed.globalName)
        assertEquals("", parsed.interpreterUrl)
        assertTrue(parsed.interpreterJavascript.contains("(function(){var p=221;})();"))
        assertTrue(parsed.interpreterJavascript.startsWith("//# sourceMappingURL="))
    }

    @Test
    fun interpreterUrlRequiresHostname() {
        assertTrue(
            BotGuardChallengeParser.isInterpreterUrl("//www.google.com/js/bg/test.js"),
        )
        assertTrue(
            BotGuardChallengeParser.isInterpreterUrl("https://www.gstatic.com/bg.js"),
        )
        assertFalse(
            BotGuardChallengeParser.isInterpreterUrl(
                "//# sourceMappingURL=data:application/json;charset=utf-8;base64,e30=",
            ),
        )
        assertFalse(
            BotGuardChallengeParser.isInterpreterUrl(
                "//# sourceMappingURL=x\n(function(){})();",
            ),
        )
    }

    @Test
    fun descrambleRoundTrip() {
        val plain = """["id",["js"],["//u"],"h","P","g"]"""
        val scrambled = BotGuardChallengeParser.scramble(plain)
        assertEquals(plain, BotGuardChallengeParser.descramble(scrambled))
    }

    @Test
    fun unrecognisedPayloadMentionsPreview() {
        try {
            BotGuardChallengeParser.parse("not-json")
            throw AssertionError("expected failure")
        } catch (e: IllegalStateException) {
            assertTrue(e.message!!.startsWith("Unrecognised Create payload"))
            assertTrue(e.message!!.contains("not-json"))
        }
    }
}
