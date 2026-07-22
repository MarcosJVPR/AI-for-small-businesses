# PYME Copilot

**An AI copilot that answers a micro-business's legal, accounting and administrative questions — grounded in its own documents.** Upload contracts, invoices, payslips or tax forms; ask questions in plain language; get answers that cite the exact passage they came from.

Built as a compact, production-shaped RAG (Retrieval-Augmented Generation) system: document ingestion → chunking → embeddings → vector search → grounded generation with inline citations.

> Sube los papeles de tu negocio y pregunta como si tuvieras un equipo legal, contable y administrativo detrás.

---

## Why RAG (and not "just ask an LLM")

A raw LLM will happily invent a due date, an IVA rate or a clause that isn't in your contract. For legal/fiscal questions that's not a bug you can ship. RAG fixes it by only letting the model answer from text it actually retrieved:

1. Every document is split into overlapping **chunks**.
2. Each chunk is turned into a **768-dim embedding** (`gemini-embedding-001`) and stored in Postgres with **pgvector**.
3. A question is embedded the same way, and the closest chunks are pulled by **cosine similarity**.
4. Those chunks — and only those — are handed to `gemini-2.5-flash`, with a system prompt that forces it to cite `[n]` and to say *"I don't find this in your documents"* when the answer isn't there.
5. A similarity floor (`0.35`) short-circuits irrelevant matches before they ever reach the model.

The result: answers are traceable to a source, and the "unknown" case is handled honestly instead of hallucinated.

---

## Architecture

```
┌──────────────────────────┐        ┌───────────────────────────────┐
│  React + TS + Tailwind    │        │  Vercel serverless (Node/TS)   │
│  (Vite)                    │        │                                │
│                            │        │  /api/ingest   chunk → embed   │
│  • Uploader (file → text)  │  HTTPS │                → store          │
│  • Chat + inline citations │ ─────▶ │  /api/query    embed → search  │
│  • Source viewer           │        │                → generate       │
│                            │        │  /api/documents  list / delete │
└──────────────────────────┘        └───────────────┬───────────────┘
       PDF text extracted                            │
       in the browser (pdfjs)             ┌──────────┴──────────┐
                                          │                     │
                                 ┌────────▼────────┐   ┌────────▼────────┐
                                 │  Gemini API      │   │  Supabase        │
                                 │  embeddings +    │   │  Postgres +      │
                                 │  generation      │   │  pgvector        │
                                 └──────────────────┘   └──────────────────┘
```

The `service_role` Supabase key lives **only** on the server (Vercel env vars). The browser never talks to the database directly and never sees a secret — it only calls `/api/*`.

---

## Stack

| Layer      | Tech |
|------------|------|
| Frontend   | React 18, TypeScript, Vite, Tailwind CSS v4 |
| API        | Vercel serverless functions (TypeScript, Node) |
| Vector DB  | Supabase (Postgres + pgvector, HNSW cosine index) |
| Embeddings | `gemini-embedding-001` (768-dim, Matryoshka truncation) |
| Generation | `gemini-2.5-flash` (swappable via `GEMINI_MODEL`) |
| PDF parsing| `pdfjs-dist` (client-side) |

---

## Run it

### 1. Database

Create a Supabase project, open the **SQL Editor**, and run [`supabase/schema.sql`](supabase/schema.sql). It enables `pgvector`, creates the `documents` / `chunks` tables, the HNSW index and the `match_chunks` search function.

### 2. Environment

```bash
cp .env.example .env
```

Fill in:
- `GEMINI_API_KEY` — from [Google AI Studio](https://aistudio.google.com/apikey)
- `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` — from Supabase → Project Settings → API

### 3. Local dev

```bash
npm install
npm run dev:full   # vercel dev — runs the frontend AND the /api functions
```

`npm run dev` runs the Vite frontend alone (the API needs `vercel dev` or a deploy).

### 4. Deploy

Push to GitHub and import into Vercel. Add the three env vars in the Vercel dashboard. Vercel auto-detects Vite and serves `/api/*` as functions. That's the whole deploy.

### Try it in 30 seconds

`sample-docs/` contains three fictional documents (a lease, an invoice, a tax-filing note). Drop them into the archive, then click one of the suggested questions — each answer comes back with the exact source passage highlighted.

---

## Repo map

```
api/
  _lib/chunk.ts      boundary-aware text splitter (paragraph → sentence → hard wrap)
  _lib/gemini.ts     embeddings + grounded generation, system prompt & guardrails
  _lib/supabase.ts   service-role client (server only)
  ingest.ts          POST  chunk + embed + store a document
  query.ts           POST  the RAG pipeline
  documents.ts       GET / DELETE documents
src/
  components/Uploader.tsx    add docs by file or paste
  components/Chat.tsx        question box, inline [n] citations
  components/SourceList.tsx  retrieved passages, highlighted
  lib/                       typed API client, pdf extraction, categories
supabase/schema.sql          pgvector schema + match_chunks()
```

---

## Notes & next steps

- **Chunking** is intentionally simple (fixed size + overlap on natural boundaries). A semantic or layout-aware splitter would improve retrieval on tables and forms.
- **Embeddings** are truncated to 768 dims via Matryoshka — cheaper and index-friendly (pgvector indexes cap at 2000 dims) with negligible quality loss vs. the full 3072.
- **Evaluation**: the obvious next layer is a small golden-question set to measure retrieval hit-rate and answer faithfulness before touching the prompt.
- Swap the chat model with `GEMINI_MODEL` (e.g. `gemini-flash-latest`) without code changes.
