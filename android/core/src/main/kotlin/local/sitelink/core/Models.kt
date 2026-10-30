package local.sitelink.core

import org.json.JSONArray
import org.json.JSONObject

/** Una sede. Il token sta nello spazio cifrato del telefono, non nel JSON delle impostazioni. */
data class SiteEntry(
    val id: String,
    val name: String,
    /** Indirizzo dell'agent (IP o nome, anche "host:porta"), per esempio quello nella LAN della sede. */
    val host: String,
    /** Indirizzo alternativo facoltativo, per esempio l'IP Tailscale del router. */
    val altHost: String = "",
    val token: String = "",
) {
    val hosts: List<String> get() = listOf(host, altHost).map { it.trim() }.filter { it.isNotEmpty() }
}

data class AppSettings(val sites: List<SiteEntry>, val port: Int = 8765)

/** Impostazioni <-> JSON (senza token) e importazione del config.json dell'app Mac/Windows. */
object SettingsCodec {
    fun toJson(s: AppSettings): String = JSONObject().apply {
        put("port", s.port)
        put("sites", JSONArray(s.sites.map {
            JSONObject().put("id", it.id).put("name", it.name).put("host", it.host).put("altHost", it.altHost)
        }))
    }.toString()

    fun fromJson(json: String, token: (String) -> String?): AppSettings? = try {
        val o = JSONObject(json)
        val arr = o.getJSONArray("sites")
        val sites = (0 until arr.length()).map {
            val x = arr.getJSONObject(it)
            val id = x.getString("id")
            SiteEntry(id, x.getString("name"), x.getString("host"), x.optString("altHost", ""), token(id) ?: "")
        }
        if (sites.size == 2 && sites.all { it.token.isNotEmpty() }) AppSettings(sites, o.optInt("port", 8765)) else null
    } catch (e: Exception) { null }

    data class Imported(val name: String, val host: String, val token: String)

    /** Legge nome, agent_url e token di ciascuna sede dal config.json del Mac; restituisce anche la porta. */
    fun importMacConfig(json: String): Pair<List<Imported>, Int?> {
        val arr = JSONObject(json).getJSONArray("sites")
        if (arr.length() != 2) throw AgentError("Il file deve contenere esattamente 2 sedi", isFinal = true)
        var port: Int? = null
        val list = (0 until arr.length()).map {
            val x = arr.getJSONObject(it)
            val uri = java.net.URI(x.getString("agent_url"))
            if (it == 0 && uri.port > 0) port = uri.port
            Imported(x.getString("name"), uri.host ?: "", x.getString("token"))
        }
        return list to port
    }
}
