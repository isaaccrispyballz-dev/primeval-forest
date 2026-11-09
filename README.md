# Primeval

An original forest survival game for Meta Quest 3, built with Godot 4.3 and OpenXR.
Your survey drone went down in an old-growth valley that isn't on any map. Chop wood,
build fires, and get through the night.

## Controls (Quest 3)
- **Hand-push movement:** press your hands into the ground or a tree trunk and push to move.
  Let go mid-push to launch yourself. You can climb trunks this way.
- **Left stick:** walk (when on the ground). **Right stick:** snap turn.
- **Axe (right hand):** swing it into a trunk. 4 hits fells a tree; walk over the logs to collect them.
- **A:** build a campfire (5 wood).

## Controls (PC, no headset)
WASD to move, mouse to look, click to chop, F for a campfire, Esc to free the mouse.

## Getting the APK onto your Quest
Every push to `main` builds an APK and publishes it as the latest GitHub release.
1. In the Quest browser, open `https://github.com/isaaccrispyballz-dev/primeval-forest/releases/latest`
   and tap **primeval.apk** to download it.
2. Install it from the headset (Developer Mode must be on), or from a PC with SideQuest
   / `adb install -r primeval.apk`.
3. In the app library, choose **Unknown Sources** and start Primeval.

## Smoke test
`godot --headless -s test.gd` chops a tree, collects logs, lights a fire and checks hand-push movement.

## Web prototype
`web-prototype/index.html` is the earlier WebXR version (three.js) of the same game.
