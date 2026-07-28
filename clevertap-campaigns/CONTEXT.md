# CleverTap campaigns — working context

Everything learned and built across the CleverTap in-app campaign work
(July 2026). Read this before touching any campaign HTML or dashboard.

## The repos and where everything lives

| Repo | What it holds |
|---|---|
| `Vikaswiom/wiom-mbg-kamai-kavach` (this repo, branch `claude/clevrtap-campaign-clickable-88k0sl`) | `clevertap-campaigns/` — canonical copies of campaign HTML + these docs |
| `Vikaswiom/wiom-csp-guarantee-campaign` | GitHub Pages for the ₹20,000 guarantee campaigns: `/` = Optical Power (Sehat MG), `/sla.html` = Service SLA |
| `Vikaswiom/wiom-offer-education-campaign` | Campaign dashboards (GitHub Pages): `dashboard.html` (Offer Education), `bonus.html` (Bonus Seva video) + CleverTap fetchers + refresh workflow |
| `Vikaswiom/wiom-inapp-video` | Video hosting, served via jsDelivr: `https://cdn.jsdelivr.net/gh/Vikaswiom/wiom-inapp-video@main/<file>` |

Live URLs:
- https://vikaswiom.github.io/wiom-csp-guarantee-campaign/ and `/sla.html`
- https://vikaswiom.github.io/wiom-offer-education-campaign/dashboard.html
- https://vikaswiom.github.io/wiom-offer-education-campaign/bonus.html

## ⚠️ The three rules of CleverTap custom HTML (each one broke a real campaign)

1. **Never use `//` line comments in campaign `<script>` blocks.** CleverTap's
   editor collapses pasted HTML onto one line; a `//` comment then swallows all
   code after it, the script fails to parse, and every button goes dead. This is
   what made the Service SLA in-app unclickable. Block comments only. Sanity
   check before shipping:
   `new Function(html.match(/<script>([\s\S]*?)<\/script>/)[1].replace(/\n/g,' '))`
2. **Event properties must cross the Android bridge as a JSON string.**
   `window.CleverTap` in the in-app WebView is a Java `@JavascriptInterface`;
   its two-arg form is `pushEvent(String, String)`. Passing a JS object doesn't
   marshal, the native JSON parse throws, and the event is silently dropped.
   Always `pushEvent(name, JSON.stringify(props))`. Name-only events may use the
   one-arg form.
3. **iOS has no `window.CleverTap` at all.** The bridge is
   `window.webkit.messageHandlers.clevertap.postMessage({action:
   'recordEventWithProps', event, properties})`, and
   `{action:'dismissInAppNotification'}` for closing (verify dismiss support on
   the app's iOS SDK version). Every `ct()`/`h()` helper in these campaigns
   handles both platforms.

Also: events only fire inside the app's in-app WebView. Opening campaign pages
on GitHub Pages or desktop records nothing by design — the bridge object is
absent, and the helpers no-op silently.

## Campaigns in this folder

### `sla.html` — Service SLA guarantee (₹20,000 / 2 months)
Multi-screen: hero → promise → payout plan → 2-question quiz → enroll → done.
Events `Sehat_*` with `offer_id: sehat_sla`, `metric: Service SLA`.

### `optical-power.html` — Sehat MG / Optical Power guarantee
Same template, `offer_id: sehat_optical`, `metric: Optical Power`. Deployed as
`index.html` of wiom-csp-guarantee-campaign.

Shared `Sehat_*` funnel (segment by `offer_id`): `Sehat_View_education` →
`Sehat_Learn_More` → `Sehat_View_plan` → `Sehat_Start_Quiz` →
`Sehat_Quiz_Answered` (question, choice, correct) ×2 → `Sehat_Quiz_Complete` →
`Sehat_View_enroll` → `Sehat_OptIn` (conversion). Final "ठीक है" only
dismisses. Quiz guards prevent double answers; `Sehat_OptIn` fires once.

### `bonus-seva-video.html` — Bonus Seva video campaign (new system bonus)
Flow: education popup ("1 अगस्त से आपके बोनस पर असर पड़ सकता है", frosted-blur
scrim, और जानें) → full-page 9:16 portrait video (object-fit:cover, whole phone
covered) with समझ गया button gated by a 45s in-button countdown (also unlocks
on video `ended`/`error` so the flow can never dead-end) → one quiz (क्वालिटी
की पूरी जानकारी कहाँ मिलेगी?) → ठीक है dismisses.

Video: `seva_sthiti_intro_portrait_v4.mp4` (H.264/AAC, 720×1280) in
wiom-inapp-video, via jsDelivr. **Always upload new videos under a NEW filename**
— jsDelivr caches `@main` aggressively; a new name serves instantly, and old
campaigns keep working.

Event schema (`Bonus_Seva_*`, all unique-user analysis on profile identity):

| Event | Fires | Props |
|---|---|---|
| `Bonus_Seva_Intro_Viewed` | in-app rendered | — |
| `Bonus_Seva_LearnMore_Clicked` | और जानें | — |
| `Bonus_Seva_Intro_Dismissed` | ✕ on popup | — |
| `Bonus_Seva_Video_Played` | first real playback | — |
| `Bonus_Seva_Video_Dismissed` | ✕ on player | `watched_seconds` |
| `Bonus_Seva_Understood_Clicked` | समझ गया | `watched_seconds` |
| `Bonus_Seva_Quiz_Answered` | quiz tap | `choice` (help_icon/luck/rotate_phone), `correct` |
| `Bonus_Seva_Flow_Completed` | final ठीक है | — |

Dismiss-after-event buttons delay `ctClose` by 200ms so the event reaches the
bridge before the WebView is torn down. Apps Script beacons (`flow=BONUS`) fire
alongside all CT events; `close-video` beacon carries seconds (`close-video-12s`).

Full-page video note: phones are taller than 9:16, so `cover` crops a sliver
off the left/right edges. The backdrop blur (`backdrop-filter:blur(14px)` on
the popup scrim) blurs the app behind only if the host WebView is transparent
and honors it; otherwise the dark tint is the fallback. To GUARANTEE full-screen
display, the CleverTap campaign layout must be 100%×100% with 0 margins —
HTML cannot paint outside the WebView frame.

## Dashboards + data pipeline (wiom-offer-education-campaign repo)

- `fetch_ct_data.py` / `dashboard.html` — Offer Education funnel, two apps.
- `fetch_bonus_data.py` / `bonus.html` — Bonus Seva funnel, drop-offs with
  watched_seconds distribution, quiz split.
- `.github/workflows/refresh-ct-data.yml` — refreshes both `data.json` and
  `bonus_data.json` every 30 min (off-peak cron minutes `11,41` — GitHub drops
  the congested :00/:15/:30/:45 slots). Secrets: `CLEVERTAP_ACCOUNT`,
  `CLEVERTAP_PASSCODE` (region eu1 is the default in code). The job exits
  quietly if secrets are missing. Manual runs: Actions → refresh-ct-data →
  Run workflow (starts in seconds).
- `.github/workflows/probe-campaign.yml` + `probe_campaign.py` — read-only
  diagnostic for any campaign id: campaign stats endpoint, Notification
  Viewed/Clicked and inApp_Shown export search, campaign_id breakdown. Use it
  whenever the CleverTap UI and the dashboard disagree.

### Attribution lessons (the Technician-funnel saga)
- Only `inApp_Shown` (custom, fired by app code) carries `campaign_id` — the
  in-app HTML's own events carry no app/campaign marker, so funnels attribute
  by intersecting profile identities from the events export.
- The Technician app **does not fire `inApp_Shown` at all**. Its impressions
  exist only as CleverTap's system event **`Notification Viewed`** with
  `wzrk_id = "<campaignId>_<YYYYMMDD>"` — this is the number the campaigns UI
  shows as "viewed". The tech funnel's Shown step uses it (locked cohort);
  `role = technician` profile-property filtering remains as fallback.
- UI "viewed" counts can differ ±1 from identity-deduped export counts
  (records without identity are dropped).
- CleverTap 400s on event names it has never seen — normal before a new
  campaign's first fire; fetchers treat it as zero and dashboards render a
  pending state. New event names appear in CleverTap only after first fire.

## Credentials

Never commit CleverTap Account ID / Passcode — all these repos are public, and
the passcode grants full API access. They belong ONLY in GitHub Actions repo
secrets (or `C:\credentials\.env` locally). Never put them in client-side JS.
If the passcode ever leaks (chat, script, page source), rotate it in CleverTap
and update the `CLEVERTAP_PASSCODE` secret.
