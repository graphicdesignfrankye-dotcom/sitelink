# SiteLink per iPhone

App SwiftUI (iOS 17+) che accende e spegne il collegamento parlando **solo con gli agent** dei router.
Non modifica le route di iOS e non usa VPN proprie: l'iPhone deve poter raggiungere almeno un agent
(stando nella rete di una sede, oppure con Tailscale attivo sull'iPhone).

## Installazione (da Xcode)
1. Apri `ios/SiteLink.xcodeproj` con Xcode.
2. Target **SiteLink → Signing & Capabilities**: scegli il tuo **Team** (basta un Apple ID gratuito; con
   l'ID gratuito l'app scade dopo 7 giorni e va reinstallata). Se serve cambia il Bundle Identifier.
3. Collega l'iPhone (Modalità sviluppatore attiva: Impostazioni → Privacy e sicurezza), selezionalo in alto
   e premi **Run** (⌘R). La prima volta: Impostazioni → Generali → VPN e gestione dispositivi → fidati dello sviluppatore.
4. Alla prima apertura accetta il permesso **Rete locale** (serve per parlare con gli agent).

## Configurazione guidata (stessi campi di Mac e Windows)
Per ogni sede: nome, indirizzo dell'agent (es. `10.0.1.31`) e token; porta comune (8765).
- **Indirizzo alternativo** (facoltativo): per esempio l'IP Tailscale del router, da usare fuori dalle due reti.
  L'app prova prima l'ultimo indirizzo che ha funzionato.
- **Importa da config.json**: legge nomi, indirizzi e token dal file dell'app Mac.
- Si può scrivere anche `indirizzo:porta` se una sede usa una porta diversa.
- I token stanno nel Keychain dell'iPhone, non in chiaro nelle impostazioni.

## Come funziona
- Basta raggiungere **un** agent: l'altra sede si legge e si comanda tramite il peer (`/peer/...`).
- Acceso: prima l'agent raggiunto, poi l'altro. Spento: prima l'altro, poi quello raggiunto.
- Stato: Connesso (entrambi attivi), Disconnesso (entrambi spenti), Parziale, Sconosciuto.
- Se un agent risponde con un errore (token errato) l'app lo mostra e non ripiega sul peer.

## Comandi rapidi (Shortcuts)
In **Comandi rapidi → App → SiteLink** (o con Siri):
- *Imposta il collegamento* (parametro Acceso sì/no), anche "Accendi/Spegni il collegamento con SiteLink";
- *Inverti il collegamento*;
- *Stato del collegamento* (restituisce Connesso / Disconnesso / Parziale / Stato sconosciuto).
Si possono mettere in automazioni (per esempio all'arrivo a casa) o nella schermata Home.
Serve aver configurato l'app almeno una volta.

## Problemi comuni
| Sintomo | Rimedio |
|---|---|
| "Nessun agent raggiungibile" | Non sei in una rete di sede e non hai la VPN: attiva Tailscale e metti l'IP Tailscale come indirizzo alternativo. |
| Niente richiesta "Rete locale" / errore di rete in locale | Impostazioni → SiteLink → Rete locale: attivala. |
| "token non valido" | Token diverso da quello dell'agent: Impostazioni (ingranaggio) e reinseriscilo. |
| Pulsante grigio | Nessun agent raggiungibile direttamente. |

## Prove
`tests/run_logic_test.sh` compila la logica (senza interfaccia) e la prova contro due agent veri in locale:
stato, accensione/spegnimento, peer, indirizzo alternativo, token errato. Gira su Mac, senza simulatore.
