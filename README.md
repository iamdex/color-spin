# Color Spin

Spin the shape and match the color of the balls. A game by Davide Dex Espertini.

- `web/index.html`: the game (JavaScript and canvas; graphics, sounds and music are generated in code).
  It runs as a claude.ai artifact, on GitHub Pages (`web/build-pages.sh`) and inside the mobile app.
- `mobile/`: the Expo app for Android and iOS. It loads the web game in a full-screen WebView;
  `mobile/scripts/build-game.mjs` bundles `web/index.html` into it on `npm install` and `npm start`.
- `godot/`: the original Godot 4 version, kept as an archive. It is no longer updated.

## Mobile app

```sh
cd mobile
npm install
npm start -- --tunnel                                    # try it with Expo Go on your phone
npx eas-cli@latest build -p android --profile preview    # installable APK
npx eas-cli@latest build -p android --profile production # AAB for the Play Store
```
