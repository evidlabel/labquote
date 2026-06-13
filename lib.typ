// =============================================================
// labquote — classical · legal · scientific quotation system
// sources: hayagriva YAML (compatible with Typst native bibliography)
//          as produced by `evid` with namespaced keys (e.g. "0001:dolor").
// usage:
//   #import "@preview/labquote:0.1.0": *
//   #setup(yaml("refs.yml"))            // hayagriva YAML
//   // or: #setup-bib(read("refs.bib")) // biblatex
//
//   #q("key", pin: "p. 42")[exact text]
//   #blockq("key", pin: "¶ 17")[body]
//   #cite-ref("key", pin: "…")          bare inline cite
//   #id(pin: "…")                       legal Id. (auto-tracks last cite)
//   #bibliography-custom()              styled back-page
//
// design intent — two complementary surfaces for one quote:
//   • bibliography (back-page): convenience for the LARGER CONTEXT. It reprints
//     the whole stored passage and italicises the in-text slice, so a reader can
//     confirm the quotation is faithful WITHOUT leaving the document. Gather
//     generously into the entry so the full passage settles any out-of-context
//     doubt on the page.
//   • blockquote / inline (in-text): convenience for READABILITY. Slice with
//     start:/end: down to only what serves the local point, and use accent:
//     to highlight the load-bearing words inline. The back-page holds the
//     context; the in-text quote stays short and pointed.
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
#let _norm-author(a) = {
  if type(a) == array {
    if a.len() == 0 { return "Anon." }
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
      author: _norm-author(entry.at("author", default: "Anon.")),
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
      author: e.at("author", default: "Anon."),
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

// ---------- DOC/QUOTE INDEX MAPS ----------
// Computed from sources insertion order (= bib file order).
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

// ---------- STORE + SETUP ----------
// Single state holding normalised sources and their precomputed index maps.
#let _store = state("labquote-store", none)

#let _build(sources, blockquote-indent, blockquote-style) = (
  sources: sources,
  doc-indices: _compute-doc-indices(sources),
  quote-indices: _compute-quote-indices(sources),
  blockquote-indent: blockquote-indent,
  blockquote-style: blockquote-style,
)

// Public: register the bibliography. Call once, near the top of the document,
// before any quote/cite/bibliography call.
// blockquote-indent: left inset of block quotes from the margin.
// blockquote-style: default look for block quotes — "bracket" (top + left rule,
//   the default), "box" (full border), or "fill" (filled background). Each
//   #blockq call may override with its own `style:` argument.
#let setup(data, blockquote-indent: 1em, blockquote-style: "bracket") = _store.update(_build(_normalize-hayagriva(data), blockquote-indent, blockquote-style))
#let setup-bib(src, blockquote-indent: 1em, blockquote-style: "bracket") = _store.update(_build(_normalize-bib(src), blockquote-indent, blockquote-style))

// ---------- INTERNALS ----------
#let _last-name(author) = {
  if author.contains(",") { author.split(",").at(0).trim() }
  else { author.split(" ").last() }
}
#let _last-cite = state("_last-cite-key", none)

// Format key as "d1, q2" content (or "d1" for :main / un-indexed).
#let _dq(store, key) = {
  let prefix = key.split(":").at(0)
  let d = store.doc-indices.at(prefix)
  if key in store.quote-indices {
    let q-i = store.quote-indices.at(key)
    [d#d, q#q-i]
  } else {
    [d#d]
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
  context {
    let store = _store.get()
    link(label(key))[#text(size: 0.85em, tracking: 0.02em)[\[#_dq(store, key)#if pin != none [: #pin]\]]]
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

// ---------- BLOCK QUOTE ----------
// style: "bracket" (top + left rule, the default), "box" (full border) or
//   "fill" (filled background). Defaults to the document-wide value set in
//   setup(blockquote-style: …); pass `style:` here to override per quote.
#let blockq(key, ..args) = {
  _record-slice(key, args.named().at("start", default: none), args.named().at("end", default: none))
  _last-cite.update(key)
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
#let bibliography-custom(brief: false, new-page: true) = context {
  let store = _store.get()
  if new-page { pagebreak(weak: true) }
  heading(level: 1, numbering: none)[References]
  v(0.3em)
  line(length: 4em, stroke: 0.6pt + black)
  v(0.6em)
  let groups = _group-sources(store)
  // order docs by their d-index (= file order, stable & predictable)
  let prefixes = groups.keys().sorted(key: p => store.doc-indices.at(p))
  let marker(content) = box[#text(size: 0.85em, tracking: 0.02em, fill: rgb("#3a3a3a"))[\[#content\]]]

  for prefix in prefixes {
    let aliases = groups.at(prefix)
    let has-main = (prefix + ":main") in aliases
    let canon-key = if has-main { prefix + ":main" } else { aliases.first() }
    let s = store.sources.at(canon-key)
    let author = s.author
    if author.ends-with(".") { author = author.slice(0, -1) }
    let d-idx = store.doc-indices.at(prefix)
    // Title: use canon's title if :main exists; else fall back to parent.title (container)
    let doc-title = if has-main { s.title } else if s.container != none { s.container } else { s.title }
    // Label: :main key if exists; else prefix-only synthetic label (avoids collision with quote sub-entries)
    let doc-label = if has-main { canon-key } else { prefix }

    // ---- doc-level entry ----
    block(below: 0.35em)[
      #set par(hanging-indent: 2.4em, justify: false, leading: 0.55em)
      #text(size: 0.95em)[
        #marker[d#d-idx]#h(0.6em)#smallcaps(author).#h(0.3em)\(#s.year\).#h(0.3em)#emph(doc-title).#if s.publisher != none [#h(0.3em)#(s.publisher).]#if s.doi != none [#h(0.3em)DOI:~#link("https://doi.org/" + s.doi)[#s.doi].]
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

    // ---- quote sub-entries (ordered by q-index) ----
    let quote-keys = aliases
      .filter(k => k in store.quote-indices)
      .sorted(key: k => store.quote-indices.at(k))
    if brief {
      // compact: one row of [q#] markers (with pins), each anchoring its key.
      if quote-keys.len() > 0 {
        block(below: 0.6em, inset: (left: 2.4em))[
          #set par(justify: false, leading: 0.55em)
          #for (i, qk) in quote-keys.enumerate() {
            let q-idx = store.quote-indices.at(qk)
            let pin = store.sources.at(qk).at("pin", default: none)
            [#marker[q#q-idx]#if pin != none [#text(size: 0.78em, fill: rgb("#7a7a7a"))[~(#pin)]]#box(width: 0pt)[]#label(qk)#if i < quote-keys.len() - 1 [#h(0.6em)]]
          }
        ]
      }
    } else {
      for qk in quote-keys {
        let qs = store.sources.at(qk)
        let q-idx = store.quote-indices.at(qk)
        let pin = qs.at("pin", default: none)
        block(below: 1.1em, inset: (left: 2em))[
          #set par(hanging-indent: 2.4em, justify: false, leading: 0.55em)
          #let slices = _slices.get().at(qk, default: ())
          #let rendered = _render-with-emph(qs.title, slices)
          #text(size: 0.88em)[
            #marker[q#q-idx]#h(0.6em)"#rendered"#if pin != none [#h(0.4em)#text(fill: rgb("#7a7a7a"))[(#pin)]]
          ]
          #box(width: 0pt)[]#label(qk)
        ]
      }
    }
    v(0.8em)
  }
}
