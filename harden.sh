set -euo pipefail
echo "→ Applying robust-ingestion upgrade…"

mkdir -p "api"
mkdir -p "api/_lib"
mkdir -p "src"
mkdir -p "src/components"
mkdir -p "src/lib"

cat > "package.json" <<'__PYME_COPILOT_EOF__'
{
  "name": "pyme-copilot",
  "private": true,
  "version": "0.1.0",
  "type": "module",
  "description": "AI copilot that answers a micro-business's legal, accounting and admin questions grounded in its own documents (RAG over pgvector).",
  "scripts": {
    "dev": "vite",
    "dev:full": "vercel dev",
    "build": "vite build",
    "preview": "vite preview",
    "typecheck": "tsc -b"
  },
  "dependencies": {
    "@google/genai": "^2.13.0",
    "@supabase/supabase-js": "^2.45.0",
    "mammoth": "^1.8.0",
    "pdfjs-dist": "^4.7.76",
    "react": "^18.3.1",
    "react-dom": "^18.3.1"
  },
  "devDependencies": {
    "@tailwindcss/vite": "^4.0.0",
    "@types/node": "^22.5.0",
    "@types/react": "^18.3.5",
    "@types/react-dom": "^18.3.0",
    "@vercel/node": "^3.2.0",
    "@vitejs/plugin-react": "^4.3.1",
    "tailwindcss": "^4.0.0",
    "typescript": "^5.5.4",
    "vite": "^5.4.2"
  }
}
__PYME_COPILOT_EOF__
echo "   wrote package.json"

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
- Swap the chat model with `GEMINI_MODEL` (e.g. `gemini-flash-latest`) without code changes.
__PYME_COPILOT_EOF__
echo "   wrote README.md"

cat > "api/ingest.ts" <<'__PYME_COPILOT_EOF__'
import type { VercelRequest, VercelResponse } from "@vercel/node";
import { supabase } from "./_lib/supabase";

export const config = { maxDuration: 30 };

const CATEGORIES = ["legal", "contable", "administrativo", "general"];

// Creates the document row. Chunks are embedded and stored separately, in
// small batches, via /api/chunks — so a 300-page file never travels in one
// oversized, slow request.
export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "POST") return res.status(405).json({ error: "Method not allowed" });
  try {
    const { title, category = "general", source, charCount = 0 } = req.body ?? {};
    if (!title || typeof title !== "string")
      return res.status(400).json({ error: "Falta 'title'" });

    const cat = CATEGORIES.includes(category) ? category : "general";
    const { data: doc, error } = await supabase
      .from("documents")
      .insert({
        title: title.trim().slice(0, 200),
        category: cat,
        source: source ?? null,
        char_count: Number(charCount) || 0,
      })
      .select("id, title, category, char_count, created_at")
      .single();
    if (error) throw error;

    return res.status(200).json({ document: doc });
  } catch (err) {
    console.error("ingest error:", err);
    return res.status(500).json({ error: "No se pudo crear el documento" });
  }
}
__PYME_COPILOT_EOF__
echo "   wrote api/ingest.ts"

cat > "api/chunks.ts" <<'__PYME_COPILOT_EOF__'
import type { VercelRequest, VercelResponse } from "@vercel/node";
import { supabase } from "./_lib/supabase";
import { embedDocuments } from "./_lib/gemini";

export const config = { maxDuration: 60 };

const MAX_PER_REQUEST = 40;

// Embeds and stores one batch of chunks for a document. The client calls this
// repeatedly (small batches) so ingestion of huge files stays within Vercel's
// request-size and timeout limits, with progress the user can see.
export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "POST") return res.status(405).json({ error: "Method not allowed" });
  try {
    const { documentId, chunks, startIndex = 0 } = req.body ?? {};
    if (!documentId || !Array.isArray(chunks) || chunks.length === 0)
      return res.status(400).json({ error: "Faltan 'documentId' o 'chunks'" });
    if (chunks.length > MAX_PER_REQUEST)
      return res.status(413).json({ error: `Máximo ${MAX_PER_REQUEST} fragmentos por lote` });

    const clean = chunks.map((c: unknown) => String(c)).filter((c) => c.trim().length > 0);
    if (clean.length === 0) return res.status(200).json({ added: 0 });

    const embeddings = await embedDocuments(clean);
    const rows = clean.map((content, i) => ({
      document_id: documentId,
      chunk_index: Number(startIndex) + i,
      content,
      embedding: embeddings[i],
    }));

    const { error } = await supabase.from("chunks").insert(rows);
    if (error) throw error;

    return res.status(200).json({ added: rows.length });
  } catch (err) {
    console.error("chunks error:", err);
    return res.status(500).json({ error: "No se pudieron indexar los fragmentos" });
  }
}
__PYME_COPILOT_EOF__
echo "   wrote api/chunks.ts"

cat > "api/ocr.ts" <<'__PYME_COPILOT_EOF__'
import type { VercelRequest, VercelResponse } from "@vercel/node";
import { ocrImage } from "./_lib/gemini";

export const config = { maxDuration: 60 };

// Reads text out of a scanned page or photo using Gemini's multimodal model.
export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "POST") return res.status(405).json({ error: "Method not allowed" });
  try {
    const { imageBase64, mimeType } = req.body ?? {};
    if (!imageBase64 || !mimeType) return res.status(400).json({ error: "Falta la imagen" });

    const text = await ocrImage(imageBase64, mimeType);
    return res.status(200).json({ text });
  } catch (err) {
    console.error("ocr error:", err);
    return res.status(500).json({ error: "No se pudo leer la imagen" });
  }
}
__PYME_COPILOT_EOF__
echo "   wrote api/ocr.ts"

cat > "api/_lib/gemini.ts" <<'__PYME_COPILOT_EOF__'
import { GoogleGenAI } from "@google/genai";

const ai = new GoogleGenAI({ apiKey: process.env.GEMINI_API_KEY! });

const EMBED_MODEL = "gemini-embedding-001";
const EMBED_DIM = 768;
const CHAT_MODEL = process.env.GEMINI_MODEL ?? "gemini-2.5-flash";

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
echo "   wrote api/_lib/gemini.ts"

cat > "src/lib/extract.ts" <<'__PYME_COPILOT_EOF__'
import * as pdfjs from "pdfjs-dist";
import workerUrl from "pdfjs-dist/build/pdf.worker.min.mjs?url";
import * as mammoth from "mammoth/mammoth.browser";
import { ocr } from "./api";

pdfjs.GlobalWorkerOptions.workerSrc = workerUrl;

export type Progress = { phase: "reading" | "ocr"; page: number; total: number };
type OnProgress = (p: Progress) => void;

const OCR_MAX_PAGES = 60; // cap OCR on very long scans so a demo can't run away

export async function extractText(file: File, onProgress?: OnProgress): Promise<string> {
  const name = file.name.toLowerCase();
  if (name.endsWith(".pdf")) return extractPdf(file, onProgress);
  if (/\.(png|jpe?g|webp|gif|bmp)$/.test(name)) return extractImage(file, onProgress);
  if (name.endsWith(".docx")) {
    const arrayBuffer = await file.arrayBuffer();
    const { value } = await mammoth.extractRawText({ arrayBuffer });
    return value.trim();
  }
  return (await file.text()).trim();
}

async function extractPdf(file: File, onProgress?: OnProgress): Promise<string> {
  const data = await file.arrayBuffer();
  const pdf = await pdfjs.getDocument({ data }).promise;
  const total = pdf.numPages;

  const pagesText: string[] = [];
  for (let i = 1; i <= total; i++) {
    onProgress?.({ phase: "reading", page: i, total });
    const page = await pdf.getPage(i);
    const content = await page.getTextContent();
    pagesText.push(content.items.map((it: any) => ("str" in it ? it.str : "")).join(" "));
  }
  const joined = pagesText.join("\n\n").trim();

  // A real text layer yields plenty of characters. If it's nearly empty, the
  // PDF is scanned images → OCR each page instead.
  if (joined.replace(/\s/g, "").length >= total * 40) return joined;

  const limit = Math.min(total, OCR_MAX_PAGES);
  const ocrText: string[] = [];
  for (let i = 1; i <= limit; i++) {
    onProgress?.({ phase: "ocr", page: i, total: limit });
    const page = await pdf.getPage(i);
    const base64 = await renderPageToJpeg(page);
    const { text } = await ocr(base64, "image/jpeg");
    if (text.trim()) ocrText.push(text.trim());
  }
  return ocrText.join("\n\n").trim();
}

async function renderPageToJpeg(page: any): Promise<string> {
  const viewport = page.getViewport({ scale: 1.4 });
  const canvas = document.createElement("canvas");
  canvas.width = Math.ceil(viewport.width);
  canvas.height = Math.ceil(viewport.height);
  const ctx = canvas.getContext("2d")!;
  await page.render({ canvasContext: ctx, viewport }).promise;
  return canvas.toDataURL("image/jpeg", 0.8).split(",")[1];
}

async function extractImage(file: File, onProgress?: OnProgress): Promise<string> {
  onProgress?.({ phase: "ocr", page: 1, total: 1 });
  const base64 = await fileToBase64(file);
  const { text } = await ocr(base64, file.type || "image/jpeg");
  return text.trim();
}

function fileToBase64(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const r = new FileReader();
    r.onload = () => resolve(String(r.result).split(",")[1]);
    r.onerror = () => reject(new Error("No se pudo leer el archivo"));
    r.readAsDataURL(file);
  });
}
__PYME_COPILOT_EOF__
echo "   wrote src/lib/extract.ts"

cat > "src/lib/api.ts" <<'__PYME_COPILOT_EOF__'
export type Category = "legal" | "contable" | "administrativo" | "general";

export type Doc = {
  id: string;
  title: string;
  category: Category;
  char_count: number;
  created_at: string;
};

export type Source = {
  n: number;
  documentId: string;
  documentTitle: string;
  category: Category;
  chunkIndex: number;
  similarity: number;
  excerpt: string;
};

export type Answer = {
  answer: string;
  sources: Source[];
};

async function json<T>(res: Response): Promise<T> {
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error((data as any).error ?? "Error de red");
  return data as T;
}

const post = (url: string, body: unknown) =>
  fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });

export function listDocuments(): Promise<{ documents: Doc[] }> {
  return fetch("/api/documents").then((r) => json<{ documents: Doc[] }>(r));
}

export function deleteDocument(id: string): Promise<{ ok: true }> {
  return fetch(`/api/documents?id=${encodeURIComponent(id)}`, { method: "DELETE" }).then((r) =>
    json<{ ok: true }>(r)
  );
}

export function createDocument(payload: {
  title: string;
  category: Category;
  source?: string;
  charCount: number;
}): Promise<{ document: Doc }> {
  return post("/api/ingest", payload).then((r) => json<{ document: Doc }>(r));
}

export function storeChunks(
  documentId: string,
  chunks: string[],
  startIndex: number
): Promise<{ added: number }> {
  return post("/api/chunks", { documentId, chunks, startIndex }).then((r) =>
    json<{ added: number }>(r)
  );
}

export function ocr(imageBase64: string, mimeType: string): Promise<{ text: string }> {
  return post("/api/ocr", { imageBase64, mimeType }).then((r) => json<{ text: string }>(r));
}

export function askQuestion(
  question: string,
  category: Category | "all",
  useWeb = false
): Promise<Answer> {
  return post("/api/query", { question, category, useWeb }).then((r) => json<Answer>(r));
}
__PYME_COPILOT_EOF__
echo "   wrote src/lib/api.ts"

cat > "src/lib/chunk.ts" <<'__PYME_COPILOT_EOF__'
const TARGET = 1000; // chars per chunk (~250 tokens)
const OVERLAP = 150; // chars carried into the next chunk for continuity

// Split on the strongest boundary available so chunks stay semantically whole:
// paragraphs first, then sentences, then hard-wrap as a last resort.
export function chunkText(raw: string): string[] {
  const text = raw.replace(/\r\n/g, "\n").replace(/\n{3,}/g, "\n\n").trim();
  if (!text) return [];

  const paragraphs = text.split(/\n\s*\n/);
  const pieces: string[] = [];
  for (const p of paragraphs) {
    if (p.length <= TARGET) {
      pieces.push(p.trim());
    } else {
      for (const s of splitLong(p)) pieces.push(s);
    }
  }

  const chunks: string[] = [];
  let current = "";
  for (const piece of pieces) {
    if (!piece) continue;
    if (current && current.length + piece.length + 2 > TARGET) {
      chunks.push(current.trim());
      current = tail(current, OVERLAP) + "\n\n" + piece;
    } else {
      current = current ? current + "\n\n" + piece : piece;
    }
  }
  if (current.trim()) chunks.push(current.trim());
  return chunks.filter((c) => c.length > 0);
}

function splitLong(paragraph: string): string[] {
  const sentences = paragraph.match(/[^.!?\n]+[.!?]*\s*/g) ?? [paragraph];
  const out: string[] = [];
  let buf = "";
  for (const s of sentences) {
    if (buf.length + s.length > TARGET) {
      if (buf) out.push(buf.trim());
      buf = s.length > TARGET ? "" : s;
      if (s.length > TARGET) {
        for (let i = 0; i < s.length; i += TARGET) out.push(s.slice(i, i + TARGET).trim());
      }
    } else {
      buf += s;
    }
  }
  if (buf.trim()) out.push(buf.trim());
  return out;
}

function tail(s: string, n: number): string {
  return s.length <= n ? s : s.slice(s.length - n);
}
__PYME_COPILOT_EOF__
echo "   wrote src/lib/chunk.ts"

cat > "src/mammoth.d.ts" <<'__PYME_COPILOT_EOF__'
declare module "mammoth/mammoth.browser" {
  export function extractRawText(input: {
    arrayBuffer: ArrayBuffer;
  }): Promise<{ value: string; messages: unknown[] }>;
}
__PYME_COPILOT_EOF__
echo "   wrote src/mammoth.d.ts"

cat > "src/components/Uploader.tsx" <<'__PYME_COPILOT_EOF__'
import { useRef, useState } from "react";
import { createDocument, storeChunks, deleteDocument, type Category } from "../lib/api";
import { CATEGORY_LABEL, CATEGORY_OPTIONS } from "../lib/categories";
import { extractText, type Progress } from "../lib/extract";
import { chunkText } from "../lib/chunk";

const BATCH = 15;

type Status = "reading" | "ocr" | "indexing" | "done" | "error";
type Item = { id: number; name: string; status: Status; detail: string };

function guessCategory(name: string): Category {
  const n = name.toLowerCase();
  if (/(contrato|acuerdo|nda|clausul|arrendamiento|laboral|estatuto|convenio|escritura)/.test(n))
    return "legal";
  if (/(factura|iva|nomina|nómina|modelo|303|130|349|390|impuesto|contab|balance|libro|ticket)/.test(n))
    return "contable";
  if (/(permiso|licencia|registro|solicitud|tramite|trámite|certificado|alta|baja)/.test(n))
    return "administrativo";
  return "general";
}

const STATUS_DOT: Record<Status, string> = {
  reading: "bg-highlight animate-pulse",
  ocr: "bg-highlight animate-pulse",
  indexing: "bg-highlight animate-pulse",
  done: "bg-viridian",
  error: "bg-red-600",
};

export default function Uploader({ onAdded }: { onAdded: () => void }) {
  const [items, setItems] = useState<Item[]>([]);
  const [category, setCategory] = useState<Category | "auto">("auto");
  const [pasteOpen, setPasteOpen] = useState(false);
  const [pasteTitle, setPasteTitle] = useState("");
  const [pasteText, setPasteText] = useState("");
  const nextId = useRef(0);
  const fileRef = useRef<HTMLInputElement>(null);

  const busy = items.some((i) => i.status === "reading" || i.status === "ocr" || i.status === "indexing");

  function update(id: number, patch: Partial<Item>) {
    setItems((list) => list.map((it) => (it.id === id ? { ...it, ...patch } : it)));
  }

  async function ingestText(name: string, text: string, cat: Category, source: string, id: number) {
    const chunks = chunkText(text);
    if (chunks.length === 0) {
      update(id, { status: "error", detail: "Documento vacío tras el procesado" });
      return;
    }
    update(id, { status: "indexing", detail: `Indexando · 0/${chunks.length}` });
    const { document } = await createDocument({ title: name, category: cat, source, charCount: text.length });
    try {
      for (let i = 0; i < chunks.length; i += BATCH) {
        await storeChunks(document.id, chunks.slice(i, i + BATCH), i);
        update(id, { detail: `Indexando · ${Math.min(i + BATCH, chunks.length)}/${chunks.length}` });
      }
    } catch (e) {
      await deleteDocument(document.id).catch(() => {});
      throw e;
    }
    update(id, { status: "done", detail: `${chunks.length} fragmentos indexados` });
    onAdded();
  }

  async function processFile(file: File) {
    const id = nextId.current++;
    setItems((list) => [...list, { id, name: file.name, status: "reading", detail: "Leyendo…" }]);
    try {
      const text = await extractText(file, (p: Progress) =>
        update(id, {
          status: p.phase === "ocr" ? "ocr" : "reading",
          detail:
            p.phase === "ocr"
              ? `Reconociendo texto con IA · pág. ${p.page}/${p.total}`
              : `Leyendo · pág. ${p.page}/${p.total}`,
        })
      );
      if (text.trim().length < 20) {
        update(id, { status: "error", detail: "No se pudo extraer texto legible" });
        return;
      }
      const cat: Category = category === "auto" ? guessCategory(file.name) : category;
      await ingestText(file.name.replace(/\.[^.]+$/, ""), text, cat, file.name, id);
    } catch (e) {
      update(id, { status: "error", detail: (e as Error).message || "Error al procesar" });
    }
  }

  async function handleFiles(files: FileList | File[]) {
    for (const f of Array.from(files)) await processFile(f); // sequential: clear progress, gentle on rate limits
    if (fileRef.current) fileRef.current.value = "";
  }

  async function submitPaste() {
    if (pasteTitle.trim().length < 2 || pasteText.trim().length < 20) return;
    const id = nextId.current++;
    setItems((list) => [...list, { id, name: pasteTitle.trim(), status: "indexing", detail: "Indexando…" }]);
    const cat: Category = category === "auto" ? "general" : category;
    try {
      await ingestText(pasteTitle.trim(), pasteText, cat, "texto pegado", id);
      setPasteTitle("");
      setPasteText("");
      setPasteOpen(false);
    } catch (e) {
      update(id, { status: "error", detail: (e as Error).message });
    }
  }

  return (
    <div className="space-y-3">
      <label
        className="flex cursor-pointer flex-col items-center justify-center gap-1 rounded-lg border border-dashed border-line bg-surface px-4 py-6 text-center transition-colors hover:border-viridian"
        onDragOver={(e) => e.preventDefault()}
        onDrop={(e) => {
          e.preventDefault();
          if (e.dataTransfer.files.length) handleFiles(e.dataTransfer.files);
        }}
      >
        <span className="text-sm font-medium text-ink">Arrastra tus documentos o elígelos</span>
        <span className="font-mono text-xs text-ink-soft">
          PDF (también escaneados) · Word · imágenes · TXT · CSV
        </span>
        <input
          ref={fileRef}
          type="file"
          multiple
          accept=".pdf,.docx,.txt,.md,.csv,.png,.jpg,.jpeg,.webp,.gif,.bmp"
          className="hidden"
          onChange={(e) => e.target.files?.length && handleFiles(e.target.files)}
        />
      </label>

      <div className="flex items-center gap-2">
        <span className="font-mono text-[10px] uppercase tracking-wide text-ink-soft">Área</span>
        <select
          value={category}
          onChange={(e) => setCategory(e.target.value as Category | "auto")}
          className="flex-1 rounded-md border border-line bg-surface px-2 py-1.5 text-xs outline-none focus:border-viridian"
        >
          <option value="auto">Detectar automáticamente</option>
          {CATEGORY_OPTIONS.map((c) => (
            <option key={c} value={c}>
              {CATEGORY_LABEL[c]}
            </option>
          ))}
        </select>
      </div>

      {items.length > 0 && (
        <ul className="space-y-1.5">
          {items.map((it) => (
            <li key={it.id} className="flex items-start gap-2 rounded-lg border border-line bg-surface px-3 py-2">
              <span className={`mt-1.5 inline-block h-2 w-2 shrink-0 rounded-full ${STATUS_DOT[it.status]}`} />
              <div className="min-w-0">
                <p className="truncate text-sm font-medium text-ink">{it.name}</p>
                <p className={`font-mono text-[10px] ${it.status === "error" ? "text-red-700" : "text-ink-soft"}`}>
                  {it.detail}
                </p>
              </div>
            </li>
          ))}
        </ul>
      )}

      <button
        onClick={() => setPasteOpen((o) => !o)}
        className="font-mono text-xs text-viridian underline-offset-2 hover:underline"
      >
        {pasteOpen ? "▾ Pegar texto" : "▸ …o pegar texto a mano"}
      </button>

      {pasteOpen && (
        <div className="space-y-2">
          <input
            value={pasteTitle}
            onChange={(e) => setPasteTitle(e.target.value)}
            placeholder="Título"
            className="w-full rounded-lg border border-line bg-surface px-3 py-2 text-sm outline-none placeholder:text-ink-soft/70 focus:border-viridian"
          />
          <textarea
            value={pasteText}
            onChange={(e) => setPasteText(e.target.value)}
            placeholder="Pega aquí el texto del documento"
            rows={4}
            className="w-full resize-y rounded-lg border border-line bg-surface px-3 py-2 text-sm outline-none placeholder:text-ink-soft/70 focus:border-viridian"
          />
          <button
            onClick={submitPaste}
            disabled={busy || pasteTitle.trim().length < 2 || pasteText.trim().length < 20}
            className="w-full rounded-lg bg-viridian px-4 py-2.5 text-sm font-semibold text-surface transition-opacity hover:bg-viridian-ink disabled:opacity-40"
          >
            Añadir texto
          </button>
        </div>
      )}
    </div>
  );
}
__PYME_COPILOT_EOF__
echo "   wrote src/components/Uploader.tsx"

echo ""
echo "✓ Files updated. Now run:"
echo "    npm install"
echo "    git add -A && git commit -m \"robust ingestion: OCR, docx, big files\" && git push"
