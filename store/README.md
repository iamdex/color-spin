# Color Spin sugli store

## App Store (iOS)

Tutto il materiale è pronto:

- `mobile/store.config.json`: la scheda in italiano (`it`) e inglese (`en-US`). Contiene
  nome, sottotitolo, testo promozionale, descrizione, parole chiave, link, categoria
  (Giochi › Casual, Azione), classificazione per età, note per la revisione e uscita manuale.
  La carica EAS Metadata.
- `store/app-store/it` e `store/app-store/en-US`: 6 screenshot per iPhone 6,9" (1320×2868)
  e 6 per iPad 13" (2064×2752). EAS Metadata non carica gli screenshot: si trascinano
  in App Store Connect.

### Passaggi

Da `mobile/`, con l'ultima versione (`git pull`):

1. **Completa il contatto per la revisione** in `store.config.json`, sotto `apple.review`:
   `email` e `phone`, nel formato `+39 …`. Apple li usa solo se deve contattarti durante
   la revisione. Poi controlla con `npx eas-cli@latest metadata:lint`.
2. **Build iOS**: `npx eas-cli@latest build -p ios --profile production`.
   La prima volta chiede di accedere con l'Apple ID, e poi di creare certificato e profilo:
   rispondi di sì.
3. **Invio ad App Store Connect**: `npx eas-cli@latest submit -p ios --latest`.
   Crea la scheda dell'app se non c'è e carica la build, che poi compare anche in TestFlight.
4. **Scheda**: `npx eas-cli@latest metadata:push`, che carica testi e impostazioni.
5. **Screenshot**: su App Store Connect apri l'app, poi la versione 1.7.0. Per ogni lingua
   (Italiano e Inglese USA) trascina i 6 `iphone-*.jpg` nella sezione iPhone 6,9" e i 6
   `ipad-*.jpg` nella sezione iPad 13", in ordine da 1 a 6.
6. **Privacy dell'app**: nella sezione "Privacy dell'app" dai le risposte della tabella qui sotto.
7. **Prezzo e disponibilità**: gratis, in tutti i paesi.
8. **Classificazione per età**: la parte principale la imposta già `metadata:push` (nessun
   contenuto sensibile). Se il questionario chiede dei contenuti generati dagli utenti,
   rispondi di sì: i nomi in classifica li scrivono i giocatori. Vedi la nota in fondo.
9. **Invia per la revisione**. Con l'uscita manuale, una volta approvata la pubblichi tu
   con un clic.

### Privacy dell'app: le risposte

Alla domanda "Raccogli dati da questa app?" rispondi **Sì**, poi dichiara solo questi tre tipi:

| Tipo di dato | Cosa è | Uso | Collegato all'identità? | Tracciamento? |
|---|---|---|---|---|
| Contenuti utente › Contenuti di gioco | Punteggi, livello, palline prese e durata delle partite da record | Funzionalità dell'app | No | No |
| Contenuti utente › Altri contenuti dell'utente | Il nome scelto per la classifica | Funzionalità dell'app | No | No |
| Identificatori › ID utente | Il codice casuale e anonimo del dispositivo per la classifica | Funzionalità dell'app | No | No |

Niente pubblicità, niente analisi, niente dati di posizione, contatti o salute. L'informativa
completa è su https://color-spin.espertini.com/privacy.html.

### Da sapere prima dell'invio

- **Nomi in classifica.** Per le app con contenuti scritti dagli utenti Apple chiede
  (linea guida 1.2) un filtro per i contenuti offensivi e un modo per segnalarli. Oggi i nomi
  non hanno filtri. Conviene aggiungere un filtro delle parole offensive sul server, più un
  contatto per le segnalazioni (c'è già nella pagina privacy) prima di inviare: riduce molto
  il rischio di un rifiuto.
- **URL di supporto**: è https://espertini.com. Apple vuole che da lì si possa contattare
  lo sviluppatore: assicurati che il sito abbia un contatto visibile.
- **Note per la revisione**: sono già scritte in inglese in `store.config.json`, dove
  spiegano che il gioco non richiede account e funziona offline.
