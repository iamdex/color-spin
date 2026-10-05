// The app is the web game (web/index.html, bundled into game-html.js) in a
// full-screen WebView. The native side only keeps the screen awake, opens
// links in the phone's browser, shares the page's score picture, plays its
// haptics and forwards
// the back button and background events to the page (window.colorSpinApp in
// web/index.html).
import { useEffect, useRef } from 'react';
import { AppState, BackHandler, Linking, StyleSheet } from 'react-native';
import { StatusBar } from 'expo-status-bar';
import { File, Paths } from 'expo-file-system';
import * as Sharing from 'expo-sharing';
import * as Haptics from 'expo-haptics';
import { useKeepAwake } from 'expo-keep-awake';
import { SafeAreaProvider, SafeAreaView } from 'react-native-safe-area-context';
import { WebView } from 'react-native-webview';
import gameHtml from './game-html';

// A fixed https origin, so localStorage (best score, settings, leaderboard) persists.
const BASE_URL = 'https://color-spin.local/';
const BG = '#08080f';

// The game's haptics (window.ReactNativeWebView messages from web/index.html).
const HAPTICS = {
  light: () => Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light),
  medium: () => Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium),
  heavy: () => Haptics.notificationAsync(Haptics.NotificationFeedbackType.Error),
  success: () => Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success),
};

// The page sends the picture as a PNG data URL: save it and open the share sheet.
async function shareImage(dataUrl) {
  const base64 = typeof dataUrl === 'string' && dataUrl.startsWith('data:image/png;base64,') && dataUrl.split(',')[1];
  if (!base64 || !(await Sharing.isAvailableAsync())) return;
  const file = new File(Paths.cache, 'color-spin.png');
  file.create({ overwrite: true });
  file.write(base64, { encoding: 'base64' });
  await Sharing.shareAsync(file.uri, { mimeType: 'image/png', UTI: 'public.png', dialogTitle: 'Color Spin' });
}

export default function App() {
  useKeepAwake();
  const web = useRef(null);
  const call = hook => web.current?.injectJavaScript(`window.colorSpinApp?.${hook}(); true;`);

  useEffect(() => {
    const appState = AppState.addEventListener('change', s => call(s === 'active' ? 'foreground' : 'background'));
    const back = BackHandler.addEventListener('hardwareBackPress', () => { call('back'); return true; });
    return () => { appState.remove(); back.remove(); };
  }, []);

  function onMessage(e) {
    let msg;
    try { msg = JSON.parse(e.nativeEvent.data); } catch { return; }
    if (msg.type === 'open' && /^https:\/\//.test(msg.url)) Linking.openURL(msg.url);
    else if (msg.type === 'exit') BackHandler.exitApp();
    else if (msg.type === 'share') shareImage(msg.image).catch(() => {});
    else if (msg.type === 'haptic' && HAPTICS[msg.kind]) HAPTICS[msg.kind]().catch(() => {});
  }

  return (
    <SafeAreaProvider>
      <SafeAreaView style={styles.root}>
        <StatusBar hidden />
        <WebView
          ref={web}
          style={styles.root}
          source={{ html: gameHtml, baseUrl: BASE_URL }}
          originWhitelist={['*']}
          onMessage={onMessage}
          // The page never navigates: anything else goes to the phone's browser.
          onShouldStartLoadWithRequest={req => {
            if (req.url.startsWith(BASE_URL) || req.url.startsWith('about:')) return true;
            if (/^https?:\/\//.test(req.url)) Linking.openURL(req.url);
            return false;
          }}
          mediaPlaybackRequiresUserAction={false}
          allowsInlineMediaPlayback
          scrollEnabled={false}
          bounces={false}
          overScrollMode="never"
          textZoom={100}
          setSupportMultipleWindows={false}
          showsVerticalScrollIndicator={false}
          showsHorizontalScrollIndicator={false}
          webviewDebuggingEnabled={__DEV__}
          // If the system kills the page (low memory), start it again.
          onRenderProcessGone={() => web.current?.reload()}
          onContentProcessDidTerminate={() => web.current?.reload()}
        />
      </SafeAreaView>
    </SafeAreaProvider>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: BG },
});
