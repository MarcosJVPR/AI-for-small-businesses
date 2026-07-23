#!/usr/bin/env bash
# Fixes: gemini-2.5-flash is no longer available to new users (404).
# Switches the default chat model to gemini-3.6-flash (GA as of July 2026).
# Run from the repo root:  bash fixmodel.sh
set -euo pipefail
echo "→ Updating default Gemini model…"

cat > "api/_lib/gemini.ts" <<'__PYME_COPILOT_EOF__'
import { GoogleGenAI } from "@google/genai";

const ai = new GoogleGenAI({ apiKey: process.env.GEMINI_API_KEY! });

const EMBED_MODEL = "gemini-embedding-001";
const EMBED_DIM = 768;
const CHAT_MODEL = process.env.GEMINI_MODEL ?? "gemini-3.6-flash";

type Task = "RETRIEVAL_DOCUMENT" | "RETRIEVAL_QUERY";

async function embedOne(text: string, taskType: Task): Promise<number[]> {
  const res = await ai.models.embedContent({
    model: EMBED_MODEL,
    contents: text,
    config: { outputDimensionality: EMBED_DIM, taskType },
  });
  const values = res.embeddings?.[0]?.values;
  if (!values) throw new Error("No embedding returned");
  return values;
}

export function embedQuery(text: string): Promise<number[]> {
  return embedOne(text, "RETRIEVAL_QUERY");
}

// Embed many chunks with light concurrency so ingestion stays fast but polite.
export async function embedDocuments(texts: string[]): Promise<number[][]> {
  const out: number[][] = new Array(texts.length);
  const BATCH = 5;
  for (let i = 0; i < texts.length; i += BATCH) {
    const slice = texts.slice(i, i + BATCH);
    const res = await Promise.all(slice.map((t) => embedOne(t, "RETRIEVAL_DOCUMENT")));
    res.forEach((v, j) => (out[i + j] = v));
  }
  return out;
}

export type Passage = {
  n: number;
  documentTitle: string;
  category: string;
  content: string;
};

const SYSTEM_STRICT = `Eres el copiloto de una micro-empresa. Respondes preguntas de tipo legal, contable y administrativo APOYÁNDOTE ÚNICAMENTE en los fragmentos de documentos que se te entregan.

Reglas:
- Usa SOLO la información de los fragmentos. No uses conocimiento propio ni general.
- Si la respuesta no está en los fragmentos, dilo con claridad ("No encuentro esto en tus documentos") y sugiere qué documento haría falta. No la deduzcas de tu memoria.
- Cita cada afirmación con el número del fragmento entre corchetes, por ejemplo [1] o [2][3].
- No inventes cifras, plazos, artículos ni cláusulas. Si dudas, no lo afirmes.
- Responde en el idioma de la pregunta, de forma directa y breve.
- No eres un abogado ni un asesor fiscal colegiado: cierra con una línea recordando que conviene validar decisiones críticas con un profesional.`;

const SYSTEM_WEB = `Eres el copiloto de una micro-empresa. Respondes preguntas de tipo legal, contable y administrativo.

Reglas:
- Prioriza SIEMPRE los fragmentos de los documentos del usuario y cítalos con su número entre corchetes, por ejemplo [1] o [2][3].
- El usuario ha permitido búsqueda web para esta pregunta. Úsala solo para completar lo que falte en los documentos, y cuando lo hagas, indícalo explícitamente ("según información pública…").
- No mezcles ni presentes información web como si viniera de los documentos del usuario.
- No inventes cifras, plazos, artículos ni cláusulas.
- Responde en el idioma de la pregunta, de forma directa y breve.
- No eres un abogado ni un asesor fiscal colegiado: cierra recordando validar decisiones críticas con un profesional.`;

export async function generateAnswer(
  question: string,
  passages: Passage[],
  useWeb = false
): Promise<string> {
  const context = passages.length
    ? passages.map((p) => `[${p.n}] (${p.category} — ${p.documentTitle})\n${p.content}`).join("\n\n")
    : "(no hay fragmentos relevantes en los documentos del usuario)";

  const system = useWeb ? SYSTEM_WEB : SYSTEM_STRICT;
  const prompt = `${system}\n\n=== FRAGMENTOS ===\n${context}\n\n=== PREGUNTA ===\n${question}`;

  const config: Record<string, unknown> = { temperature: 0.2 };
  if (useWeb) config.tools = [{ googleSearch: {} }];

  const res = await ai.models.generateContent({ model: CHAT_MODEL, contents: prompt, config });
  return res.text ?? "No pude generar una respuesta.";
}

export async function ocrImage(base64: string, mimeType: string): Promise<string> {
  const res = await ai.models.generateContent({
    model: CHAT_MODEL,
    contents: [
      { inlineData: { data: base64, mimeType } },
      {
        text: "Transcribe literalmente TODO el texto de este documento, respetando el orden de lectura. No resumas, no añadas comentarios ni explicaciones. Si hay tablas, transcríbelas fila por fila. Devuelve únicamente el texto.",
      },
    ],
    config: { temperature: 0 },
  });
  return res.text ?? "";
}
__PYME_COPILOT_EOF__
echo "   updated api/_lib/gemini.ts"

cat > ".env.example" <<'__PYME_COPILOT_EOF__'
# Gemini (Google AI Studio) — https://aistudio.google.com/apikey
GEMINI_API_KEY=
# Optional: override the chat model. Defaults to gemini-3.6-flash.
# GEMINI_MODEL=gemini-3.5-flash-lite

# Supabase — Project settings → API
SUPABASE_URL=https://xxxxxxxx.supabase.co
# service_role key. SERVER-SIDE ONLY. Never expose in the browser / never prefix with VITE_.
SUPABASE_SERVICE_ROLE_KEY=
__PYME_COPILOT_EOF__
echo "   updated .env.example"

cat > "README.md" <<'__PYME_COPILOT_EOF__'
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
| Generation | `gemini-3.6-flash` (swappable via `GEMINI_MODEL`) |
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

## Robust ingestion

Real small-business paperwork is messy, so ingestion is built to survive it:

- **Scanned PDFs & photos** — if a PDF has no text layer (or you upload a JPG/PNG of a contract), each page is sent to Gemini's multimodal model for OCR, so image-only documents still become searchable. Tables are transcribed row by row.
- **Word documents** — `.docx` is parsed in the browser via `mammoth`.
- **Huge documents** — text is split client-side and embedded in small batches (`/api/chunks`), so a 300-page file never travels in one oversized request and never trips Vercel's body-size or timeout limits. Progress is shown per page and per batch.
- **Many files at once** — drag a whole folder's worth; each file is queued with its own live status, and one bad file doesn't block the rest.
- **Built for non-technical users** — category is auto-detected from the filename, titles are filled automatically, and failures show a plain-language reason instead of a stack trace.

---

## Notes & next steps

- **Chunking** is intentionally simple (fixed size + overlap on natural boundaries). A semantic or layout-aware splitter would improve retrieval on tables and forms.
- **Embeddings** are truncated to 768 dims via Matryoshka — cheaper and index-friendly (pgvector indexes cap at 2000 dims) with negligible quality loss vs. the full 3072.
- **Evaluation**: the obvious next layer is a small golden-question set to measure retrieval hit-rate and answer faithfulness before touching the prompt.
- Swap the chat model with `GEMINI_MODEL` (e.g. `gemini-3.5-flash-lite` for lower cost) without code changes.
__PYME_COPILOT_EOF__
echo "   updated README.md"

echo ""
echo "✓ Done. Commit and push:"
echo "    git add -A && git commit -m \"fix: use gemini-3.6-flash\" && git push"
echo ""
echo "Note: if you set GEMINI_MODEL in Vercel env vars, update or remove it too —"
echo "an explicit env var overrides this default."
