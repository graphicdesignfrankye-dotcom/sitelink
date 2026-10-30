package local.sitelink.core

data class SiteForm(val name: String = "", val host: String = "", val altHost: String = "", val token: String = "")

/** Dati inseriti nella configurazione guidata, con la stessa validazione delle altre app. */
data class SetupDraft(val a: SiteForm = SiteForm(), val b: SiteForm = SiteForm(), val port: String = "8765") {

    val isPristine: Boolean get() = a.name.isEmpty() && b.name.isEmpty() && a.token.isEmpty() && b.token.isEmpty()

    /** Indirizzo valido: host oppure host:porta. */
    private fun hostOk(h: String): Boolean {
        val t = h.trim()
        val parts = t.split(":")
        if (parts.size > 2 || parts[0].isEmpty()) return false
        if (parts.size == 2 && (parts[1].toIntOrNull()?.let { it in 1..65535 } != true)) return false
        return parts[0].none { it == ' ' || it == '/' || it == '@' }
    }

    private fun errors(f: SiteForm, label: String): List<String> = buildList {
        if (f.name.isBlank()) add("$label: manca il nome")
        if (!hostOk(f.host)) add("$label: indirizzo dell'agent non valido (esempio 10.0.1.31)")
        if (f.altHost.isNotBlank() && !hostOk(f.altHost)) add("$label: indirizzo alternativo non valido")
        if (f.token.trim().length < 24) add("$label: token troppo corto (almeno 24 caratteri)")
    }

    val allErrors: List<String>
        get() = buildList {
            addAll(errors(a, "Sede 1")); addAll(errors(b, "Sede 2"))
            if (port.toIntOrNull()?.let { it in 1..65535 } != true) add("Porta non valida")
            if (a.name.isNotBlank() && a.name.trim().equals(b.name.trim(), ignoreCase = true)) add("Le due sedi devono avere nomi diversi")
        }

    fun toSettings(): AppSettings {
        fun site(f: SiteForm): SiteEntry {
            val name = f.name.trim()
            val slug = name.lowercase().filter { it.isLetterOrDigit() }
            return SiteEntry(slug.ifEmpty { "sede" }, name, f.host.trim(), f.altHost.trim(), f.token.trim())
        }
        val s = listOf(site(a), site(b)).toMutableList()
        if (s[0].id == s[1].id) s[1] = s[1].copy(id = s[1].id + "2")
        return AppSettings(s, port.toIntOrNull() ?: 8765)
    }

    companion object {
        fun from(s: AppSettings?): SetupDraft {
            if (s == null || s.sites.size != 2) return SetupDraft()
            fun f(x: SiteEntry) = SiteForm(x.name, x.host, x.altHost, x.token)
            return SetupDraft(f(s.sites[0]), f(s.sites[1]), s.port.toString())
        }
    }
}
