# Tampermonkey Configurator - Task State Notes

## Repo
- GitHub: bambisho/tampermonkey-configurator (master branch), local clone: /home/ubuntu/tm-easy
- Main script: tm-configure.ps1 (PowerShell, run as Admin on Windows)
- Combined user script: scripts/amazon-suite.user.js (v9.0)
- Run command for user:
  `irm "https://raw.githubusercontent.com/bambisho/tampermonkey-configurator/master/tm-configure.ps1?v=22" | iex`

## Version history (key)
- v13-15: managed-storage jsonImport provisioning (structural hash via /home/ubuntu/tm-work/tmhash.py) - FAILED on user's machine (settings never applied)
- v16: native install flow, 2 separate scripts, 2 tabs
- v17: single combined amazon-suite.user.js (v7.0), 1 tab
- v18: rebuilt combined script from user's updated uploads (v8.0)
- v19: 3-step flow with settings-only policy - settings still failed
- v20: CDP automation of TM settings page (verified e2e on Linux Chromium+TM 5.5) - user rejected, wants manual settings
- v21: simple 2 steps (TM install / script install), no settings automation
- v22 (current): SINGLE RUN - wipe + force-install policy + open Chrome + wait for TM download (Test-TmInstalled polls for manifest.json, 120s timeout) + open script install page. Added Find-Chrome (registry App Paths -> known dirs -> PATH) because plain `Start-Process "chrome.exe"` failed on user's machine (step 2 tab never opened).

## Combined script details (scripts/amazon-suite.user.js v9.0)
- Sources: /home/ubuntu/upload/amazon-address-filler.user.js (v5.1.0->patched) + /home/ubuntu/upload/amazonplatinum_autofill.user.js (v5.0)
- Builder: /home/ubuntu/tm-work/build_combined_v18.py (patches routing: broad host match instead of strict paths, adds heartbeat dots)
- Heartbeats: green dot bottom-right on amazon.co.uk/.de; blue dot bottom-left on delta.alliance.codes
- 4s delay after selecting Ireland country (was 2s) in fillIrishAddress before filling fields (user-reported lag fix)
- Delta: login autofill on /login (LOGIN_USER='bambisho'), FILL INFORMATION UK/DE buttons appear when [name="timer_work"] exists on any page
- Amazon: "Add Ireland Address" button attaches next to "Change address" link (UK returns); DE flow on /a/addresses/add pages

## Test harness
- /home/ubuntu/tm-work/test-panels/ : local HTML pages + puppeteer tests (run_test3.cjs, run_test4.cjs), system chromium at /usr/bin/chromium
- /home/ubuntu/tm-work/test-cdp-settings.py : CDP settings automation e2e test (works)
- /home/ubuntu/tm-work/profile + tm-ext: seeded Chromium profile with unpacked TM 5.5.0 (ext id hcjamhlkmdbgmibmnlehejchdhmolohh)

## User environment / preferences
- Windows, Chrome, Tampermonkey stable ext id dhdgffkkebhmkfjojejmpbldmpobfkfo
- Manual TM install worked fine; policy provisioning did not
- User wants: settings manual, TM+script install automated in ONE run
- TM settings desired manually: Config mode Advanced (100), external_update_interval Always
