# CleverTap in-app campaign HTML

Source for custom-HTML in-app campaigns (also deployed at
https://vikaswiom.github.io/wiom-csp-guarantee-campaign/).

## `sla.html` — Service SLA guarantee (₹20,000 / 2 months)

Multi-screen in-app: hero → promise → payout plan → 2-question quiz → enroll → done.
Fires `Sehat_*` events through the `window.CleverTap` bridge and closes via
`CleverTap.dismissInAppNotification()`.

## ⚠️ Rule: no `//` comments inside the `<script>` block

CleverTap's custom-HTML editor (and copy-paste into it) can collapse the file
onto a single line. A `//` line comment then comments out **all code after it
on that line** — the script fails to parse with a `SyntaxError`, none of the
`onclick` handlers get defined, and the whole in-app becomes unclickable.

This is exactly what broke the Service SLA campaign: the minified script
contained `// console.log(...)`, which swallowed the closing `}catch(e){}}`
of a `try` block and killed the entire script.

**Use `/* block comments */ ` only.** Before shipping, sanity-check that the
script still parses after flattening:

```bash
node -e "
const html = require('fs').readFileSync('sla.html','utf8').replace(/\r?\n/g,' ');
new Function(html.match(/<script>([\s\S]*?)<\/script>/)[1]);
console.log('script parses OK when flattened to one line');
"
```
