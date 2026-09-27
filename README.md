# Color Spin

Spin the shape and match the color of the balls. A game by Davide Dex Espertini.

- `web/index.html`: the game (JavaScript and canvas; graphics, sounds and music are generated in code).
  It runs as a claude.ai artifact, on GitHub Pages (`web/build-pages.sh`) and inside the mobile app.
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
```

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
