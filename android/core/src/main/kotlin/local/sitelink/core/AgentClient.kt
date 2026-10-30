package local.sitelink.core

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.ConnectException
import java.net.HttpURLConnection
import java.net.SocketTimeoutException
import java.net.URL

/** [isFinal] = true: l'agent ha risposto (token errato, errore interno): provare un altro indirizzo non serve. */
class AgentError(message: String, val isFinal: Boolean = false) : Exception(message)

data class AgentStatus(val site: String, val linkEnabled: Boolean, val vpnUp: Boolean)

object AgentParser {
    fun parse(json: String): AgentStatus {
        val o = JSONObject(json)
        // API v2: "vpn". Gli agent v1 (solo Tailscale) usano ancora "tailscale".
        val vpn = o.optJSONObject("vpn") ?: o.optJSONObject("tailscale")
        return AgentStatus(o.optString("site", ""), o.optBoolean("link_enabled", false), vpn?.optBoolean("up", false) ?: false)
    }
}

/** Chiamata HTTP a un singolo indirizzo di un agent (stessa API usata dalle app Mac, Windows e iPhone). */
class AgentClient(private val host: String, private val port: Int, private val token: String, private val siteName: String) {

    suspend fun call(path: String, post: Boolean = false, viaPeer: Boolean = false, timeoutMs: Int = 4000): AgentStatus =
        withContext(Dispatchers.IO) { blockingCall(path, post, viaPeer, timeoutMs) }

    private fun fail(m: String, viaPeer: Boolean, final: Boolean = false) =
        AgentError(if (viaPeer) m else "Agent $siteName: $m", final)

    private fun blockingCall(path: String, post: Boolean, viaPeer: Boolean, timeoutMs: Int): AgentStatus {
        // "host" può già contenere la porta ("10.0.2.2:9000"); altrimenti vale quella comune.
        val authority = if (host.contains(":")) host else "$host:$port"
        val url = try { URL("http://$authority${if (viaPeer) "/peer/" else "/"}$path") }
        catch (e: Exception) { throw AgentError("Indirizzo non valido ($siteName)", true) }
        val conn = url.openConnection() as HttpURLConnection
        try {
            conn.connectTimeout = timeoutMs
            conn.readTimeout = timeoutMs
            conn.requestMethod = if (post) "POST" else "GET"
            conn.setRequestProperty("Authorization", "Bearer $token")
            if (post) { conn.doOutput = true; conn.setFixedLengthStreamingMode(0) }
            val code = try { conn.responseCode }
            catch (e: SocketTimeoutException) { throw fail("nessuna risposta (timeout)", viaPeer) }
            catch (e: ConnectException) { throw fail("non raggiungibile", viaPeer) }
            catch (e: java.io.IOException) { throw fail("non raggiungibile", viaPeer) }
            val body = (if (code == 200) conn.inputStream else conn.errorStream)?.bufferedReader()?.use { it.readText() } ?: ""
            if (code != 200) {
                var msg = if (code == 401) "token non valido" else "errore HTTP $code"
                if (code != 401) runCatching { JSONObject(body).optString("error").takeIf { it.isNotEmpty() } }.getOrNull()?.let { msg = it }
                throw fail(msg, viaPeer, final = true)
            }
            return try { AgentParser.parse(body) } catch (e: Exception) { throw fail("risposta non valida", viaPeer, final = true) }
        } finally {
            conn.disconnect()
        }
    }
}
