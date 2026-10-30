package local.sitelink.toggle.android

import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.repeatOnLifecycle
import kotlinx.coroutines.delay
import local.sitelink.core.LinkController
import local.sitelink.core.LinkState
import local.sitelink.core.SetupDraft
import local.sitelink.core.SettingsCodec
import local.sitelink.core.SiteForm
import local.sitelink.core.SiteState

class MainActivity : ComponentActivity() {
    private val vm: LinkViewModel by viewModels()

    private val localNetwork = registerForActivityResult(ActivityResultContracts.RequestPermission()) { }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Android 17+: permesso per parlare con gli agent nella rete locale.
        if (Build.VERSION.SDK_INT >= 37) localNetwork.launch("android.permission.ACCESS_LOCAL_NETWORK")
        setContent {
            val dark = androidx.compose.foundation.isSystemInDarkTheme()
            MaterialTheme(colorScheme = if (dark) darkColorScheme() else lightColorScheme()) {
                Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) { AppScreen(vm) }
            }
        }
    }
}

private val Green = Color(0xFF2EA043)
private val Orange = Color(0xFFE68C14)
private val Gray = Color(0xFF828282)
private val LightGray = Color(0xFFAAAAAA)

private fun stateColor(s: LinkState) = when (s) {
    LinkState.ON -> Green; LinkState.PARTIAL -> Orange; LinkState.OFF -> Gray; LinkState.UNKNOWN -> LightGray
}

private fun stateTitle(s: LinkState) = when (s) {
    LinkState.ON -> "Connesso"; LinkState.OFF -> "Disconnesso"; LinkState.PARTIAL -> "Parziale"; LinkState.UNKNOWN -> "Stato sconosciuto"
}

@Composable
fun AppScreen(vm: LinkViewModel) {
    val settings by vm.settings.collectAsStateWithLifecycle()
    var showSetup by remember { mutableStateOf(false) }

    // Aggiornamento ogni 10 s finché la schermata è visibile.
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    LaunchedEffect(settings) {
        if (settings == null) { showSetup = true; return@LaunchedEffect }
        lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) {
            while (true) { vm.refresh(); delay(10_000) }
        }
    }

    if (showSetup || settings == null) {
        SetupScreen(vm, canClose = settings != null, onClose = { showSetup = false })
    } else {
        MainScreen(vm, onSettings = { showSetup = true })
    }
}

@Composable
fun MainScreen(vm: LinkViewModel, onSettings: () -> Unit) {
    val snap by vm.snapshot.collectAsStateWithLifecycle()
    val busy by vm.busy.collectAsStateWithLifecycle()
    val action by vm.actionMessage.collectAsStateWithLifecycle()
    val state = snap?.state ?: LinkState.UNKNOWN
    val message = action ?: snap?.message

    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text("SiteLink", fontSize = 20.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
            TextButton(onClick = onSettings) { Text("Impostazioni") }
        }
        Spacer(Modifier.height(24.dp))
        PowerButton(color = stateColor(state), busy = busy, enabled = !busy && (snap?.canControl ?: false)) { vm.toggle() }
        Spacer(Modifier.height(22.dp))
        Text(stateTitle(state), fontSize = 28.sp, fontWeight = FontWeight.Bold)
        Spacer(Modifier.height(22.dp))
        val s = snap
        if (s == null) CircularProgressIndicator() else {
            Column(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp))
                    .background(MaterialTheme.colorScheme.surfaceVariant).padding(horizontal = 16.dp),
            ) {
                s.states.forEachIndexed { i, st ->
                    if (i > 0) HorizontalDivider()
                    SiteRow(st)
                }
            }
        }
        if (message != null) {
            Spacer(Modifier.height(16.dp))
            Text(message, fontSize = 13.sp, color = Orange, textAlign = TextAlign.Center)
        }
    }
}

@Composable
private fun SiteRow(st: SiteState) {
    Row(Modifier.fillMaxWidth().padding(vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
        val c = when { st.status == null -> Color.Red; st.status!!.linkEnabled -> Green; else -> Gray }
        Box(Modifier.size(10.dp).clip(CircleShape).background(c))
        Spacer(Modifier.size(10.dp))
        Text(st.site.name, modifier = Modifier.weight(1f))
        Column(horizontalAlignment = Alignment.End) {
            Text(
                st.status?.let { if (it.linkEnabled) "attivo" else "spento" } ?: "offline",
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            if (st.viaPeer) Text("tramite l'altra sede", fontSize = 11.sp, color = MaterialTheme.colorScheme.outline)
        }
    }
}

@Composable
private fun PowerButton(color: Color, busy: Boolean, enabled: Boolean, onClick: () -> Unit) {
    Box(
        Modifier.size(190.dp).clip(CircleShape).clickable(enabled = enabled, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        val c = if (enabled || busy) color else color.copy(alpha = 0.6f)
        Canvas(Modifier.fillMaxSize()) {
            val stroke = 5.dp.toPx()
            drawCircle(c.copy(alpha = 0.18f))
            drawCircle(c, radius = size.minDimension / 2 - stroke / 2, style = Stroke(stroke))
            if (!busy) {
                val r = size.minDimension * 0.19f
                val ctr = Offset(size.width / 2, size.height / 2 + 6.dp.toPx())
                val w = 9.dp.toPx()
                drawArc(c, startAngle = -60f, sweepAngle = 300f, useCenter = false,
                    topLeft = Offset(ctr.x - r, ctr.y - r), size = Size(r * 2, r * 2), style = Stroke(w, cap = StrokeCap.Round))
                drawLine(c, Offset(ctr.x, ctr.y - r - 8.dp.toPx()), Offset(ctr.x, ctr.y), strokeWidth = w, cap = StrokeCap.Round)
            }
        }
        if (busy) CircularProgressIndicator(Modifier.size(48.dp), color = color)
    }
}

// ---------------------------------------------------------------- configurazione guidata

private class TestLine(val ok: Boolean?, val text: String)

@Composable
fun SetupScreen(vm: LinkViewModel, canClose: Boolean, onClose: () -> Unit) {
    var step by remember { mutableStateOf(0) }
    var draft by remember { mutableStateOf(SetupDraft.from(vm.settings.value)) }
    val lines = remember { mutableStateListOf<TestLine>() }
    var testing by remember { mutableStateOf(false) }
    var importError by remember { mutableStateOf<String?>(null) }
    val context = LocalContext.current

    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        importError = null
        try {
            val json = context.contentResolver.openInputStream(uri)!!.bufferedReader().use { it.readText() }
            val (sites, port) = SettingsCodec.importMacConfig(json)
            draft = draft.copy(
                a = SiteForm(sites[0].name, sites[0].host, "", sites[0].token),
                b = SiteForm(sites[1].name, sites[1].host, "", sites[1].token),
                port = port?.toString() ?: draft.port,
            )
        } catch (e: Exception) { importError = "Importazione non riuscita: ${e.message}" }
    }

    LaunchedEffect(step) {
        if (step != 2) return@LaunchedEffect
        testing = true; lines.clear()
        val snap = LinkController.snapshot(draft.toSettings())
        for (st in snap.states) {
            val s = st.status
            lines += if (s != null)
                TestLine(true, "«${st.site.name}» risponde" + (if (st.viaPeer) " (tramite l'altra sede)" else " e il token è corretto") +
                    " — VPN ${if (s.vpnUp) "attiva" else "spenta"}.")
            else TestLine(null, "«${st.site.name}»: ${st.error ?: "non raggiungibile"}.")
        }
        if (snap.states.all { it.status == null })
            lines += TestLine(false, "Nessun agent raggiungibile. Controlla indirizzi, porta e token, e di essere nella rete di una sede o con la VPN attiva.")
        else if (!snap.canControl) lines += TestLine(false, "Nessun agent è raggiungibile direttamente.")
        testing = false
    }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text("Configura SiteLink", fontSize = 20.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
            if (canClose) TextButton(onClick = onClose) { Text("Chiudi") }
        }
        when (step) {
            0 -> {
                Text("Benvenuto in SiteLink", fontSize = 22.sp, fontWeight = FontWeight.Bold)
                Text("Questa app accende e spegne il collegamento tra due sedi, per esempio il tuo ufficio e casa, parlando con gli agent installati sui router. Prima di configurarla deve essere già stato fatto tutto il resto:")
                for (t in listOf(
                    "Su ciascun router che collega la sede (uno per sede) è installato e funzionante l'agent SiteLink.",
                    "I due agent sono configurati per raggiungersi tra loro (peer).",
                    "Il collegamento tra le due reti (VPN) è già configurato sui router.",
                    "Il telefono non modifica le sue route: deve poter raggiungere almeno uno dei due agent, stando nella sua rete o con una VPN (per esempio Tailscale) attiva.",
                )) Text("•  $t")
                Text("Ti serviranno, per ogni sede: un nome, l'indirizzo dell'agent e il suo token.", color = MaterialTheme.colorScheme.onSurfaceVariant)
                Button({ step = 1 }, Modifier.align(Alignment.End)) { Text("Continua") }
            }
            1 -> {
                TextButton({ picker.launch(arrayOf("*/*")) }) { Text("Importa da config.json (Mac)…") }
                importError?.let { Text(it, fontSize = 12.sp, color = Orange) }
                Text("Facoltativo: legge nomi, indirizzi e token dal file dell'app Mac.", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                SiteFields("Sede 1", draft.a, "Ufficio", "10.0.1.31") { draft = draft.copy(a = it) }
                SiteFields("Sede 2", draft.b, "Casa", "10.0.2.2") { draft = draft.copy(b = it) }
                OutlinedTextField(draft.port, { draft = draft.copy(port = it) }, label = { Text("Porta degli agent") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number), singleLine = true, modifier = Modifier.fillMaxWidth())
                val errs = draft.allErrors
                if (errs.isNotEmpty() && !draft.isPristine) errs.take(3).forEach { Text(it, fontSize = 12.sp, color = Orange) }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    TextButton({ step = 0 }) { Text("Indietro") }
                    Button({ step = 2 }, enabled = errs.isEmpty()) { Text("Avanti") }
                }
            }
            else -> {
                if (testing) Row(verticalAlignment = Alignment.CenterVertically) {
                    CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp); Spacer(Modifier.size(10.dp)); Text("Provo la connessione…")
                }
                lines.forEach {
                    val (glyph, c) = when (it.ok) { true -> "✔" to Green; false -> "✖" to Color.Red; null -> "ℹ" to Gray }
                    Row { Text(glyph, color = c); Spacer(Modifier.size(8.dp)); Text(it.text) }
                }
                Text("Dal telefono basta raggiungere un agent: l'altro viene comandato tramite il peer.", fontSize = 12.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    TextButton({ step = 1 }) { Text("Indietro") }
                    Button({ vm.save(draft.toSettings()); onClose() }, enabled = !testing) {
                        Text(if (lines.any { it.ok == false }) "Salva comunque" else "Salva e chiudi")
                    }
                }
            }
        }
    }
}

@Composable
private fun SiteFields(title: String, f: SiteForm, nameHint: String, hostHint: String, onChange: (SiteForm) -> Unit) {
    Text(title, fontWeight = FontWeight.SemiBold)
    OutlinedTextField(f.name, { onChange(f.copy(name = it)) }, label = { Text("Nome") }, placeholder = { Text(nameHint) },
        singleLine = true, modifier = Modifier.fillMaxWidth())
    OutlinedTextField(f.host, { onChange(f.copy(host = it)) }, label = { Text("Indirizzo dell'agent") }, placeholder = { Text(hostHint) },
        singleLine = true, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri), modifier = Modifier.fillMaxWidth())
    OutlinedTextField(f.altHost, { onChange(f.copy(altHost = it)) }, label = { Text("Indirizzo alternativo (facoltativo)") },
        placeholder = { Text("IP Tailscale del router") }, singleLine = true,
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri), modifier = Modifier.fillMaxWidth())
    OutlinedTextField(f.token, { onChange(f.copy(token = it)) }, label = { Text("Token") }, singleLine = true,
        visualTransformation = PasswordVisualTransformation(), modifier = Modifier.fillMaxWidth())
}
