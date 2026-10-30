package local.sitelink.toggle.android

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import local.sitelink.core.AgentError
import local.sitelink.core.AppSettings
import local.sitelink.core.LinkController
import local.sitelink.core.LinkState
import local.sitelink.core.Snapshot

class LinkViewModel(app: Application) : AndroidViewModel(app) {
    val store = Store(app)
    val settings = MutableStateFlow(store.load())
    val snapshot = MutableStateFlow<Snapshot?>(null)
    val busy = MutableStateFlow(false)
    val actionMessage = MutableStateFlow<String?>(null)

    val state: LinkState get() = snapshot.value?.state ?: LinkState.UNKNOWN

    fun reload() { settings.value = store.load(); snapshot.value = null; actionMessage.value = null }

    fun save(s: AppSettings) { store.save(s); reload() }

    suspend fun refresh() {
        val s = settings.value ?: return
        if (busy.value) return
        snapshot.value = LinkController.snapshot(s)
    }

    fun toggle() {
        val s = settings.value ?: return
        if (busy.value) return
        viewModelScope.launch {
            busy.value = true
            actionMessage.value = null
            try { snapshot.value = LinkController.set(state != LinkState.ON, s) }
            catch (e: AgentError) { actionMessage.value = e.message }
            busy.value = false
            if (actionMessage.value != null) refresh()
        }
    }
}
