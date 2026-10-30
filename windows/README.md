# SiteLink per Windows

App nella tray (area notifiche) con gli stessi campi e lo stesso wizard dell'app Mac:
pulsante ON/OFF, riconoscimento automatico della sede, aggiunta/rimozione della route.

## Installazione
1. Avvia `SiteLink-Setup.exe` (doppio clic), scegli le opzioni e premi **Installa**. Installa per il tuo
   utente in `%LOCALAPPDATA%\Programs\SiteLink` (nessun amministratore), crea il collegamento nel menu
   Start (e sul Desktop, se vuoi) e può avviare SiteLink all'accesso. Si disinstalla da
   **Impostazioni → App → App installate → SiteLink**.
   Se SmartScreen avvisa ("Windows ha protetto il PC"): **Ulteriori informazioni → Esegui comunque**
   (l'app non è firmata).
2. Al primo avvio si apre la configurazione guidata: nome, rete (es. `10.0.1.0/24`), IP del router
   con l'agent e token delle **due** sedi. Il PC deve essere in una delle due reti per la prova.
3. Salvando, Windows chiede il consenso dell'amministratore (UAC) **una sola volta**: crea 4 attività
   pianificate nella cartella `SiteLink` del Utilità di pianificazione, una per ogni comando
   `route add/delete` esatto. Da quel momento il pulsante funziona senza altre richieste.
4. L'icona compare nella tray (se nascosta: freccia `^` accanto all'orologio). Clic sinistro = pannello,
   clic destro = menu (Impostazioni, Avvia con Windows, Esci).

## Come funziona
- Config: `%APPDATA%\SiteLink\config.json` (stesso formato del Mac, token incluso: non condividerlo).
- Accensione: agent locale → route → agent dell'altra sede. Spegnimento: l'inverso.
- La route viene ripristinata da sola se sparisce (cambio rete, riavvio) mentre il link è acceso.
- Serve un account **amministratore** di Windows (le attività route girano con privilegi elevati).
- Il PC non deve avere una VPN installata verso l'altra rete (altrimenti la route di SiteLink è superflua).

## Risoluzione problemi
| Sintomo | Causa / rimedio |
|---|---|
| "Rete non riconosciuta" | Il PC non ha un IP in nessuna delle due reti. Controlla Wi-Fi/cavo. |
| "Agent … non raggiungibile" | IP/porta errati, agent spento o firewall: prova `curl http://IP:8765/health`. |
| "token non valido" | Token diverso da quello dell'agent: Impostazioni… e reinseriscilo. |
| "Permessi route mancanti" / pulsante grigio con "Autorizza…" | Premi **Autorizza…** e conferma l'UAC. Da rifare se cambi reti o gateway. |
| Una finestra nera lampeggia | È `route.exe` che gira per un istante: normale. |
| Disinstallare | Da "App installate": chiede se eliminare anche configurazione e autorizzazioni route (UAC). |

## Compilare
- Da Windows: installa l'SDK .NET 8 e lancia `.\build.ps1` → `dist\SiteLink-Setup.exe`.
- Da Mac/Linux: `./build.sh` (stesso risultato).
- Prove della logica (CIDR, route, attività, client agent): `dotnet run --project tests`.
