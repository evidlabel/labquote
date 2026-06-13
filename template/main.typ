#import "@preview/labquote:0.1.0": *
// dev: #import "../lib.typ": *

// ---------- DOCUMENT DEFAULTS ----------
#set page(paper: "a4", margin: (x: 2.6cm, y: 2.8cm))
#set text(font: "New Computer Modern", size: 11pt, lang: "en")
#set par(justify: true, leading: 0.62em)
#show heading: set text(weight: "regular")
#show link: set text(fill: rgb("#1a3a6a"))

// ---------- REGISTER SOURCES ----------
// Pick one:
// #setup-bib(read("refs.bib"))
#setup(yaml("refs.yml"), blockquote-indent: 1em)

// =============================================================
// DEMO
// =============================================================

= Lorem ipsum — example

#lorem(12) #cite-ref("0001:dolor"):

#blockq("0001:dolor", start: "Ut enim ad minim", end: "commodo consequat.")

#lorem(10) #cite-ref("0001:amet"):

#blockq("0001:amet", style: "box")

#lorem(12) #cite-ref("0002:perspiciatis"):

#blockq("0002:perspiciatis", start: "totam rem aperiam", end: "dicta sunt explicabo.", style: "fill")

#lorem(8) — see #id(pin: "p. 8"). Inline quote: #q("0001:amet", start: "Excepteur sint", end: "non proident", pin: "p. 2")

#bibliography-custom(new-page: false)
