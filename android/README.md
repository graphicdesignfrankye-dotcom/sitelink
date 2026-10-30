# SiteLink per Android

App Android (Kotlin, Jetpack Compose, Android 8.0 / API 26 in su) che accende e spegne il collegamento
parlando **solo con gli agent** dei router. Non usa VPN proprie e non modifica le route del telefono: deve poter
raggiungere almeno un agent, stando nella rete di una sede oppure con Tailscale attivo sul telefono.

## Installare l'APK
1. Scarica `SiteLink-Android.apk` (dalla pagina Release del repository) direttamente dal telefono.
2. Aprilo. Android chiede di consentire "Installa app sconosciute" per il browser o per l'app File che l'ha
   scaricato: attivalo, torna indietro e installa.
3. Play Protect può avvisare che l'app non è verificata (non è nel Play Store): **Installa comunque**.
4. Alla prima apertura parte la configurazione guidata (stessi campi di Mac, Windows e iPhone).

Aggiornare: installa il nuovo APK sopra il vecchio (funziona solo se firmato con la stessa chiave).

## Configurazione
Per ogni sede: nome, indirizzo dell'agent (es. `10.0.1.31`) e token; porta comune (8765).
- **Indirizzo alternativo** (facoltativo): l'IP Tailscale del router (`tailscale ip -4`), per quando non sei nelle due reti.
- **Importa da config.json**: legge nomi, indirizzi e token dal file dell'app Mac (copialo sul telefono con un
  cavo o un cloud privato, poi cancellalo: contiene i token).
- `indirizzo:porta` se una sede usa una porta diversa.
- I token sono salvati cifrati (Android Keystore), non in chiaro.

## Uso
- Pulsante grande ON/OFF e stato delle due sedi (si aggiorna ogni 10 s).
- **Impostazioni rapide**: aggiungi il riquadro "SiteLink" alla tendina (matita di modifica) per accendere e
  spegnere senza aprire l'app. Serve aver configurato l'app una volta.
- Basta raggiungere **un** agent: l'altra sede si comanda tramite il peer.

## Problemi comuni
| Sintomo | Rimedio |
|---|---|
| "Nessun agent raggiungibile" | Non sei in una rete di sede e non c'è l'indirizzo alternativo: attiva Tailscale sul telefono e inserisci gli IP 100.x. |
| Errore anche sul Wi-Fi giusto | Impostazioni → App → SiteLink → Autorizzazioni: consenti **Dispositivi nelle vicinanze / Rete locale** (Android 17+). Prova `http://IP:8765/health` dal browser del telefono. |
| "token non valido" | Token diverso da quello dell'agent: Impostazioni nell'app e reinseriscilo. |
| L'APK non si installa ("app non installata") | Esiste già una versione firmata con un'altra chiave: disinstallala prima (si perdono le impostazioni). |
| Il riquadro è grigio | Configura prima l'app. |

## Compilare (Android Studio o riga di comando)
- **Android Studio**: apri la cartella `android/`. Servono SDK 35 e un JDK 17 per Gradle.
- **Da terminale**: `./build-apk.sh` → `dist/SiteLink-Android.apk`.
  Servono un JDK 17 in `~/Library/Android/jdk/jdk-17*/` (o `JAVA_HOME`) e l'SDK in `~/Library/Android/sdk`
  (piattaforma 35, build-tools 35.0.0). Il JDK 25 di Android Studio è troppo nuovo per questo Gradle.
- **Firma**: crea una chiave una volta e **conservala** (senza non puoi pubblicare aggiornamenti installabili):
  ```
  keytool -genkeypair -keystore sitelink-release.jks -alias sitelink -keyalg RSA -keysize 4096 -validity 10000
  ```
  poi `keystore.properties` con `storeFile`, `storePassword`, `keyAlias`, `keyPassword`. Entrambi i file sono
  ignorati da git. Senza `keystore.properties` lo script firma con la chiave di debug (solo per prove).
- **Prove della logica** (stato, comando, peer, indirizzo alternativo, token errato, wizard), contro due agent
  veri in locale: `tests/run_logic_test.sh`.
