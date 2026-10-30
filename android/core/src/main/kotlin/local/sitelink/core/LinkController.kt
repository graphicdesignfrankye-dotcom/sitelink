package local.sitelink.core

import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import java.util.concurrent.ConcurrentHashMap

enum class LinkState { ON, OFF, PARTIAL, UNKNOWN }

data class SiteState(
    val site: SiteEntry,
    val status: AgentStatus? = null,
    /** true: lo stato arriva tramite l'agent dell'altra sede (la sede non è raggiungibile direttamente). */
    val viaPeer: Boolean = false,
    val error: String? = null,
    /** true: l'agent ha risposto con un errore (per esempio token errato): il peer non cambierebbe nulla. */
    val errorIsFinal: Boolean = false,
)

data class Snapshot(val states: List<SiteState>, val message: String? = null) {
    val state: LinkState
        get() {
            val s = states.mapNotNull { it.status?.linkEnabled }
            if (s.size != states.size || s.isEmpty()) return LinkState.UNKNOWN
            return when {
                s.all { it } -> LinkState.ON
                s.none { it } -> LinkState.OFF
                else -> LinkState.PARTIAL
            }
        }

    /** Basta raggiungere un agent direttamente: l'altro si comanda tramite il peer. */
    val canControl: Boolean get() = states.any { it.status != null && !it.viaPeer }
}

/** Logica del collegamento, senza interfaccia: la usano sia l'app sia il riquadro nelle Impostazioni rapide. */
object LinkController {
    private val goodHost = ConcurrentHashMap<String, String>()

    /** Prova gli indirizzi della sede (prima l'ultimo che ha funzionato). */
    suspend fun call(
        site: SiteEntry, s: AppSettings, path: String, post: Boolean = false,
        viaPeer: Boolean = false, timeoutMs: Int = 4000,
    ): AgentStatus {
        val hosts = site.hosts.toMutableList()
        goodHost[site.id]?.let { g -> if (hosts.remove(g)) hosts.add(0, g) }
        var last: Throwable = AgentError("Agent ${site.name}: indirizzo mancante", true)
        for (h in hosts) {
            try {
                val r = AgentClient(h, s.port, site.token, site.name).call(path, post, viaPeer, timeoutMs)
                goodHost[site.id] = h
                return r
            } catch (e: AgentError) {
                if (e.isFinal) throw e
                last = e
            }
        }
        throw last
    }

    suspend fun snapshot(s: AppSettings): Snapshot = coroutineScope {
        val ra = async { runCatching { call(s.sites[0], s, "status") } }
        val rb = async { runCatching { call(s.sites[1], s, "status") } }
        fun fill(x: SiteState, r: Result<AgentStatus>): SiteState = r.fold(
            { x.copy(status = it) },
            { x.copy(error = it.message, errorIsFinal = (it as? AgentError)?.isFinal ?: false) },
        )
        var a = fill(SiteState(s.sites[0]), ra.await())
        var b = fill(SiteState(s.sites[1]), rb.await())
        // Una sede fuori portata si legge tramite l'agent dell'altra (canale tra i router).
        if (a.status == null && !a.errorIsFinal && b.status != null) {
            runCatching { call(s.sites[1], s, "status", viaPeer = true, timeoutMs = 12000) }
                .onSuccess { a = a.copy(status = it, viaPeer = true, error = null) }
        }
        if (b.status == null && !b.errorIsFinal && a.status != null && !a.viaPeer) {
            runCatching { call(s.sites[0], s, "status", viaPeer = true, timeoutMs = 12000) }
                .onSuccess { b = b.copy(status = it, viaPeer = true, error = null) }
        }
        val msg = when {
            a.status == null && b.status == null ->
                "Nessun agent raggiungibile: sei in una delle due reti o collegato con Tailscale?"
            else -> a.error ?: b.error
        }
        Snapshot(listOf(a, b), msg)
    }

    /**
     * Accende o spegne il collegamento. Ordine come sulle altre app: acceso = agent raggiunto, poi l'altro;
     * spento = prima l'altro, poi quello raggiunto (finché il canale tra i router c'è).
     */
    suspend fun set(on: Boolean, s: AppSettings): Snapshot {
        val before = snapshot(s)
        val entryIdx = before.states.indexOfFirst { it.status != null && !it.viaPeer }
        if (entryIdx < 0) throw AgentError(before.message ?: "Nessun agent raggiungibile")
        val entry = before.states[entryIdx].site
        val other = before.states[1 - entryIdx]
        val verb = if (on) "enable" else "disable"

        suspend fun setOther(): String? = try {
            if (other.status != null && !other.viaPeer) call(other.site, s, verb, post = true)
            else call(entry, s, verb, post = true, viaPeer = true, timeoutMs = 12000)
            null
        } catch (e: AgentError) { "Altra sede: ${e.message}" }

        val problem: String?
        if (on) {
            call(entry, s, verb, post = true)
            problem = setOther()
        } else {
            problem = setOther()
            call(entry, s, verb, post = true)
        }
        val after = snapshot(s)
        return if (problem != null) after.copy(message = problem) else after
    }
}
