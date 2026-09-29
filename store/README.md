# Color Spin sugli store

- [App Store (iOS)](#app-store-ios)
- [Google Play (Android)](#google-play-android)

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

- **Nomi in classifica.** Per i contenuti scritti dagli utenti Apple chiede (linea guida 1.2)
  un filtro e un modo per segnalarli. Ci sono tutti e due:
  - il server scarta i nomi offensivi in italiano e inglese (`server/src/names.js`): il giocatore
    compare come "Giocatore" e il gioco lo avvisa;
  - nella classifica, "Nome offensivo? Segnalalo su espertini.com" apre il sito.

  Per togliere a mano un nome segnalato, da `server/` (con il token in `.env`):
  `npx wrangler d1 execute color-spin-scores --remote --command "UPDATE players SET name='' WHERE name='NOME'; UPDATE daily SET name='' WHERE name='NOME'; UPDATE sprint SET name='' WHERE name='NOME'; UPDATE hardcore SET name='' WHERE name='NOME'"`.
  Nelle note per la revisione puoi scrivere che i nomi sono filtrati e segnalabili.
- **URL di supporto**: è https://espertini.com. Apple vuole che da lì si possa contattare
  lo sviluppatore: assicurati che il sito abbia un contatto visibile.
- **Note per la revisione**: sono già scritte in inglese in `store.config.json`, dove
  spiegano che il gioco non richiede account e funziona offline.

## Google Play (Android)

Tutto il materiale è in `store/google-play/it-IT` e `store/google-play/en-US`, nella
struttura standard di Google Play (la stessa che usa `fastlane supply`):

| File | Dove va in Play Console | Limite |
|---|---|---|
| `title.txt` | Nome dell'app | 30 caratteri |
| `short_description.txt` | Descrizione breve | 80 caratteri |
| `full_description.txt` | Descrizione completa | 4000 caratteri |
| `images/icon.png` | Icona dell'app (512×512) | |
| `images/featureGraphic.jpg` | Grafica in evidenza (1024×500) | |
| `images/phoneScreenshots/1-6.jpg` | Screenshot del telefono (1080×1920) | da 2 a 8 |
| `images/tenInchScreenshots/1-6.jpg` | Screenshot di tablet da 10" (1536×2048) | facoltativi |

### Passaggi

1. **Crea l'app** in Play Console: *Crea app*, nome "Color Spin", lingua predefinita
   Italiano, tipo **Gioco**, **Senza costi**.
2. **Scheda dello Store principale** (Aumenta il numero di utenti › Presenza nello store):
   incolla i testi e carica le immagini di `it-IT`. Poi *Gestisci traduzioni* ›
   Inglese (Stati Uniti), con i file di `en-US`.
   - Categoria: **Giochi › Arcade**. Tag consigliati: Arcade, Casual, Rompicapo.
   - Email di contatto: **è pubblica**, scegli quella che vuoi mostrare.
   - Sito web: https://color-spin.espertini.com/
3. **Contenuti dell'app** (Monitora e migliora › Norme › Contenuti dell'app), una sezione alla volta:
   - Norme sulla privacy: https://color-spin.espertini.com/privacy.html
   - Annunci: **No**, l'app non contiene annunci.
   - Accesso all'app: **tutte le funzionalità sono disponibili senza restrizioni**.
   - Classificazione dei contenuti: vedi sotto.
   - Pubblico di destinazione: vedi sotto.
   - Sicurezza dei dati: vedi sotto.
   - App governative, funzionalità finanziarie, salute: **No**.
4. **Build per lo store**: da `mobile/` lancia `npx eas-cli@latest build -p android --profile production`.
   Produce un file `.aab`, firmato con la stessa chiave dell'APK di prova.
5. **Test chiuso**: vedi la nota qui sotto. Il **primo** `.aab` va caricato **a mano**
   (Test › Test chiuso › Crea release): Google non accetta il primo caricamento dagli strumenti
   automatici. Dopo si può usare `npx eas-cli@latest submit -p android`, che però richiede
   una chiave di un account di servizio di Google.
6. **Produzione**: finito il test chiuso, chiedi l'accesso alla produzione e pubblica.

### Il test chiuso: 12 tester per 14 giorni

Per gli account sviluppatore personali creati dopo novembre 2023, Google chiede un **test
chiuso con almeno 12 tester** che restino iscritti per **14 giorni di fila** prima di
aprire la pubblicazione in produzione. Conviene partire subito:

1. Test › Test chiuso › crea una traccia e aggiungi una lista di email (Account Google) dei tester.
2. Carica il primo `.aab` (passaggio 4) e invia la release in revisione.
3. Manda ai tester il link di adesione: devono accettare e installare l'app dal Play Store.

Il conteggio dei 14 giorni parte da quando i 12 tester sono iscritti. Se il tuo account è
di un'organizzazione (partita IVA), il requisito non si applica.

### Sicurezza dei dati: le risposte

- L'app raccoglie o condivide dati utente? **Sì, li raccoglie** (non li condivide con terze parti).
- I dati sono crittografati in transito? **Sì** (HTTPS).
- Gli utenti possono chiedere l'eliminazione dei dati? **Sì**, tramite il contatto su espertini.com
  (è scritto nella pagina privacy).
- Tipi di dati, tutti **raccolti**, **non condivisi**, **non effimeri**, uso: **Funzionalità dell'app**:

| Categoria | Tipo | Cosa è |
|---|---|---|
| Attività nell'app | Altri contenuti generati dagli utenti | Il nome scelto per la classifica |
| Attività nell'app | Altre azioni | Punteggi, livello e durata delle partite da record |
| ID dispositivo o altri ID | ID dispositivo o altri ID | Il codice casuale e anonimo usato per la classifica |

Per ognuno: la raccolta è **obbligatoria** (avviene da sola quando fai un record).

### Classificazione dei contenuti (questionario IARC)

Categoria **Gioco**. A tutte le domande su violenza, paura, sesso, linguaggio, droghe e gioco
d'azzardo rispondi **No**. Alle domande sull'interazione tra utenti:
- Gli utenti possono comunicare o scambiarsi contenuti? **Sì**: i nomi in classifica sono visibili a tutti.
- Condivide la posizione dell'utente? **No**. Acquisti digitali? **No**.

Il risultato atteso è una classificazione per tutti (PEGI 3 / Everyone), con la nota
"Interazione tra utenti".

### Pubblico di destinazione

Consiglio **13 anni in su** (13-15, 16-17, 18+). Se includi i minori di 13 anni si applicano
le norme per le famiglie di Google, molto più severe sui contenuti scritti dagli utenti come
i nomi in classifica. Il gioco resta adatto a tutti: la classificazione dei contenuti lo dice comunque.

### Da sapere

- **I nomi in classifica** sono filtrati e segnalabili (vedi la sezione App Store): è quello che
  Google chiede per i contenuti generati dagli utenti.
- Quando l'app è pubblicata, il link è
  `https://play.google.com/store/apps/details?id=com.espertini.colorspin`: va messo in
  `STORE_LINKS.play` in `site/index.html`.
