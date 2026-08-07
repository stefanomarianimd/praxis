---
title: Praxis
---

A clinical information system for a single orthopaedic practice, built by the surgeon who
uses it. Hip and knee arthroplasty, sports knee, revision. Italy.

This is not a product and not a company. It is one clinician's attempt to build the tool he
wanted and could not buy, under the constraints that actually apply to a small European
private practice: GDPR, MDR, no data engineering team, and a corpus of clinical knowledge
measured in tens of documents rather than millions.

The repository is private. This page exists because the design decisions turned out to be
worth discussing with people building the same thing at a very different scale.

---

## What it does

**Structured at the source.** The clinical datum is entered once, during the consultation,
into typed fields defined by a per-pathology schema — eight of them, one per condition the
practice actually treats (patellofemoral instability and pain, knee and hip arthroplasty,
ACL and ligament surgery, knee osteotomy, knee and hip revision). Those same fields serve
two purposes: they compose the report the patient and the referring physician read, and they
populate a pseudonymised longitudinal registry. There is no second data-entry step, because
a second data-entry step is a step that does not happen.

**Patient-reported outcomes from the patient.** A tablet in the waiting room, running under a
dedicated kiosk role that can reach nothing else, administers the instruments due at that
timepoint. Scores flow into the same record and pre-fill the corresponding fields in the
report.

**A guideline assistant that must cite.** An LLM agent over a closed corpus — clinical
guidelines plus the practice's own pathology schemas — with one rule that is not negotiable:
no clinical statement leaves the system without a citation the physician can open.

The rest is the unglamorous half: scheduling, patient records, episodes of care, consent
tracking with revocation, attachments, surgical worklist, a personal operative logbook,
role-based access with the secretary structurally excluded from clinical notes, and an audit
log of every read and write.

---

## The part worth discussing: refusal as a structural constraint

The failure mode that matters in this setting is not a wrong answer. It is a **plausible
answer to a question the corpus cannot support**, delivered with a citation that looks
authoritative. A physician who reads a confident sentence with a source attached will
reasonably assume the source says it.

So refusal is not a behaviour requested in a prompt. It is a property of the output type.

The model may emit exactly two shapes: an answer in which **every sentence carries at least
one source index**, or a declared non-answer. An answer whose citations do not validate — a
missing index, an index out of range, a sentence without sources — is not a poor answer; it
is not a *representable* one. Code rejects it and the result is downgraded to a refusal. The
model does not have permission to answer without evidence; if it tries, the type system
takes the answer away.

That idea is not ours. It is the `<answer>`-gated structure in
[OrthoPilot](https://arxiv.org/abs/2607.12527), read out of their released code and pushed
one level down, from a prompt instruction into a discriminated union plus validation.

### Three safeguards, not one threshold

Abstention rests on three signals, deliberately heterogeneous, because a single better
threshold does not exist — we measured that, and the measurement is below.

| | | |
|---|---|---|
| **1. Declared coverage** | deterministic, runs *before* retrieval | The corpus declares which anatomical districts it covers. A question that names only uncovered districts is refused without any model being called. Cheap, auditable, and it never sees the question's semantics — which is both its strength and its failure mode. |
| **2. Noise floor** | deterministic, after reranking | Removes garbage. Does *not* decide relevance, and cannot: near-out-of-distribution questions score comfortably above any floor that still admits weak positives. |
| **3. Model judgement** | the reader | Given the retrieved passages, does the evidence actually support an answer? This is the only safeguard that can catch a question inside the covered district whose answer is simply absent. It is also a noisy vote, not a safety net. |

The ordering matters. Safeguards 1 and 2 are free and wrong in predictable ways; safeguard 3
is expensive and wrong in unpredictable ones. Putting the deterministic checks first means the
model is asked only the questions that genuinely require reading.

### Measuring it: two numbers, never averaged

- **FRR**, false refusal rate — refusals on questions the corpus *does* answer. The cost of
  use. A system with FRR near 1 is safe and useless.
- **FAR**, false answer rate — answers on questions the corpus does *not* answer. The clinical
  cost.

Reporting a single blended score hides exactly the trade-off you need to see. They are always
printed side by side.

The evaluation set is 120 labelled queries — 60 in-corpus, anchored to verified passages, and
60 out-of-corpus stratified by *why* they are out. That stratification is the point. Questions
naming an uncovered district are a control, not a challenge. The hard families are the
near-OOD ones:

- **Recommendation-shaped questions inside a covered district.** *"Which surgical approach is
  best for a hip replacement?"* The schemas record what was done, not what should be done. The
  words are all in the corpus; the answer is not.
- **Thresholds that look like they must exist.** The strongest single case: *"What is the CRP
  cutoff for confirming periprosthetic joint infection under EBJIS?"* EBJIS discusses CRP in
  four separate places and deliberately never gives a number. Retrieval could not be more
  confident; the answer does not exist.

An early result, from the retrieval stage alone with the model deliberately not consulted: the
two deterministic safeguards stop **every** out-of-district question at zero cost and let
through essentially **100% of all three near-OOD families**. That gap is not a defect — it is
the measurement of how much work safeguard 3 is actually being asked to do, which is the
quantity worth knowing before trusting any architecture that rests on it alone.

Full results, including what the model catches and what it does not, are kept
with the code and available on request.

### What the evaluation already caught

The set was written to test the system; it immediately found two defects in it, which is the
argument for writing one.

- The deterministic coverage filter refused *"in which **column** of the EBJIS table does…"*
  as out-of-scope, because in Italian **colonna** is both the spine and a table column. A
  filter that blocks on positive evidence cannot accept an ambiguous word as evidence.
- A legitimate question phrased naturally fell below the noise floor while the same question
  phrased as keywords passed. Hybrid dense + lexical retrieval does not make phrasing
  irrelevant; it changes which phrasings fail.

---

## Architecture

```
Next.js + Prisma  ─ web app, role-based, audit-logged
      │
      ├── PostgreSQL           clinical data, EU-hosted
      │
      └── guideline assistant
             ├── retrieval sidecar (FastAPI, stateless, no DB access)
             │     multilingual-e5-large  +  bge-reranker-v2-m3
             │     hybrid recall: dense + BM25, fused by rank
             │
             └── LLM  (Claude via Amazon Bedrock, Frankfurt)
```

Notes on choices that were not obvious:

**Cross-lingual by construction.** Questions arrive in Italian; the guidelines are in English.
That is not an edge case to be handled, it is the normal operating condition, and it drove the
choice of both the embedding and the reranking model.

**Rank fusion, not score fusion.** Dense similarity and BM25 produce numbers on incommensurable
scales. Adding them yields a quantity with no meaning. The two lists are fused by rank because
the only comparable thing about them is the ordering.

**Retrieval is the agent's entire world.** The tool is read-only and has no access to anything
the physician's session can reach. There is no path from the assistant to patient data.

**The corpus is small on purpose.** Roughly 140 passages from ten documents. At this scale a
declared-coverage manifest is cheap and reliable, table structure can be preserved by hand, and
every retrieval failure can be read individually. Whether any of that survives at a larger scale
is a genuinely open question, and the reason the conversation with larger projects is
interesting.

**Chunking is table-aware, and this was learned the hard way.** Both retrieval models silently
truncate at 512 tokens. The EBJIS criteria table — the single most important passage in the
corpus — exceeded it, and lost 27% of its content with no error and no warning: the sonication
threshold for confirmed infection, the entire histology row, and all of nuclear imaging. The
system could not answer those questions because it had never read them. Tables are now split by
row with the header repeated on each part, and a regression test fails the build if any fragment
exceeds the limit or if a table part loses its header.

---

## Regulatory position

The guideline assistant is scoped as **document retrieval with citation**, not as a system that
produces patient-specific recommendations. That boundary is a design constraint, not a
disclaimer: the corpus contains documents, the assistant answers about documents, and no patient
data enters it. Crossing that line would change the regulatory qualification of the system, and
is therefore a decision to be taken deliberately rather than arrived at by feature creep.

Clinical data are hosted in the EU. Audio for ambient scribing, when that module ships, is
deleted immediately after transcription and never stored. No report leaves the system without a
physician's signature.

---

## Status

Working and in use with synthetic data: patient records, scheduling, clinical history,
structured reporting for all eight pathologies, the PROM kiosk, the research export, the
surgical worklist, the operative logbook.

Working locally, not yet deployed: the guideline assistant.

Not yet built: ambient scribing.

Deployment to production is planned for autumn 2026. Nothing has ever run against real patient
data.

---

## Contact

Stefano Mariani — orthopaedic surgeon, hip and knee arthroplasty. Milan / Monza, Italy.

Interested in comparing notes with anyone building evidence-grounded clinical assistants,
particularly on abstention, on entailment verification of generated sentences, and on evaluating
either honestly at a scale where you cannot fall back on statistics.
