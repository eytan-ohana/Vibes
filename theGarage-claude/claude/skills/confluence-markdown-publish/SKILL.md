---
name: confluence-markdown-publish
description: >-
  How to publish a Markdown document (design docs, READMEs, notes) to Confluence
  Cloud via the Atlassian MCP so it renders correctly — working in-page section
  cross-links and visible architecture diagrams (Mermaid). Use whenever asked to
  "upload/publish this markdown to Confluence", "put this design doc in Confluence",
  "create a Confluence page from this file", or to fix anchor links / Mermaid
  diagrams on a Confluence page. Covers the Atlassian MCP tools, the heading-anchor
  scheme, the percent-encoding needed for `[§x](#anchor)` links, and rendering +
  embedding diagrams as image attachments via the authenticated browser.
---

# Publishing Markdown to Confluence Cloud

Confluence Cloud is reached through the **Atlassian MCP** tools (`mcp__claude_ai_Atlassian__*`).
Passing Markdown as the body (`contentFormat: "markdown"`) converts most things well —
**but two things need special handling**: in-page section cross-links and Mermaid
diagrams. The notes below are the result of empirically probing a real instance.

## 0. Locate where to publish

- **cloudId**: pass the site hostname directly, e.g. `formcom.atlassian.net` (no UUID lookup needed for most tools; fall back to `getAccessibleAtlassianResources` if it fails).
- **spaceId**: `getConfluenceSpaces({cloudId, keys: ["~personalSpaceKey"]})` → numeric `id`. A personal space key looks like `~712020e82275...`; it's in the space URL.
- **Parent**: a Confluence **folder** is a valid `parentId` for a page. Folders don't show up via `getPagesInConfluenceSpace` (that's pages); find one with
  `searchConfluenceUsingCql({cql: 'title ~ "Design Docs" AND space = "~key"'})` → result `id` (type `folder`).
- Create with `createConfluencePage({cloudId, spaceId, parentId, title, status:"current", contentFormat:"markdown", body})`.

**Pitfall — draft publish:** publishing an existing *draft* to `current` can fail with
"Version number must be 1 when publishing a page for the first time. Provided version: [2]".
Avoid it by **creating directly as `status: "current"`** (create sets version 1 cleanly).

**Pitfall — body size:** the whole document goes inline in the `body` param. That's fine, just large.

## 1. Section cross-links (`[§6.6](#...)`) — the anchor scheme

Markdown like `[§6.6](#anchor)` becomes a Confluence link whose target is your
`#fragment` **verbatim**. For it to actually jump, the fragment must equal
Confluence's auto-generated heading `id`, which is:

> **heading text → spaces replaced by hyphens; case and punctuation preserved.**

Examples (real, verified):
- `## 1. Summary` → `id="1.-Summary"`
- `## 2. Goals & non-goals` → `id="2.-Goals-&-non-goals"`
- `### 6.6 Guaranteeing VLM ... don't break ingestion` → `id="6.6-Guaranteeing-VLM-...-don't-break-ingestion"`

So **GitHub-style slugs do NOT work** (Confluence keeps case + punctuation, doesn't lowercase/strip).

**The parsing gotcha:** the Markdown→storage converter **silently strips the `href`**
of a link whose destination contains `(`, `)`, or `:` (e.g. `(open)`, `Granularity:`).
The link text survives but it's no longer a link.

**Fix — percent-encode the special chars in the fragment.** The browser decodes the
fragment when matching the `id`, so `#...%3F-%28open%29` matches `id="...?-(open)"`.
Keep `-` `.` `_` and alphanumerics literal; encode the rest. Build the fragment as:

```python
from urllib.parse import quote
def confluence_anchor(heading_text):
    # heading_text = the rendered heading WITHOUT leading '#'s and WITHOUT backticks
    t = heading_text.replace('`', '').strip().replace(' ', '-')
    return quote(t, safe='-._')   # encodes ( ) ? : , + * & ' ↔ etc.; browser decodes on match
# '6.10 Theme: is category ↔ content 1:1? (open)'
#   -> '#6.10-Theme%3A-is-category-%E2%86%94-content-1%3A1%3F-%28open%29'
```

Keep the **repo copy** of the Markdown using normal GitHub-style anchors (so it works
on GitHub); generate a **separate Confluence copy** where the fragments use the scheme
above. A small script that maps each `§N.M` reference to its heading's
`confluence_anchor` and rewrites only the link targets does the job. Skip fenced code
blocks when rewriting.

**Always verify** after upload (see §3).

## 2. Mermaid diagrams — render to PNG and embed as attachments

Confluence Cloud (without a Mermaid app) does **not** render ` ```mermaid ` blocks — the
Markdown converter turns them into a **code macro** that just shows the source. Also:
**attached SVGs do NOT display inline** (they render to nothing). So:

> Render each diagram to a **raster PNG**, attach it, and embed with an image macro.

### 2a. Render + shrink (locally)
```bash
npx -y @mermaid-js/mermaid-cli@latest -i diagram.mmd -o diagram.png -b white -s 2
```
PNGs of flat diagrams shrink a lot via palette quantization (keeps text crisp):
```python
from PIL import Image            # available in the garage38ai conda env
im = Image.open("diagram.png").convert("RGBA")
bg = Image.new("RGBA", im.size, (255,255,255,255)); bg.alpha_composite(im)
bg.convert("RGB").quantize(colors=64, method=Image.MEDIANCUT).save("diagram-q.png", optimize=True)
```
Sanity-check the busiest diagram visually (Read the PNG) — confirm `\n` in node labels
became line breaks and text is legible.

### 2b. Upload as attachments — via the authenticated browser (cheap, no base64 in context)
Use the **chrome-devtools MCP** with the user's logged-in Confluence session. Do NOT
base64-inline the image bytes into tool calls (huge token cost). Instead:

1. Confirm the browser is authenticated (navigate to the page; if redirected to
   `id.atlassian.com/login`, ask the user to log in — they can do it in the browser).
2. Inject a file input, get its uid, and push files from disk:
   ```js
   // evaluate_script: create a visible-ish file input so it appears in the a11y snapshot
   const el=document.createElement('input'); el.type='file'; el.id='__up';
   el.setAttribute('aria-label','upload probe'); el.style.cssText='position:fixed;top:0;left:0;z-index:99999';
   document.body.appendChild(el);
   ```
   - `take_snapshot({filePath: "<repo>/tmp/snap.txt"})` then `grep` the file for `"upload probe"` to get the `uid` (the snapshot is huge — save to file, don't dump to context).
   - **`upload_file` only accepts paths inside a workspace root** (the repo). Copy the
     PNGs into a temp dir *inside the repo* (e.g. `<repo>/.diagram_upload_tmp/`), upload
     from there, and `rm -rf` it afterwards.
3. For each file: `upload_file({uid, filePath})` then `evaluate_script` to POST it
   same-origin (the browser reads bytes from disk; nothing flows through the model):
   ```js
   async () => {
     const f = document.getElementById('__up').files[0];
     const fd = new FormData();
     fd.append('file', f, 'diagram-1.png');   // <- the attachment filename
     fd.append('minorEdit','true');
     const r = await fetch('/wiki/rest/api/content/<PAGE_ID>/child/attachment',
       {method:'POST', headers:{'X-Atlassian-Token':'no-check'}, credentials:'include', body:fd});
     return {status:r.status};   // 200 = ok
   }
   ```
   (Uploading a new file to the same input replaces `files[0]`, so POST after each upload.)

### 2c. Swap the code macros for image macros (edit storage via browser fetch)
The MCP `update*` tools don't accept raw storage macros, and the HTML format rejects
`<ac:image>` / `id` attributes. Edit the **storage format directly** through the
authenticated browser instead:
```js
async () => {
  const id='<PAGE_ID>';
  const g = await (await fetch(`/wiki/rest/api/content/${id}?expand=body.storage,version`,{credentials:'include'})).json();
  let s = g.body.storage.value; const ver = g.version.number; const title = g.title;
  const imgs = ['diagram-1.png','diagram-2.png','diagram-3.png','diagram-4.png'];
  let i = 0;
  // replace ONLY mermaid code macros (leave plain/json code macros alone), in document order
  s = s.replace(/<ac:structured-macro[^>]*ac:name="code"[\s\S]*?<\/ac:structured-macro>/g,
    m => m.includes('>mermaid<')
      ? `<ac:image ac:align="center" ac:layout="center" ac:width="820"><ri:attachment ri:filename="${imgs[i++]}"/></ac:image>`
      : m);
  const put = await fetch(`/wiki/rest/api/content/${id}`, {
    method:'PUT', headers:{'Content-Type':'application/json','X-Atlassian-Token':'no-check'}, credentials:'include',
    body: JSON.stringify({id, type:'page', title, version:{number: ver+1, message:'Embed diagrams'},
      body:{storage:{value:s, representation:'storage'}}})});
  return {replaced:i, putStatus: put.status};
}
```
`ac:width="820"` keeps wide diagrams within the page. If you experimented with SVGs
first, delete the orphaned `.svg` attachments afterward (`GET .../child/attachment`,
then `DELETE /wiki/rest/api/content/<attachmentId>` for each).

## 3. Verify (don't assume)

Reload the page in the browser and check with `evaluate_script`:
- **Links:** every `§`-link's `href` fragment, URL-decoded, matches some element `id`:
  ```js
  const ids = new Set([...document.querySelectorAll('[id]')].map(e=>e.id));
  [...document.querySelectorAll('a[href*="#"]')].filter(a=>/^\s*§\d/.test(a.textContent))
    .filter(a=>{const f=decodeURIComponent(a.getAttribute('href').split('#')[1]||''); return !ids.has(f);});
  // -> should be empty
  ```
- **Diagrams:** Confluence lazy-loads media via blob URLs (filenames won't appear in
  `img.src`), so scroll each diagram into view (`heading.scrollIntoView()`, wait ~2.5s)
  and confirm large rendered `<img>`s (`offsetWidth>300 && offsetHeight>80`); take a
  screenshot of one to eyeball quality. Also confirm no `flowchart`/`erDiagram` source text remains.

## Quick checklist
1. Find cloudId / spaceId / parent folder.
2. Generate a Confluence-anchored copy of the Markdown (percent-encoded fragments); keep the GitHub-anchored original in the repo.
3. `createConfluencePage` (status `current`, markdown).
4. Render Mermaid → quantized PNG; upload via browser `upload_file` + attachment POST (files inside repo workspace).
5. Edit storage via browser fetch: replace mermaid code macros with `<ac:image>`.
6. Reload + verify links resolve and diagrams render; clean up temp files / orphaned attachments / test pages.
