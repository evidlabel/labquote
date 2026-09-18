// =============================================================
// labquote — classical · legal · scientific quotation system
// sources: hayagriva YAML (compatible with Typst native bibliography)
//          as produced by `evid` with namespaced keys (e.g. "0001:dolor").
// usage:
//   #import "@preview/labquote:0.1.0": *
//   #setup(yaml("refs.yml"))            // hayagriva YAML
//   #setup(yaml("refs.yml"), cite-brief: true)  // [d1,2] instead of [d1, q2]
//   // or: #setup-bib(read("refs.bib")) // biblatex
//
// numbering: d/q indices are assigned in ORDER OF APPEARANCE in the rendered
//   text (first cite-ref/q/blockq of a doc → d1, next new doc → d2, …); the
//   bibliography is ordered to match. Only entries actually cited in the text
//   are printed — uncited docs/quotes in the bib data are omitted. Never
//   hand-assign d/q numbers.
//
//   #q("key", pin: "p. 42")[exact text]
//   #inlineq("key", mark: ("brace", "italic"))  inline quote + superscript cite
//   #blockq("key", pin: "¶ 17")[body]
//   #cite-ref("key", pin: "…")          bare inline cite
//   #multicite(("k1","k2"))             several cites in one bracket: [1a,1b]
//   #multicite(("k1","k2"), mode: "dash")
//                                       adjacent same-doc cites dash-joined:
//                                       [1a-b] instead of [1a,1b]
//   #id(pin: "…")                       legal Id. (auto-tracks last cite)
//   #bibliography-custom()              styled back-page
//
// design intent — three nested contexts for one quote:
//   • in-text (blockquote / inline): only the snippet that supports the local
//     point. Slice with start:/end:; accent: for load-bearing words.
//   • bibliography (back-page): a bit WIDER CONTEXT. Reprints the stored
//     title: and italicises the in-text slice, plus the :main URL, so a reader
//     can confirm the quotation is faithful WITHOUT leaving the document.
//     Gather generously into the entry so the passage settles out-of-context
//     doubt on the page.
//   • URL: the widest context — the full document at the :main url.
// =============================================================

// ---------- SHARED HELPERS ----------
// Format page-range field for pin display.
// "2" → "p. 2"; "412-451" → "pp. 412-451"
#let _format-pages(p) = {
  if p == none or p == "" { return none }
  let pn = str(p).trim()
  if pn.contains("-") or pn.contains("–") { return "pp. " + pn }
  return "p. " + pn
}

// ---------- HAYAGRIVA NORMALISERS ----------
// Placeholder for a source with no author. Never "Anon.", which reads as a
// real surname in the bibliography and in inline cites.
#let _no-author = "[no_author]"

#let _norm-author(a) = {
  if type(a) == array {
    if a.len() == 0 { return _no-author }
    return _norm-author(a.at(0))
  }
  if type(a) == dictionary {
    let surname = a.at("name", default: "")
    let given = a.at("given-name", default: "")
    if given != "" { return surname + ", " + given }
    return surname
  }
  return a
}

#let _norm-year(entry) = {
  if "date" not in entry { return "n.d." }
  let d = entry.date
  if type(d) == datetime { return str(d.year()) }
  let s = str(d)
  if s.len() >= 4 { return s.slice(0, 4) }
  return s
}

#let _norm-url(entry) = {
  if "url" not in entry { return none }
  let u = entry.url
  if type(u) == dictionary { return u.at("value", default: none) }
  return u
}

#let _norm-publisher(entry) = {
  if "publisher" not in entry { return none }
  let p = entry.publisher
  if type(p) == dictionary { return p.at("name", default: "") }
  return p
}

#let _norm-container(entry) = {
  if "parent" not in entry { return none }
  let p = entry.parent
  if type(p) == dictionary {
    let title = p.at("title", default: "")
    let vol = p.at("volume", default: none)
    let iss = p.at("issue", default: none)
    let s = title
    if vol != none { s += " " + str(vol) }
    if iss != none { s += "(" + str(iss) + ")" }
    return s
  }
  return p
}

#let _norm-doi(entry) = {
  if "serial-number" not in entry { return none }
  let sn = entry.serial-number
  if type(sn) == dictionary { return sn.at("doi", default: none) }
  return none
}

// Normalise a raw hayagriva dict (e.g. from `yaml("refs.yml")`) into our schema.
#let _normalize-hayagriva(raw) = {
  let out = (:)
  for (key, entry) in raw {
    out.insert(str(key), (
      author: _norm-author(entry.at("author", default: _no-author)),
      // collapse hard line-wrap whitespace from PDF/text extraction so quote
      // bodies reflow (mirrors the .bib path's ws-rx normalisation)
      title: entry.at("title", default: "").replace(regex("\s+"), " ").trim(),
      year: _norm-year(entry),
      publisher: _norm-publisher(entry),
      container: _norm-container(entry),
      url: _norm-url(entry),
      doi: _norm-doi(entry),
      pin: _format-pages(entry.at("page-range", default: entry.at("pages", default: none))),
    ))
  }
  return out
}

// ---------- BIBLATEX (.bib) NORMALISERS ----------
// Flat-field parser: handles biblatex-style entries without nested braces in values.
#let _parse-bib(src) = {
  let entry-rx = regex("(?s)@(\w+)\s*\{\s*([^,\s]+)\s*,(.*?)\n\}")
  let field-rx = regex("(?ms)^\s*([a-zA-Z][a-zA-Z_-]*)\s*=\s*\{([^}]*)\}\s*,?\s*$")
  let ws-rx = regex("\s+")
  let entries = (:)
  for m in src.matches(entry-rx) {
    let key = m.captures.at(1)
    let body = m.captures.at(2)
    let fields = (:)
    for fm in body.matches(field-rx) {
      let name = fm.captures.at(0).trim()
      let value = fm.captures.at(1).replace(ws-rx, " ").trim()
      fields.insert(name, value)
    }
    entries.insert(key, fields)
  }
  entries
}

// Normalise a raw biblatex string (e.g. from `read("refs.bib")`) into our schema.
#let _normalize-bib(src) = {
  let raw = _parse-bib(src)
  let out = (:)
  for (key, e) in raw {
    let date = e.at("date", default: e.at("year", default: ""))
    let year = if date.len() >= 4 { date.slice(0, 4) } else { date }
    out.insert(key, (
      author: e.at("author", default: _no-author),
      title: e.at("title", default: ""),
      year: year,
      publisher: e.at("publisher", default: none),
      container: e.at("journal", default: e.at("booktitle", default: none)),
      url: e.at("url", default: none),
      doi: e.at("doi", default: none),
      pin: _format-pages(e.at("pages", default: none)),
    ))
  }
  out
}

// ---------- DOC/QUOTE INDEX MAPS (LEGACY, file order) ----------
// Kept for backward compatibility only. Displayed d/q numbers are now assigned
// in ORDER OF APPEARANCE (see _doc-index-map / _quote-index-map and the
// _cited-docs / _cited-quotes state below); these file-order maps are no longer
// read for rendering.
// doc index per prefix (e.g. "0088" → 1, "0115" → 2)
// quote index per non-:main key, scoped to its prefix
#let _compute-doc-indices(sources) = {
  let out = (:)
  let i = 1
  for k in sources.keys() {
    let prefix = k.split(":").at(0)
    if prefix not in out {
      out.insert(prefix, i)
      i += 1
    }
  }
  out
}
#let _compute-quote-indices(sources) = {
  let out = (:)
  let counters = (:)
  for k in sources.keys() {
    let parts = k.split(":")
    let prefix = parts.at(0)
    let suffix = if parts.len() > 1 { parts.at(1) } else { "main" }
    if suffix == "main" { continue }
    let n = counters.at(prefix, default: 0) + 1
    counters.insert(prefix, n)
    out.insert(k, n)
  }
  out
}

// ---------- ORDER-OF-APPEARANCE INDEX MAPS ----------
// d/q numbers follow first appearance in the rendered text (cite-ref/q/blockq),
// not bib file order. `appeared` is the accumulated list of prefixes (docs) or
// keys (quotes) in citation order; any store entries never cited are appended
// afterwards in file order so the bibliography still numbers them stably.
#let _doc-index-map(store, appeared) = {
  let out = (:)
  let i = 1
  for prefix in appeared {
    if prefix not in out { out.insert(prefix, i); i += 1 }
  }
  for k in store.sources.keys() {
    let prefix = k.split(":").at(0)
    if prefix not in out { out.insert(prefix, i); i += 1 }
  }
  out
}
#let _quote-index-map(store, appeared) = {
  let out = (:)
  let counters = (:)
  for k in appeared {
    if k not in out {
      let prefix = k.split(":").at(0)
      let n = counters.at(prefix, default: 0) + 1
      counters.insert(prefix, n)
      out.insert(k, n)
    }
  }
  for k in store.sources.keys() {
    let parts = k.split(":")
    if parts.len() > 1 and parts.at(1) != "main" and k not in out {
      let prefix = parts.at(0)
      let n = counters.at(prefix, default: 0) + 1
      counters.insert(prefix, n)
      out.insert(k, n)
    }
  }
  out
}

// ---------- STORE + SETUP ----------
// Single state holding normalised sources and their precomputed index maps.
#let _store = state("labquote-store", none)

#let _build(sources, blockquote-indent, blockquote-style, cite-brief, cite-style) = (
  sources: sources,
  doc-indices: _compute-doc-indices(sources),
  quote-indices: _compute-quote-indices(sources),
  blockquote-indent: blockquote-indent,
  blockquote-style: blockquote-style,
  cite-brief: cite-brief,
  cite-style: cite-style,
)

// Public: register the bibliography. Call once, near the top of the document,
// before any quote/cite/bibliography call.
// blockquote-indent: left inset of block quotes from the margin.
// blockquote-style: default look for block quotes — "bracket" (top + left rule,
//   the default), "box" (full border), or "fill" (filled background). Each
//   #blockq call may override with its own `style:` argument.
// cite-style: inline cite format —
//   "full"  → [d1, q2]   (default)
//   "brief" → [d1,2]
//   "short" → [1b]       (doc number + quote letter; bibliography markers follow)
//   left as `auto`, it follows the legacy `cite-brief` boolean ("brief"/"full").
#let setup(data, blockquote-indent: 1em, blockquote-style: "bracket", cite-brief: false, cite-style: auto) = _store.update(_build(_normalize-hayagriva(data), blockquote-indent, blockquote-style, cite-brief, cite-style))
#let setup-bib(src, blockquote-indent: 1em, blockquote-style: "bracket", cite-brief: false, cite-style: auto) = _store.update(_build(_normalize-bib(src), blockquote-indent, blockquote-style, cite-brief, cite-style))

// ---------- INTERNALS ----------
// Corporate/legal-form tokens that are not a usable short name on their own.
#let _org-suffixes = (
  "a/s", "aps", "ivs", "i/s", "k/s", "ltd", "llc", "inc", "gmbh", "ag",
  "ab", "as", "oy", "oyj", "sa", "bv", "nv", "plc", "co", "corp",
)
#let _last-name(author) = {
  if author.contains(",") { return author.split(",").at(0).trim() }
  let toks = author.split(" ").filter(t => t != "")
  if toks.len() == 0 { return author }
  let tail = lower(toks.last()).replace(".", "")
  // "Northwind Supplies A/S" -> "Northwind Supplies", not "A/S".
  if tail in _org-suffixes and toks.len() > 1 {
    return toks.slice(0, toks.len() - 1).join(" ")
  }
  toks.last()
}
#let _last-cite = state("_last-cite-key", none)

// Accumulated first-appearance order of cited docs (prefixes) and quotes (keys).
#let _cited-docs = state("labquote-cited-docs", ())
#let _cited-quotes = state("labquote-cited-quotes", ())
// Record a cite at its point of appearance (append-if-absent → stable order).
#let _register(key) = {
  let parts = key.split(":")
  let prefix = parts.at(0)
  _cited-docs.update(d => if prefix in d { d } else { d + (prefix,) })
  if parts.len() > 1 and parts.at(1) != "main" {
    _cited-quotes.update(q => if key in q { q } else { q + (key,) })
  }
}

// Resolve the effective inline cite style: explicit cite-style wins; else the
// legacy cite-brief boolean ("brief"/"full").
#let _resolve-style(store) = {
  let s = store.at("cite-style", default: auto)
  if s != auto { return s }
  if store.at("cite-brief", default: false) { "brief" } else { "full" }
}

// Format key as bracket-free cite content per style (no surrounding [ ]):
//   full  → "d1, q2"   brief → "d1,2"   short → "1b"   (:main / un-indexed → "d1" / "1")
// Indices follow order of appearance. Call inside a context (reads .final()).
#let _dq(store, key) = {
  let prefix = key.split(":").at(0)
  let di = _doc-index-map(store, _cited-docs.final())
  let d = di.at(prefix)
  let qi = _quote-index-map(store, _cited-quotes.final())
  let style = _resolve-style(store)
  let has-q = key in qi
  if style == "short" {
    if has-q { [#d#numbering("a", qi.at(key))] } else { [#d] }
  } else if style == "brief" {
    if has-q { [d#d,#(qi.at(key))] } else { [d#d] }
  } else {
    if has-q { [d#d, q#(qi.at(key))] } else { [d#d] }
  }
}

// Resolve pin: explicit arg wins; otherwise pull from entry (bib `pages`).
#let _pin(store, key, pin) = {
  if pin != none { return pin }
  store.sources.at(key).at("pin", default: none)
}

// ---------- INLINE CITATION ----------
// [d1, q2]  — clickable → bibliography anchor
// pin (if explicitly passed) appended: [d1, q2: pin]
#let cite-ref(key, pin: none) = {
  _last-cite.update(key)
  _register(key)
  context {
    let store = _store.get()
    link(label(key))[#text(size: 0.85em, tracking: 0.02em)[\[#_dq(store, key)#if pin != none [: #pin]\]]]
  }
}

// ---------- MULTI CITATION ----------
// One pair of brackets around several cites: [1a,1b,2a] (short), or
// [d1, q1; d2, q1] in full/brief. Each token links to its own bib anchor.
// `keys`: an array of keys, e.g. #multicite(("0157:a", "0157:b", "0301:a")).
// mode: "list" (default) → every cite separated by the style's separator.
//       "dash"            → runs of *adjacent* same-doc cites (same prefix and
//                           consecutive quote indices) are joined with "-" so
//                           several quotes from one document stay brief inline:
//                           #multicite(("0157:a", "0157:b", "0301:a"), mode: "dash")
//                           → short [1a-b, 2a] · brief [d1,1-2] · full [d1, q1-2]
//                           Non-consecutive same-doc quotes stay separate tokens
//                           ([1a, 1c]); keys without a quote index (:main) render
//                           as plain doc cites and break adjacency. Each run
//                           links to its first key; register order is unchanged.
#let multicite(keys, pin: none, mode: "list") = {
  // Accept a bare string (single key) as well as an array — `("k")` is a
  // parenthesised string in Typst, not a 1-tuple, so this avoids a footgun.
  let keys = if type(keys) == str { (keys,) } else { keys }
  for k in keys { _register(k) }
  if keys.len() > 0 { _last-cite.update(keys.last()) }
  if mode != "dash" {
    context {
      let store = _store.get()
      // short style is unambiguous with "," ; full/brief tokens already contain
      // commas, so separate those with "; " instead.
      let sep = if _resolve-style(store) == "short" { ", " } else { "; " }
      let toks = keys.map(k => link(label(k))[#_dq(store, k)])
      text(size: 0.85em, tracking: 0.02em)[\[#toks.join(sep)#if pin != none [: #pin]\]]
    }
    return
  }
  // dash mode: split the keys into runs of *adjacent* cites from the same doc
  // (same prefix AND consecutive quote indices), then join each run's
  // quote-index tails with "-". Keys without a quote index (:main) render as
  // plain doc cites and break adjacency.
  context {
    let store = _store.get()
    let style = _resolve-style(store)
    let di = _doc-index-map(store, _cited-docs.final())
    let qi = _quote-index-map(store, _cited-quotes.final())
    let tail(k) = if k in qi { qi.at(k) } else { none }
    // split into runs
    let runs = ()
    for k in keys {
      let prefix = k.split(":").at(0)
      let t = tail(k)
      let brk = runs.len() == 0
      if not brk {
        let prev = runs.last()
        brk = prev.prefix != prefix or prev.last-tail == none or t == none or t != prev.last-tail + 1
      }
      if brk { runs.push((prefix: prefix, keys: (k,), last-tail: t)) }
      else {
        runs.last().keys.push(k)
        runs.last().last-tail = t
      }
    }
    // render one token per run
    let tailstr(k) = if style == "short" { numbering("a", qi.at(k)) } else { str(qi.at(k)) }
    let toks = runs.map(r => {
      let first = r.keys.first()
      if r.keys.len() == 1 { return link(label(first))[#_dq(store, first)] }
      // multi-key run: doc part + dash-joined tails, formatted per style
      let d = di.at(r.prefix)
      let tails = r.keys.map(tailstr).join("-")
      let body = if style == "short" {
        [#d#tails]
      } else if style == "brief" {
        [d#d,#tails]
      } else {
        [d#d, q#tails]
      }
      link(label(first))[#body]
    })
    let sep = if style == "short" { ", " } else { "; " }
    text(size: 0.85em, tracking: 0.02em)[\[#toks.join(sep)#if pin != none [: #pin]\]]
  }
}

// ---------- QUOTE SLICING ----------
// Slice entry's quote text using start/end markers; add … if content was cut.
#let _slice-quote(s, start: none, end: none) = {
  let body = s
  let prefix = ""
  let suffix = ""
  if start != none {
    let parts = body.split(start)
    if parts.len() > 1 {
      let before = parts.at(0)
      body = start + parts.slice(1).join(start)
      if before.trim() != "" { prefix = "… " }
    }
  }
  if end != none {
    let parts = body.split(end)
    if parts.len() > 1 {
      body = parts.at(0) + end
      let after = parts.slice(1).join(end)
      if after.trim() != "" { suffix = " …" }
    }
  }
  prefix + body + suffix
}

// Track which slices were used per key — bib italicizes matching ranges.
#let _slices = state("quote-slices", (:))
#let _record-slice(key, start, end) = {
  if start == none and end == none { return }
  _slices.update(d => {
    let existing = d.at(key, default: ())
    let new-list = existing + ((start, end),)
    let new-d = d
    new-d.insert(key, new-list)
    new-d
  })
}

// Render a string with substrings (defined by (start, end) marker pairs) italicized.
#let _render-with-emph(s, slices) = {
  if slices.len() == 0 { return s }
  let ranges = ()
  for sl in slices {
    let start = sl.at(0)
    let end-marker = sl.at(1)
    let start-pos = 0
    if start != none {
      let parts = s.split(start)
      if parts.len() > 1 { start-pos = parts.at(0).len() }
    }
    let end-pos = s.len()
    if end-marker != none {
      let parts = s.split(end-marker)
      if parts.len() > 1 { end-pos = parts.at(0).len() + end-marker.len() }
    }
    if end-pos > start-pos { ranges.push((start-pos, end-pos)) }
  }
  ranges = ranges.sorted(key: r => r.at(0))
  let out = []
  let pos = 0
  for r in ranges {
    let rs = r.at(0)
    let re = r.at(1)
    if rs > pos { out += [#s.slice(pos, rs)] }
    let actual-start = calc.max(rs, pos)
    if re > actual-start {
      out += emph(s.slice(actual-start, re))
      pos = re
    }
  }
  if pos < s.len() { out += [#s.slice(pos, s.len())] }
  out
}

// Map an accent style name to the function that wraps the matched span.
// Unknown / missing style falls back to italic (emph).
#let _wrap-fn(style) = {
  if style == "bold" { strong }
  else if style == "underline" { underline }
  else { emph }   // "italic" and any unrecognised value
}

// Render a verbatim string with author-chosen substrings accentuated inline.
// `pairs`: a list of (substring, style) tuples, style ∈ "italic"|"bold"|"underline".
// A lone pair (("foo", "italic") passed as ("foo","italic")) is accepted too.
// Every non-overlapping occurrence of each substring is wrapped; where ranges
// overlap, the earlier-starting one wins (the overlapped span is not re-wrapped).
// Substrings are matched verbatim against the (already sliced + whitespace-
// normalised) body — same matching idiom as start:/end:. Not found ⇒ no-op.
#let _render-with-accents(s, pairs) = {
  // normalise the shorthand `("foo","italic")` → `(("foo","italic"),)`
  let plist = if pairs.len() == 2 and type(pairs.at(0)) == str and type(pairs.at(1)) == str {
    (pairs,)
  } else { pairs }
  // collect (start, end, wrap-fn) for every non-overlapping occurrence of each sub
  let ranges = ()
  for p in plist {
    let sub = p.at(0)
    if sub == none or sub == "" { continue }
    let wrap = _wrap-fn(p.at(1, default: "italic"))
    let parts = s.split(sub)
    if parts.len() <= 1 { continue }   // not present
    let pos = 0
    for (i, before) in parts.enumerate() {
      if i == parts.len() - 1 { break }   // text after the last match, no occurrence follows
      let st = pos + before.len()
      ranges.push((st, st + sub.len(), wrap))
      pos = st + sub.len()
    }
  }
  if ranges.len() == 0 { return s }
  ranges = ranges.sorted(key: r => r.at(0))
  let out = []
  let pos = 0
  for r in ranges {
    let rs = r.at(0)
    let re = r.at(1)
    if re <= pos { continue }            // fully inside an already-wrapped range
    let actual-start = calc.max(rs, pos)
    if actual-start > pos { out += [#s.slice(pos, actual-start)] }
    out += (r.at(2))(s.slice(actual-start, re))
    pos = re
  }
  if pos < s.len() { out += [#s.slice(pos, s.len())] }
  out
}

// Resolve body: explicit positional/named wins; else slice entry text by start/end; else full entry text.
#let _resolve-body(store, key, args) = {
  let pos = args.pos()
  let body = if pos.len() > 0 { pos.at(0) } else { args.named().at("body", default: auto) }
  let start = args.named().at("start", default: none)
  let end = args.named().at("end", default: none)
  if body != auto and body != none { return body }
  let qtext = store.sources.at(key).at("title", default: "")
  if start != none or end != none {
    qtext = _slice-quote(qtext, start: start, end: end)
  }
  // author-chosen inline emphasis: italic / bold / underline of verbatim substrings
  let accent = args.named().at("accent", default: none)
  if accent != none and accent.len() > 0 {
    return _render-with-accents(qtext, accent)
  }
  qtext
}

// ---------- INLINE QUOTE ----------
// #q("key")                          full text from entry
// #q("key", start: "X", end: "Y")    sliced
// #q("key")[explicit body]           explicit (backward compat)
// #q("key", accent: (("foo", "bold"), ("bar", "italic")))
//                                    highlight verbatim substrings inline
//                                    (style ∈ "italic"|"bold"|"underline";
//                                     all occurrences; ignored for explicit body)
#let q(key, ..args) = {
  _record-slice(key, args.named().at("start", default: none), args.named().at("end", default: none))
  let pin = args.named().at("pin", default: none)
  context {
    let store = _store.get()
    let body = _resolve-body(store, key, args)
    ["#body"]
    h(0.15em)
  }
  cite-ref(key, pin: pin)
}

// Visually distinguish an inline quote body. `mark` is a single token or an
// array of tokens that compose:
//   wrapper (pick one; default "quote") —
//     "quote"  → "…" typographic quotation marks (default)
//     "brace"  → { … } curly braces
//     "plain"  → no surrounding marks (use with a text treatment below)
//   text treatment (any combination, layered) —
//     "italic" · "underline" · "color" (a slight blue tint)
//   modifier —
//     "ellipsis" → a leading "… " to signal the quote opens mid-sentence
// e.g. mark: "italic" · mark: ("brace", "color") · mark: ("plain", "underline", "ellipsis")
#let _distinguish(body, mark) = {
  let marks = if mark == none { ("quote",) } else if type(mark) == str { (mark,) } else { mark }
  // layered text treatments
  let content = body
  if "italic" in marks { content = emph(content) }
  if "underline" in marks { content = underline(content) }
  if "color" in marks { content = text(fill: rgb("#2a4a7a"), content) }
  // leading ellipsis (mid-sentence opener)
  let lead = if "ellipsis" in marks { [… ] } else { [] }
  let inner = [#lead#content]
  // wrapper — quotes by default; "plain" or "brace" opt out / swap
  if "brace" in marks { [{#inner}] }
  else if "plain" in marks or "none" in marks { inner }
  else { ["#inner"] }
}

// ---------- INLINE QUOTE WITH SUPERSCRIPT ----------
// Like #q, but the quote reads as part of the running sentence and the citation
// trails as a single clickable SUPERSCRIPT carrying author · year · d/q index
// (· pin) — unobtrusive, footnote-style, instead of #q's bracketed [d1, q2].
// #inlineq("key")                          full entry text, inline
// #inlineq("key", start: "X", end: "Y")    sliced (same idiom as #q)
// #inlineq("key")[explicit body]           explicit body
// #inlineq("key", accent: …)               inline accents (same as #q)
// #inlineq("key", pin: "p. 5")             pin appended inside the superscript
// #inlineq("key", mark: ("brace", "italic"))  distinguish the quote (see _distinguish)
#let inlineq(key, ..args) = {
  _record-slice(key, args.named().at("start", default: none), args.named().at("end", default: none))
  _last-cite.update(key)
  _register(key)
  let pin = args.named().at("pin", default: none)
  let mark = args.named().at("mark", default: none)
  context {
    let store = _store.get()
    let body = _resolve-body(store, key, args)
    let s = store.sources.at(key)
    let p = _pin(store, key, pin)
    let has-url = s.url != none
    _distinguish(body, mark)
    // The whole attribution (author · year · d/q ref · pin · ↗) trails the quote
    // as a single clickable superscript pointing at the back-page entry. Wrapped
    // in one box so the link annotation is a single rectangle whose height
    // covers the raised superscript (otherwise the per-run link rect sits at the
    // baseline, below the superscript glyphs).
    link(label(key), box(super(text(tracking: 0.02em, fill: rgb("#3a3a3a"))[#smallcaps(_last-name(s.author))#h(0.3em)#s.year#h(0.3em)#sym.dot.c#h(0.3em)#_dq(store, key)#if p != none [#h(0.3em)#sym.dot.c#h(0.3em)#p]#if has-url [#h(0.25em)#text(fill: rgb("#2a4a7a"))[↗]]])))
  }
}

// ---------- BLOCK QUOTE ----------
// style: "bracket" (top + left rule, the default), "box" (full border) or
//   "fill" (filled background). Defaults to the document-wide value set in
//   setup(blockquote-style: …); pass `style:` here to override per quote.
#let blockq(key, ..args) = {
  _record-slice(key, args.named().at("start", default: none), args.named().at("end", default: none))
  _last-cite.update(key)
  _register(key)
  let pin = args.named().at("pin", default: none)
  context {
    let store = _store.get()
    let body = _resolve-body(store, key, args)
    let s = store.sources.at(key)
    let p = _pin(store, key, pin)
    let has-url = s.url != none
    let style = args.named().at("style", default: store.at("blockquote-style", default: "bracket"))
    let indent = store.at("blockquote-indent", default: 1em)
    let stroke-color = rgb("#141414")
    let stroke-spec = 0.5pt + stroke-color
    let fill-color = rgb("#f3f2ef")
    let attribution = link(label(key))[
      #text(size: 0.78em, tracking: 0.08em, fill: rgb("#3a3a3a"))[
        #smallcaps(_last-name(s.author))#h(0.4em)#sym.dot.c#h(0.4em)#s.year#if p != none [#h(0.4em)#sym.dot.c#h(0.4em)#p]#h(0.4em)#sym.dot.c#h(0.4em)#_dq(store, key)#if has-url [#h(0.45em)#text(fill: rgb("#2a4a7a"))[↗]]
      ]
    ]

    if style == "bracket" {
      let attr-h = measure(attribution).height
      let half = attr-h / 2
      block(
        width: 100%,
        spacing: 1.25em,
        inset: (left: indent),
        {
          set block(spacing: 0pt)
          // header: hairline (col 1, 1fr) + attribution (col 2, auto), horizon-aligned.
          // sticky so the header line never gets orphaned at the bottom of a page —
          // it always travels to the next page together with the start of the body.
          block(sticky: true, grid(
            columns: (1fr, auto),
            align: horizon,
            column-gutter: 0.8em,
            line(length: 100%, stroke: stroke-spec),
            attribution,
          ))
          // pull body up so its top = hairline's top edge (= half - 0.25pt below header top)
          v(-(half + 0.25pt), weak: false)
          // body row: bar (0.5pt fill) + content
          grid(
            columns: (0.5pt, 1fr),
            column-gutter: 1.2em,
            grid.cell(fill: stroke-color)[],
            [
              #v(half + 0.9em, weak: false)
              #set text(size: 0.97em)
              "#body"
            ]
          )
        }
      )
    } else {
      // "box" → full border; "fill" → filled background. Attribution top-right,
      // body below. Indent shifts the whole container in from the left margin.
      block(width: 100%, spacing: 1.25em, inset: (left: indent),
        block(
          width: 100%,
          spacing: 0pt,
          inset: (x: 1em, y: 0.85em),
          radius: 2pt,
          stroke: if style == "box" { stroke-spec } else { none },
          fill: if style == "fill" { fill-color } else { none },
          {
            set block(spacing: 0pt)
            // sticky so the attribution never gets orphaned from the body start
            block(sticky: true, align(right, attribution))
            v(0.5em, weak: false)
            set text(size: 0.97em)
            ["#body"]
          }
        )
      )
    }
  }
}

// ---------- LEGAL "Id." ----------
#let id(pin: none) = context {
  let last = _last-cite.get()
  if last == none {
    text(fill: red)[[id.: no prior cite]]
  } else {
    link(label(last))[
      #text(size: 0.9em, style: "italic")[Id.#if pin != none [ at #pin].]
    ]
  }
}

// ---------- CUSTOM BIBLIOGRAPHY ----------
// Group sibling keys: "0088:historier" and "0088:main" share prefix "0088".
// Renders one entry per group, preferring `<prefix>:main` for source metadata.
// All sibling keys get labels on the same entry so any cite-ref anchors correctly.
#let _group-sources(store) = {
  let groups = (:)
  for k in store.sources.keys() {
    let prefix = k.split(":").at(0)
    let aliases = groups.at(prefix, default: ())
    aliases.push(k)
    groups.insert(prefix, aliases)
  }
  groups
}

// brief: keep the document (d) entries, but list quote (q) items inline as a
// compact row of clickable markers (with pins) instead of repeating each quote.
// Localised bibliography heading by document language (text.lang). Falls back
// to "References". Pass `title:` to override.
#let _bib-titles = (
  en: "References", da: "Referencer", de: "Literatur", fr: "Références",
  es: "Referencias", sv: "Referenser", nb: "Referanser", nn: "Referansar", nl: "Literatuur",
)
#let bibliography-custom(brief: false, new-page: true, title: auto) = context {
  let store = _store.get()
  if new-page { pagebreak(weak: true) }
  let header = if title != auto { title } else { _bib-titles.at(text.lang, default: "References") }
  heading(level: 1, numbering: none)[#header]
  v(0.3em)
  line(length: 100%, stroke: 0.6pt + black)
  v(0.6em)
  let groups = _group-sources(store)
  // appearance-order index maps (cited order, then any uncited in file order)
  let cited-docs = _cited-docs.final()
  let cited-quotes = _cited-quotes.final()
  let di = _doc-index-map(store, cited-docs)
  let qi = _quote-index-map(store, cited-quotes)
  // Only print docs actually cited in the text, ordered by d-index (= order of
  // first appearance). Uncited entries present in the bib data are omitted.
  let prefixes = groups.keys().filter(p => p in cited-docs).sorted(key: p => di.at(p))
  let marker(content) = box[#text(size: 0.85em, tracking: 0.02em, fill: rgb("#3a3a3a"))[\[#content\]]]
  // Bibliography markers follow the inline cite style:
  //   full  → [d1] / [q1]   brief → [d1] / [1]   short → [1] / [a]
  let style = _resolve-style(store)
  let dmark(n) = if style == "short" { marker[#n] } else { marker[d#n] }
  let qmark(n) = if style == "short" { marker[#numbering("a", n)] } else if style == "brief" { marker[#n] } else { marker[q#n] }

  for prefix in prefixes {
    let aliases = groups.at(prefix)
    let has-main = (prefix + ":main") in aliases
    let canon-key = if has-main { prefix + ":main" } else { aliases.first() }
    let s = store.sources.at(canon-key)
    let author = s.author
    if author.ends-with(".") { author = author.slice(0, -1) }
    let d-idx = di.at(prefix)
    // Title: use canon's title if :main exists; else fall back to parent.title (container)
    let doc-title = if has-main { s.title } else if s.container != none { s.container } else { s.title }
    // Label: :main key if exists; else prefix-only synthetic label (avoids collision with quote sub-entries)
    let doc-label = if has-main { canon-key } else { prefix }

    // ---- doc-level entry ----
    block(below: 0.35em)[
      #set par(hanging-indent: 2.4em, justify: false, leading: 0.55em)
      #text(size: 0.95em)[
        #dmark(d-idx)#h(0.6em)#smallcaps(author).#h(0.3em)\(#s.year\).#h(0.3em)#emph(doc-title).#if s.publisher != none [#h(0.3em)#(s.publisher).]#if s.doi != none [#h(0.3em)DOI:~#link("https://doi.org/" + s.doi)[#s.doi].]
      ]
      #box(width: 0pt)[]#label(doc-label)
    ]
    // URL in its own padded block — wraps stay at 2.4em
    if s.url != none {
      block(below: 0.55em, inset: (left: 2.4em))[
        #set par(justify: false, leading: 0.55em)
        #link(s.url)[#text(size: 0.85em, fill: rgb("#1a3a6a"))[#s.url]]
      ]
    }

    // ---- quote sub-entries (only cited quotes, ordered by q-index) ----
    let quote-keys = aliases
      .filter(k => k in cited-quotes)
      .sorted(key: k => qi.at(k))
    if brief {
      // compact: one row of [q#] markers (with pins), each anchoring its key.
      if quote-keys.len() > 0 {
        block(below: 0.6em, inset: (left: 2.4em))[
          #set par(justify: false, leading: 0.55em)
          #for (i, qk) in quote-keys.enumerate() {
            let q-idx = qi.at(qk)
            let pin = store.sources.at(qk).at("pin", default: none)
            [#qmark(q-idx)#if pin != none [#text(size: 0.78em, fill: rgb("#7a7a7a"))[~(#pin)]]#box(width: 0pt)[]#label(qk)#if i < quote-keys.len() - 1 [#h(0.6em)]]
          }
        ]
      }
    } else {
      for qk in quote-keys {
        let qs = store.sources.at(qk)
        let q-idx = qi.at(qk)
        let pin = qs.at("pin", default: none)
        block(below: 1.1em, inset: (left: 2em))[
          #set par(hanging-indent: 2.4em, justify: false, leading: 0.55em)
          #let slices = _slices.get().at(qk, default: ())
          #let rendered = _render-with-emph(qs.title, slices)
          #text(size: 0.88em)[
            #qmark(q-idx)#h(0.6em)"#rendered"#if pin != none [#h(0.4em)#text(fill: rgb("#7a7a7a"))[(#pin)]]
          ]
          #box(width: 0pt)[]#label(qk)
        ]
      }
    }
    v(0.8em)
  }
}
