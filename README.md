# Color Spin

Spin the shape and match the color of the balls. A game by Davide Dex Espertini.

- `web/index.html`: the game (JavaScript and canvas; graphics, sounds and music are generated in code).
  It runs as a claude.ai artifact, on GitHub Pages at https://color-spin.espertini.com/play/ and inside the mobile app.
- `site/`: the presentation site at https://color-spin.espertini.com/ (with the privacy policy). The store links
  are the `STORE_LINKS` placeholders at the top of the script in `site/index.html`.
  `web/build-pages.sh <dir>` builds the Pages site: `site/` at the root and the game under `play/`.
  The custom domain is set by `site/CNAME` (DNS: a CNAME on Cloudflare to iamdex.github.io, DNS only).
- `mobile/`: the Expo app for Android and iOS. It loads the web game in a full-screen WebView;
  `mobile/scripts/build-game.mjs` bundles `web/index.html` into it on `npm install` and `npm start`.
- `server/`: the global leaderboard (https://scores.espertini.com), a Cloudflare Worker with a D1 database. Used by GitHub Pages
  and the app; the claude.ai artifact keeps its own leaderboard.
- `godot/`: the original Godot 4 version, kept as an archive. It is no longer updated.

## Mobile app

```sh
cd mobile
npm install
npm start -- --tunnel                                    # try it with Expo Go on your phone
npx eas-cli@latest build -p android --profile preview    # installable APK
npx eas-cli@latest build -p android --profile production # AAB for the Play Store
npx eas-cli@latest build -p ios --profile production     # for the App Store (asks for the Apple login)
```

### Over-the-air updates (EAS Update)

The whole game is JavaScript (`web/index.html`, bundled into `game-html.js`), so a change to the
game reaches the store builds without a new review:

```sh
cd mobile
npm run ota -- --message "What changed"           # production channel: the store builds
npm run ota:preview -- --message "What changed"   # preview channel: the test APKs
```

The script rebuilds `game-html.js` first. Phones download the update in the background when the app
starts and use it from the next launch.

An update reaches only the builds with the same app version (`runtimeVersion` policy `appVersion`), so
**keep `version` in `app.json` unchanged for OTA updates** (the game's own `VERSION` can move on).
Change it only for a new store build, which a native change (a new Expo module, a new permission)
always needs.

## Leaderboard server

```sh
cd server
npm install
npm run db:init:local && npm run dev   # local server on http://localhost:8787
npm run deploy                         # publish (needs CLOUDFLARE_API_TOKEN in server/.env)
```

`GET /v1/scores?player=<id>` returns the top 10 and the player's rank; `POST /v1/scores` saves a game.
Each device is an anonymous player with a random id; the server keeps its best score and its name,
and refuses scores that don't match the game's rules.
