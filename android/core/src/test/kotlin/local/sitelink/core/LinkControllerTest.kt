package local.sitelink.core

import kotlinx.coroutines.runBlocking
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Prove contro due agent veri in locale: si lanciano con tests/run_logic_test.sh (imposta TA e TB e le porte). */
class LinkControllerTest {
    private val ta = System.getenv("TA") ?: error("Usa tests/run_logic_test.sh")
    private val tb = System.getenv("TB") ?: error("Usa tests/run_logic_test.sh")

    private fun settings(aHost: String = "127.0.0.1:18771", bHost: String = "127.0.0.1:18772", bAlt: String = "", bToken: String = tb) =
        AppSettings(listOf(SiteEntry("a", "Ufficio", aHost, token = ta), SiteEntry("b", "Casa", bHost, bAlt, bToken)))

    @Test
    fun comandoConEntrambiGliAgent() = runBlocking<Unit> {
        val s = settings()
        var snap = LinkController.snapshot(s)
        assertEquals(LinkState.OFF, snap.state); assertTrue(snap.canControl); assertNull(snap.message)
        snap = LinkController.set(true, s)
        assertEquals(LinkState.ON, snap.state)
        assertTrue(snap.states.all { it.status?.linkEnabled == true && !it.viaPeer })
        assertEquals(LinkState.OFF, LinkController.set(false, s).state)
    }

    @Test
    fun sedeFuoriPortataTramitePeer() = runBlocking<Unit> {
        val s = settings(bHost = "127.0.0.1:19999")
        var snap = LinkController.snapshot(s)
        assertTrue(snap.states[1].viaPeer); assertNotNull(snap.states[1].status); assertTrue(snap.canControl)
        snap = LinkController.set(true, s)
        assertEquals(LinkState.ON, snap.state); assertTrue(snap.states[1].viaPeer)
        assertEquals(LinkState.OFF, LinkController.set(false, s).state)
    }

    @Test
    fun indirizzoAlternativo() = runBlocking<Unit> {
        val snap = LinkController.snapshot(settings(bHost = "127.0.0.1:19999", bAlt = "127.0.0.1:18772"))
        assertNotNull(snap.states[1].status); assertFalse(snap.states[1].viaPeer)
    }

    @Test
    fun tokenErratoSegnalato() = runBlocking<Unit> {
        val snap = LinkController.snapshot(settings(bToken = "z".repeat(32)))
        assertNull(snap.states[1].status)
        assertTrue((snap.message ?: "").contains("token non valido"))
    }

    @Test
    fun nessunAgent() = runBlocking<Unit> {
        val s = settings(aHost = "127.0.0.1:19998", bHost = "127.0.0.1:19999")
        val snap = LinkController.snapshot(s)
        assertEquals(LinkState.UNKNOWN, snap.state); assertFalse(snap.canControl)
        assertFailsWith<AgentError> { LinkController.set(true, s) }
    }

    @Test
    fun parsingEImportazione() {
        assertTrue(AgentParser.parse("""{"site":"u","link_enabled":true,"tailscale":{"up":true}}""").vpnUp)
        val json = """{"sites":[{"name":"A","agent_url":"http://10.0.1.31:9000","token":"x"},{"name":"B","agent_url":"http://10.0.2.2:9000","token":"y"}]}"""
        val (list, port) = SettingsCodec.importMacConfig(json)
        assertEquals("10.0.1.31", list[0].host); assertEquals(9000, port); assertEquals("y", list[1].token)
        val s = AppSettings(listOf(SiteEntry("a", "A", "h1", "alt", "t1"), SiteEntry("b", "B", "h2", token = "t2")), 8765)
        val back = SettingsCodec.fromJson(SettingsCodec.toJson(s)) { id -> mapOf("a" to "t1", "b" to "t2")[id] }
        assertEquals(s, back)
        assertFalse(SettingsCodec.toJson(s).contains("t1"))
    }

    @Test
    fun validazioneWizard() {
        val ok = SiteForm("Ufficio", "10.0.1.31", "", "t".repeat(32))
        assertTrue(SetupDraft(ok, ok.copy(name = "Casa", host = "10.0.2.2:9000")).allErrors.isEmpty())
        assertTrue(SetupDraft(ok, ok).allErrors.any { it.contains("nomi diversi") })
        assertTrue(SetupDraft(ok.copy(host = "10.0.1.31/x"), ok.copy(name = "Casa")).allErrors.any { it.contains("indirizzo") })
        assertTrue(SetupDraft(ok.copy(token = "corto"), ok.copy(name = "Casa")).allErrors.any { it.contains("token") })
        assertEquals("ufficio", SetupDraft(ok, ok.copy(name = "Casa")).toSettings().sites[0].id)
    }
}
