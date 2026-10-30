package local.sitelink.toggle.android

import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import local.sitelink.core.LinkController
import local.sitelink.core.LinkState

/** Riquadro nelle Impostazioni rapide (tendina): mostra lo stato e accende/spegne con un tocco. */
class LinkTileService : TileService() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    override fun onStartListening() { scope.launch { update(null) } }

    override fun onClick() {
        val s = Store(this).load() ?: return
        scope.launch {
            update("In corso…", Tile.STATE_UNAVAILABLE)
            val result = runCatching { LinkController.set(LinkController.snapshot(s).state != LinkState.ON, s) }
            update(result.exceptionOrNull()?.message?.take(40))
        }
    }

    override fun onDestroy() { scope.cancel(); super.onDestroy() }

    private suspend fun update(text: String?, force: Int? = null) {
        val tile = qsTile ?: return
        val s = Store(this).load()
        if (s == null) {
            tile.state = Tile.STATE_UNAVAILABLE; tile.label = "SiteLink"; setSubtitle(tile, "Configura l'app")
            tile.updateTile(); return
        }
        val state = if (force == null) runCatching { LinkController.snapshot(s).state }.getOrDefault(LinkState.UNKNOWN) else LinkState.UNKNOWN
        tile.label = "SiteLink"
        tile.state = force ?: if (state == LinkState.ON) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        setSubtitle(tile, text ?: when (state) {
            LinkState.ON -> "Connesso"; LinkState.OFF -> "Disconnesso"; LinkState.PARTIAL -> "Parziale"; LinkState.UNKNOWN -> "Sconosciuto"
        })
        tile.updateTile()
    }

    private fun setSubtitle(tile: Tile, text: String) { if (Build.VERSION.SDK_INT >= 29) tile.subtitle = text }
}
