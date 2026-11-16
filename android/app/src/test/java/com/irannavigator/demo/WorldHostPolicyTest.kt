package com.irannavigator.demo

import org.junit.Assert.*
import org.junit.Test

class WorldHostPolicyTest {
    @Test fun bridgeIsRestrictedToBundledHttpsOrigin() {
        assertTrue(WorldHostPolicy.isTrustedUrl(WorldHostPolicy.ENTRY))
        assertTrue(WorldHostPolicy.isTrustedUrl("${WorldHostPolicy.ORIGIN}:443/assets/world/index.html?test=1"))
        listOf(null, "", "http://appassets.androidplatform.net/assets/world/index.html",
            "https://example.com/assets/world/index.html",
            "https://appassets.androidplatform.net.evil.test/assets/world/index.html",
            "https://user@appassets.androidplatform.net/assets/world/index.html",
            "https://appassets.androidplatform.net:444/assets/world/index.html",
            "${WorldHostPolicy.ORIGIN}/assets/other/index.html",
            "${WorldHostPolicy.ORIGIN}/assets/world/../secret",
            "${WorldHostPolicy.ORIGIN}/assets/world/%2e%2e/secret",
            "file:///android_asset/world/index.html", "javascript:alert(1)")
            .forEach { assertFalse("Must reject $it", WorldHostPolicy.isTrustedUrl(it)) }
    }

    @Test fun callbacksCannotInjectJavascript() {
        assertEquals(1, WorldHostPolicy.callbackId("1"))
        listOf("0", "-1", "1000000001", "1);alert(1)//", "NaN", "1.5")
            .forEach { assertNull(WorldHostPolicy.callbackId(it)) }
    }

    @Test fun locationMustBeFreshAccurateAndFinite() {
        val now = 100_000L
        assertTrue(WorldHostPolicy.isFreshAccurateLocation(35.7, 51.4, 8f, now, now))
        assertTrue(WorldHostPolicy.isFreshAccurateLocation(35.7, 51.4, 65f, now - 15000, now))
        assertFalse(WorldHostPolicy.isFreshAccurateLocation(35.7, 51.4, 8f, now - 15001, now))
        assertFalse(WorldHostPolicy.isFreshAccurateLocation(35.7, 51.4, 8f, now + 1, now))
        assertFalse(WorldHostPolicy.isFreshAccurateLocation(35.7, 51.4, 66f, now, now))
        assertFalse(WorldHostPolicy.isFreshAccurateLocation(35.7, 51.4, -1f, now, now))
        assertFalse(WorldHostPolicy.isFreshAccurateLocation(Double.NaN, 51.4, 8f, now, now))
        assertFalse(WorldHostPolicy.isFreshAccurateLocation(91.0, 181.0, 8f, now, now))
    }
}
