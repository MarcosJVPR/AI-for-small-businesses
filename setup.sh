
set -euo pipefail

echo "→ Creating folders and files…"

mkdir -p "api"
mkdir -p "api/_lib"
mkdir -p "public"
mkdir -p "sample-docs"
mkdir -p "src"
mkdir -p "src/components"
mkdir -p "src/lib"
mkdir -p "supabase"

cat > ".env.example" <<'__PYME_COPILOT_EOF__'
# Gemini (Google AI Studio) — https://aistudio.google.com/apikey
GEMINI_API_KEY=
# Optional: override the chat model. Defaults to gemini-2.5-flash.
# GEMINI_MODEL=gemini-flash-latest

# Supabase — Project settings → API
SUPABASE_URL=https://xxxxxxxx.supabase.co
# service_role key. SERVER-SIDE ONLY. Never expose in the browser / never prefix with VITE_.
SUPABASE_SERVICE_ROLE_KEY=
__PYME_COPILOT_EOF__

cat > ".gitignore" <<'__PYME_COPILOT_EOF__'
node_modules
dist
.vercel
.env
.env*.local
*.log
.DS_Store
__PYME_COPILOT_EOF__

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

## Notes & next steps

- **Chunking** is intentionally simple (fixed size + overlap on natural boundaries). A semantic or layout-aware splitter would improve retrieval on tables and forms.
- **Embeddings** are truncated to 768 dims via Matryoshka — cheaper and index-friendly (pgvector indexes cap at 2000 dims) with negligible quality loss vs. the full 3072.
- **Evaluation**: the obvious next layer is a small golden-question set to measure retrieval hit-rate and answer faithfulness before touching the prompt.
- Swap the chat model with `GEMINI_MODEL` (e.g. `gemini-flash-latest`) without code changes.
__PYME_COPILOT_EOF__

cat > "index.html" <<'__PYME_COPILOT_EOF__'
<!doctype html>
<html lang="es">
  <head>
    <meta charset="UTF-8" />
    <link rel="icon" type="image/svg+xml" href="/favicon.svg" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>PYME Copilot — asesor IA sobre tus documentos</title>
    <meta
      name="description"
      content="Sube los documentos de tu negocio y pregunta como si tuvieras un equipo legal, contable y administrativo. Respuestas ancladas en tus propios documentos."
    />
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.tsx"></script>
  </body>
</html>
__PYME_COPILOT_EOF__

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

cat > "tsconfig.app.json" <<'__PYME_COPILOT_EOF__'
{
  "compilerOptions": {
    "target": "ES2022",
    "useDefineForClassFields": true,
    "lib": ["ES2022", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "skipLibCheck": true,
    "moduleResolution": "bundler",
    "allowImportingTsExtensions": true,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "moduleDetection": "force",
    "noEmit": true,
    "jsx": "react-jsx",
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noFallthroughCasesInSwitch": true
  },
  "include": ["src"]
}
__PYME_COPILOT_EOF__

cat > "tsconfig.json" <<'__PYME_COPILOT_EOF__'
{
  "files": [],
  "references": [
    { "path": "./tsconfig.app.json" },
    { "path": "./tsconfig.node.json" }
  ]
}
__PYME_COPILOT_EOF__

cat > "tsconfig.node.json" <<'__PYME_COPILOT_EOF__'
{
  "compilerOptions": {
    "target": "ES2022",
    "lib": ["ES2023"],
    "module": "ESNext",
    "skipLibCheck": true,
    "moduleResolution": "bundler",
    "allowImportingTsExtensions": true,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "moduleDetection": "force",
    "noEmit": true,
    "strict": true
  },
  "include": ["vite.config.ts", "api"]
}
__PYME_COPILOT_EOF__

cat > "vite.config.ts" <<'__PYME_COPILOT_EOF__'
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";

export default defineConfig({
  plugins: [react(), tailwindcss()],
  server: {
    proxy: {
      "/api": "http://localhost:3000",
    },
  },
});
__PYME_COPILOT_EOF__

cat > "api/documents.ts" <<'__PYME_COPILOT_EOF__'
import type { VercelRequest, VercelResponse } from "@vercel/node";
import { supabase } from "./_lib/supabase";

export default async function handler(req: VercelRequest, res: VercelResponse) {
  try {
    if (req.method === "GET") {
      const { data, error } = await supabase
        .from("documents")
        .select("id, title, category, char_count, created_at")
        .order("created_at", { ascending: false });
      if (error) throw error;
      return res.status(200).json({ documents: data });
    }

    if (req.method === "DELETE") {
      const id = (req.query.id as string) ?? req.body?.id;
      if (!id) return res.status(400).json({ error: "Falta 'id'" });
      const { error } = await supabase.from("documents").delete().eq("id", id);
      if (error) throw error;
      return res.status(200).json({ ok: true });
    }

    return res.status(405).json({ error: "Method not allowed" });
  } catch (err) {
    console.error("documents error:", err);
    return res.status(500).json({ error: "Error al acceder a los documentos" });
  }
}
__PYME_COPILOT_EOF__

cat > "api/ingest.ts" <<'__PYME_COPILOT_EOF__'
import type { VercelRequest, VercelResponse } from "@vercel/node";
import { supabase } from "./_lib/supabase";
import { chunkText } from "./_lib/chunk";
import { embedDocuments } from "./_lib/gemini";

const CATEGORIES = ["legal", "contable", "administrativo", "general"];
const MAX_CHARS = 200_000;

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "POST") return res.status(405).json({ error: "Method not allowed" });

  try {
    const { title, text, category = "general", source } = req.body ?? {};

    if (!title || typeof title !== "string") return res.status(400).json({ error: "Falta 'title'" });
    if (!text || typeof text !== "string" || text.trim().length < 20)
      return res.status(400).json({ error: "El documento está vacío o es demasiado corto" });
    if (text.length > MAX_CHARS)
      return res.status(413).json({ error: `El documento supera ${MAX_CHARS} caracteres` });

    const cat = CATEGORIES.includes(category) ? category : "general";
    const chunks = chunkText(text);
    if (chunks.length === 0) return res.status(400).json({ error: "No se pudo extraer contenido" });

    const { data: doc, error: docErr } = await supabase
      .from("documents")
      .insert({ title: title.trim(), category: cat, source: source ?? null, char_count: text.length })
      .select("id, title, category, char_count, created_at")
      .single();
    if (docErr) throw docErr;

    const embeddings = await embedDocuments(chunks);
    const rows = chunks.map((content, i) => ({
      document_id: doc.id,
      chunk_index: i,
      content,
      embedding: embeddings[i],
    }));

    const { error: chunkErr } = await supabase.from("chunks").insert(rows);
    if (chunkErr) {
      await supabase.from("documents").delete().eq("id", doc.id);
      throw chunkErr;
    }

    return res.status(200).json({ document: doc, chunks: chunks.length });
  } catch (err) {
    console.error("ingest error:", err);
    return res.status(500).json({ error: "No se pudo procesar el documento" });
  }
}
__PYME_COPILOT_EOF__

cat > "api/query.ts" <<'__PYME_COPILOT_EOF__'
import type { VercelRequest, VercelResponse } from "@vercel/node";
import { supabase } from "./_lib/supabase";
import { embedQuery, generateAnswer, type Passage } from "./_lib/gemini";

const MATCH_COUNT = 6;
const MIN_SIMILARITY = 0.35; // below this, retrieved chunks are treated as irrelevant

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "POST") return res.status(405).json({ error: "Method not allowed" });

  try {
    const { question, category } = req.body ?? {};
    if (!question || typeof question !== "string" || question.trim().length < 3)
      return res.status(400).json({ error: "Escribe una pregunta" });

    const queryEmbedding = await embedQuery(question.trim());

    const { data: matches, error } = await supabase.rpc("match_chunks", {
      query_embedding: queryEmbedding,
      match_count: MATCH_COUNT,
      filter_category: category && category !== "all" ? category : null,
    });
    if (error) throw error;

    const relevant = (matches ?? []).filter((m: any) => m.similarity >= MIN_SIMILARITY);

    if (relevant.length === 0) {
      return res.status(200).json({
        answer:
          "No encuentro nada sobre esto en tus documentos. Sube el documento relevante (un contrato, una factura, un modelo fiscal…) y vuelve a preguntar.",
        sources: [],
      });
    }

    const passages: Passage[] = relevant.map((m: any, i: number) => ({
      n: i + 1,
      documentTitle: m.document_title,
      category: m.category,
      content: m.content,
    }));

    const answer = await generateAnswer(question.trim(), passages);

    const sources = relevant.map((m: any, i: number) => ({
      n: i + 1,
      documentId: m.document_id,
      documentTitle: m.document_title,
      category: m.category,
      chunkIndex: m.chunk_index,
      similarity: Number(m.similarity.toFixed(3)),
      excerpt: m.content,
    }));

    return res.status(200).json({ answer, sources });
  } catch (err) {
    console.error("query error:", err);
    return res.status(500).json({ error: "No se pudo responder la consulta" });
  }
}
__PYME_COPILOT_EOF__

cat > "api/_lib/chunk.ts" <<'__PYME_COPILOT_EOF__'
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

const SYSTEM = `Eres el copiloto de una micro-empresa. Respondes preguntas de tipo legal, contable y administrativo APOYÁNDOTE ÚNICAMENTE en los fragmentos de documentos que se te entregan.

Reglas:
- Usa solo la información de los fragmentos. Si la respuesta no está ahí, dilo con claridad ("No encuentro esto en tus documentos") y sugiere qué documento haría falta.
- Cita cada afirmación con el número del fragmento entre corchetes, por ejemplo [1] o [2][3].
- No inventes cifras, plazos, artículos ni cláusulas. Si dudas, no lo afirmes.
- Responde en el idioma de la pregunta, de forma directa y breve.
- No eres un abogado ni un asesor fiscal colegiado: cierra con una línea recordando que conviene validar decisiones críticas con un profesional.`;

export async function generateAnswer(question: string, passages: Passage[]): Promise<string> {
  const context = passages
    .map((p) => `[${p.n}] (${p.category} — ${p.documentTitle})\n${p.content}`)
    .join("\n\n");

  const prompt = `${SYSTEM}\n\n=== FRAGMENTOS ===\n${context}\n\n=== PREGUNTA ===\n${question}`;

  const res = await ai.models.generateContent({
    model: CHAT_MODEL,
    contents: prompt,
    config: { temperature: 0.2 },
  });
  return res.text ?? "No pude generar una respuesta.";
}
__PYME_COPILOT_EOF__

cat > "api/_lib/supabase.ts" <<'__PYME_COPILOT_EOF__'
import { createClient } from "@supabase/supabase-js";

// Service role key: server-side only. Never ships to the browser.
export const supabase = createClient(
  process.env.SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!,
  { auth: { persistSession: false } }
);
__PYME_COPILOT_EOF__

cat > "public/favicon.svg" <<'__PYME_COPILOT_EOF__'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32">
  <rect width="32" height="32" rx="7" fill="#0d5b45" />
  <rect x="9" y="7" width="14" height="18" rx="2" fill="#fbfbf8" />
  <rect x="11.5" y="14.5" width="9" height="3" fill="#f4d35e" />
  <rect x="11.5" y="10.5" width="6" height="1.6" rx="0.8" fill="#565a5f" />
  <rect x="11.5" y="20" width="9" height="1.6" rx="0.8" fill="#565a5f" />
</svg>
__PYME_COPILOT_EOF__

cat > "sample-docs/contrato-alquiler-local.md" <<'__PYME_COPILOT_EOF__'
# Contrato de arrendamiento de local de negocio (EJEMPLO FICTICIO)

En Madrid, a 3 de febrero de 2025, entre INMOBILIARIA CANDELA S.L. (la Arrendadora) y ESTUDIO NÓRDICA S.L. (la Arrendataria) se acuerda el arrendamiento del local sito en Calle del Amparo 14, bajo, 28012 Madrid.

**Primera. Objeto.** El local se destina exclusivamente a actividad de estudio de diseño. Cualquier otro uso requiere autorización escrita de la Arrendadora.

**Segunda. Duración.** El contrato tiene una duración de tres (3) años, con inicio el 1 de marzo de 2025 y vencimiento el 28 de febrero de 2028.

**Tercera. Renovación.** Llegado el vencimiento, el contrato se prorrogará automáticamente por periodos anuales, salvo que cualquiera de las partes comunique a la otra su voluntad de no renovar mediante notificación fehaciente con una antelación mínima de dos (2) meses a la fecha de vencimiento.

**Cuarta. Renta.** La renta mensual es de mil doscientos euros (1.200 €), pagaderos dentro de los cinco (5) primeros días de cada mes mediante transferencia. La renta se actualizará anualmente conforme a la variación del IPC.

**Quinta. Fianza.** La Arrendataria entrega una fianza equivalente a dos (2) mensualidades, es decir, dos mil cuatrocientos euros (2.400 €).

**Sexta. Obras.** Las obras de conservación ordinaria corresponden a la Arrendataria. Las obras estructurales corresponden a la Arrendadora.

**Séptima. Resolución anticipada.** La Arrendataria podrá desistir del contrato una vez transcurridos seis (6) meses, preavisando con treinta (30) días. En tal caso, indemnizará con una mensualidad de renta por cada año de contrato que reste por cumplir.
__PYME_COPILOT_EOF__

cat > "sample-docs/factura-2025-041.md" <<'__PYME_COPILOT_EOF__'
# Factura Nº 2025-041 (EJEMPLO FICTICIO)

**Emisor:** Estudio Nórdica S.L. — NIF B-88991122 — Calle del Amparo 14, 28012 Madrid
**Cliente:** Panadería La Espiga S.L. — NIF B-77445566
**Fecha de emisión:** 12 de junio de 2025
**Fecha de vencimiento:** 12 de julio de 2025 (pago a 30 días)

| Concepto | Cantidad | Precio unitario | Importe |
|---|---|---|---|
| Diseño de identidad de marca | 1 | 1.500,00 € | 1.500,00 € |
| Diseño de packaging (3 formatos) | 3 | 200,00 € | 600,00 € |

**Base imponible:** 2.100,00 €
**IVA (21%):** 441,00 €
**Retención IRPF (15%):** −315,00 €
**Total a pagar:** 2.226,00 €

Forma de pago: transferencia bancaria. El tipo de IVA aplicado es el general del 21%, correspondiente a servicios de diseño gráfico. La retención de IRPF del 15% aplica por tratarse de una actividad profesional facturada a otra empresa.
__PYME_COPILOT_EOF__

cat > "sample-docs/notas-modelo-303.md" <<'__PYME_COPILOT_EOF__'
# Notas internas — Modelo 303 (IVA) (EJEMPLO FICTICIO)

El Modelo 303 es la autoliquidación trimestral del IVA. Nuestra empresa lo presenta con periodicidad trimestral.

**Plazos de presentación:**
- Primer trimestre (enero–marzo): del 1 al 20 de abril.
- Segundo trimestre (abril–junio): del 1 al 20 de julio.
- Tercer trimestre (julio–septiembre): del 1 al 20 de octubre.
- Cuarto trimestre (octubre–diciembre): del 1 al 30 de enero del año siguiente.

Si el resultado sale a ingresar y se domicilia el pago, la presentación se adelanta al día 15 del mes correspondiente.

**Recordatorio interno:** junto con el 303 del cuarto trimestre se presenta el Modelo 390 (resumen anual de IVA), también hasta el 30 de enero.

En caso de resultado negativo (a compensar), se arrastra el saldo a los trimestres siguientes del mismo ejercicio. La compensación con Hacienda solo puede solicitarse en el último trimestre del año.
__PYME_COPILOT_EOF__

cat > "src/App.tsx" <<'__PYME_COPILOT_EOF__'
import { useEffect, useState } from "react";
import { listDocuments, deleteDocument, type Doc } from "./lib/api";
import { CATEGORY_LABEL } from "./lib/categories";
import Uploader from "./components/Uploader";
import Chat from "./components/Chat";

export default function App() {
  const [docs, setDocs] = useState<Doc[]>([]);
  const [loading, setLoading] = useState(true);

  async function refresh() {
    try {
      const { documents } = await listDocuments();
      setDocs(documents);
    } catch {
      /* API not reachable yet — the empty state still guides the user */
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    refresh();
  }, []);

  async function remove(id: string) {
    setDocs((d) => d.filter((x) => x.id !== id));
    await deleteDocument(id).catch(refresh);
  }

  return (
    <div className="flex min-h-screen flex-col">
      <header className="flex h-16 items-center gap-3 border-b border-line px-5">
        <div className="flex h-8 w-8 items-center justify-center rounded-md bg-viridian text-surface">
          <span className="font-display text-lg font-semibold leading-none">P</span>
        </div>
        <div>
          <h1 className="font-display text-lg font-semibold leading-tight">PYME Copilot</h1>
          <p className="text-xs text-ink-soft">Asesor IA anclado en los documentos de tu negocio</p>
        </div>
        <a
          href="https://github.com/MarcosJVPR"
          className="ml-auto font-mono text-xs text-ink-soft underline-offset-2 hover:text-viridian hover:underline"
        >
          RAG · Gemini · Supabase pgvector
        </a>
      </header>

      <main className="flex-1 lg:h-[calc(100vh-4rem)] lg:overflow-hidden">
        <div className="mx-auto grid h-full max-w-6xl grid-cols-1 lg:grid-cols-[340px_1fr]">
          <aside className="flex flex-col gap-4 border-line p-5 lg:h-full lg:overflow-y-auto lg:border-r">
            <div>
              <h2 className="font-display text-lg font-semibold">Archivo</h2>
              <p className="text-xs text-ink-soft">
                Sube contratos, facturas, nóminas, modelos… Se trocean, se indexan y quedan
                consultables.
              </p>
            </div>

            <Uploader onAdded={refresh} />

            <div className="mt-1">
              <p className="mb-2 font-mono text-xs uppercase tracking-wide text-ink-soft">
                {loading ? "Cargando…" : `${docs.length} documento${docs.length === 1 ? "" : "s"}`}
              </p>
              <ul className="space-y-1.5">
                {docs.map((d) => (
                  <li
                    key={d.id}
                    className="group flex items-center gap-2 rounded-lg border border-line bg-surface px-3 py-2"
                  >
                    <div className="min-w-0">
                      <p className="truncate text-sm font-medium text-ink">{d.title}</p>
                      <p className="font-mono text-[10px] text-ink-soft">
                        {CATEGORY_LABEL[d.category]} · {(d.char_count / 1000).toFixed(1)}k car.
                      </p>
                    </div>
                    <button
                      onClick={() => remove(d.id)}
                      aria-label={`Eliminar ${d.title}`}
                      className="ml-auto rounded p-1 text-ink-soft opacity-0 transition-opacity hover:text-red-700 focus:opacity-100 group-hover:opacity-100"
                    >
                      ✕
                    </button>
                  </li>
                ))}
              </ul>
            </div>
          </aside>

          <section className="min-h-[70vh] lg:h-full lg:min-h-0">
            <Chat docCount={docs.length} />
          </section>
        </div>
      </main>
    </div>
  );
}
__PYME_COPILOT_EOF__

cat > "src/index.css" <<'__PYME_COPILOT_EOF__'
@import url("https://fonts.googleapis.com/css2?family=Fraunces:opsz,wght@9..144,400;9..144,500;9..144,600;9..144,700&family=IBM+Plex+Sans:wght@400;500;600;700&family=IBM+Plex+Mono:wght@400;500&display=swap");
@import "tailwindcss";

@theme {
  --color-paper: #eceae2;
  --color-surface: #fbfbf8;
  --color-ink: #17191c;
  --color-ink-soft: #565a5f;
  --color-line: #dbd8cd;
  --color-viridian: #0d5b45;
  --color-viridian-ink: #0a4636;
  --color-highlight: #f4d35e;

  --font-display: "Fraunces", Georgia, serif;
  --font-sans: "IBM Plex Sans", system-ui, sans-serif;
  --font-mono: "IBM Plex Mono", ui-monospace, monospace;
}

@layer base {
  html {
    -webkit-text-size-adjust: 100%;
  }
  body {
    margin: 0;
    background-color: var(--color-paper);
    color: var(--color-ink);
    font-family: var(--font-sans);
    -webkit-font-smoothing: antialiased;
  }
  * {
    box-sizing: border-box;
  }
  ::selection {
    background: var(--color-highlight);
    color: var(--color-ink);
  }
}

/* Signature: citations look like little highlighter tabs pressed onto the page. */
.cite {
  font-family: var(--font-mono);
  font-size: 0.72em;
  font-weight: 500;
  background: var(--color-highlight);
  color: var(--color-ink);
  padding: 0.05em 0.35em;
  border-radius: 3px;
  box-decoration-break: clone;
  cursor: default;
  vertical-align: baseline;
}

/* Source excerpts read like a passage marked with a highlighter in the margin. */
.marked {
  background: linear-gradient(transparent 62%, color-mix(in srgb, var(--color-highlight) 55%, transparent) 62%);
}

@media (prefers-reduced-motion: reduce) {
  * {
    animation-duration: 0.01ms !important;
    transition-duration: 0.01ms !important;
  }
}
__PYME_COPILOT_EOF__

cat > "src/main.tsx" <<'__PYME_COPILOT_EOF__'
import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import App from "./App.tsx";
import "./index.css";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <App />
  </StrictMode>
);
__PYME_COPILOT_EOF__

cat > "src/components/Chat.tsx" <<'__PYME_COPILOT_EOF__'
import { useRef, useState, type ReactNode } from "react";
import { askQuestion, type Category, type Source } from "../lib/api";
import { CATEGORY_LABEL } from "../lib/categories";
import SourceList from "./SourceList";

type Msg = { role: "user" } | { role: "assistant"; sources: Source[] };
type Turn = Msg & { text: string; id: number };

const SAMPLES = [
  "¿Cuándo vence y cómo se renueva este contrato?",
  "¿Qué tipo de IVA aplico en esta factura?",
  "¿Qué plazo tengo para presentar este modelo?",
  "Resume mis obligaciones de este documento.",
];

function renderCitations(text: string): ReactNode[] {
  return text.split(/(\[\d+\])/g).map((part, i) => {
    const m = part.match(/^\[(\d+)\]$/);
    return m ? (
      <sup key={i} className="cite">
        {m[1]}
      </sup>
    ) : (
      <span key={i}>{part}</span>
    );
  });
}

export default function Chat({ docCount }: { docCount: number }) {
  const [turns, setTurns] = useState<Turn[]>([]);
  const [input, setInput] = useState("");
  const [filter, setFilter] = useState<Category | "all">("all");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const nextId = useRef(0);

  async function ask(question: string) {
    const q = question.trim();
    if (!q || busy) return;
    setError(null);
    setInput("");
    setTurns((t) => [...t, { role: "user", text: q, id: nextId.current++ }]);
    setBusy(true);
    try {
      const res = await askQuestion(q, filter);
      setTurns((t) => [
        ...t,
        { role: "assistant", text: res.answer, sources: res.sources, id: nextId.current++ },
      ]);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="flex h-full flex-col">
      <div className="flex items-center gap-2 border-b border-line px-5 py-3">
        <h2 className="font-display text-lg font-semibold">Consulta</h2>
        <select
          value={filter}
          onChange={(e) => setFilter(e.target.value as Category | "all")}
          className="ml-auto rounded-md border border-line bg-surface px-2 py-1 font-mono text-xs outline-none focus:border-viridian"
        >
          <option value="all">Todas las áreas</option>
          {(Object.keys(CATEGORY_LABEL) as Category[]).map((c) => (
            <option key={c} value={c}>
              {CATEGORY_LABEL[c]}
            </option>
          ))}
        </select>
      </div>

      <div className="flex-1 space-y-4 overflow-y-auto px-5 py-5">
        {turns.length === 0 && (
          <div className="mx-auto max-w-md pt-6 text-center">
            <p className="font-display text-xl text-ink">
              Pregunta como si tuvieras un equipo legal, contable y administrativo.
            </p>
            <p className="mt-2 text-sm text-ink-soft">
              {docCount === 0
                ? "Primero añade algún documento al archivo. Luego prueba una de estas:"
                : "Cada respuesta se ancla en tus documentos y cita el fragmento exacto. Prueba una:"}
            </p>
            <div className="mt-4 flex flex-wrap justify-center gap-2">
              {SAMPLES.map((s) => (
                <button
                  key={s}
                  onClick={() => ask(s)}
                  disabled={busy}
                  className="rounded-full border border-line bg-surface px-3 py-1.5 text-xs text-ink-soft transition-colors hover:border-viridian hover:text-ink disabled:opacity-40"
                >
                  {s}
                </button>
              ))}
            </div>
          </div>
        )}

        {turns.map((turn) =>
          turn.role === "user" ? (
            <div key={turn.id} className="flex justify-end">
              <div className="max-w-[85%] rounded-2xl rounded-br-sm bg-viridian px-4 py-2.5 text-sm text-surface">
                {turn.text}
              </div>
            </div>
          ) : (
            <div key={turn.id} className="max-w-[92%]">
              <div className="rounded-2xl rounded-bl-sm border border-line bg-surface px-4 py-3">
                <p className="whitespace-pre-wrap text-sm leading-relaxed text-ink">
                  {renderCitations(turn.text)}
                </p>
                <SourceList sources={turn.sources} />
              </div>
            </div>
          )
        )}

        {busy && (
          <div className="flex gap-1.5 px-2 text-ink-soft">
            <Dot /> <Dot delay="0.15s" /> <Dot delay="0.3s" />
          </div>
        )}
        {error && <p className="text-xs text-red-700">{error}</p>}
      </div>

      <div className="border-t border-line px-5 py-3">
        <div className="flex items-end gap-2">
          <textarea
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter" && !e.shiftKey) {
                e.preventDefault();
                ask(input);
              }
            }}
            rows={1}
            placeholder="Escribe tu pregunta…"
            className="max-h-32 flex-1 resize-none rounded-lg border border-line bg-surface px-3 py-2.5 text-sm outline-none placeholder:text-ink-soft/70 focus:border-viridian"
          />
          <button
            onClick={() => ask(input)}
            disabled={busy || input.trim().length < 3}
            className="rounded-lg bg-viridian px-4 py-2.5 text-sm font-semibold text-surface transition-opacity hover:bg-viridian-ink disabled:opacity-40"
          >
            Enviar
          </button>
        </div>
        <p className="mt-2 font-mono text-[10px] text-ink-soft">
          Orientativo. No sustituye a un abogado ni a un asesor fiscal colegiado.
        </p>
      </div>
    </div>
  );
}

function Dot({ delay = "0s" }: { delay?: string }) {
  return (
    <span
      className="inline-block h-2 w-2 animate-bounce rounded-full bg-ink-soft/60"
      style={{ animationDelay: delay }}
    />
  );
}
__PYME_COPILOT_EOF__

cat > "src/components/SourceList.tsx" <<'__PYME_COPILOT_EOF__'
import { useState } from "react";
import type { Source } from "../lib/api";
import { CATEGORY_LABEL } from "../lib/categories";

export default function SourceList({ sources }: { sources: Source[] }) {
  const [open, setOpen] = useState(false);
  if (sources.length === 0) return null;

  return (
    <div className="mt-3 border-t border-line pt-3">
      <button
        onClick={() => setOpen((o) => !o)}
        className="flex items-center gap-2 font-mono text-xs font-medium text-viridian"
      >
        <span>{open ? "▾" : "▸"}</span>
        {sources.length} {sources.length === 1 ? "fragmento citado" : "fragmentos citados"}
      </button>

      {open && (
        <ul className="mt-2 space-y-2">
          {sources.map((s) => (
            <li key={s.n} className="rounded-lg border border-line bg-paper/60 p-3">
              <div className="mb-1 flex items-center gap-2 text-xs">
                <span className="cite">{s.n}</span>
                <span className="font-medium text-ink">{s.documentTitle}</span>
                <span className="rounded bg-line/60 px-1.5 py-0.5 font-mono text-[10px] text-ink-soft">
                  {CATEGORY_LABEL[s.category]}
                </span>
                <span className="ml-auto font-mono text-[10px] text-ink-soft">
                  {Math.round(s.similarity * 100)}% afín
                </span>
              </div>
              <p className="text-xs leading-relaxed text-ink-soft">
                <span className="marked">{s.excerpt}</span>
              </p>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
__PYME_COPILOT_EOF__

cat > "src/components/Uploader.tsx" <<'__PYME_COPILOT_EOF__'
import { useRef, useState } from "react";
import { ingestDocument, type Category } from "../lib/api";
import { CATEGORY_LABEL, CATEGORY_OPTIONS } from "../lib/categories";
import { extractText } from "../lib/extract";

export default function Uploader({ onAdded }: { onAdded: () => void }) {
  const [title, setTitle] = useState("");
  const [category, setCategory] = useState<Category>("general");
  const [text, setText] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const fileRef = useRef<HTMLInputElement>(null);

  async function handleFile(file: File) {
    setError(null);
    setBusy(true);
    try {
      const extracted = await extractText(file);
      setText(extracted);
      if (!title) setTitle(file.name.replace(/\.[^.]+$/, ""));
    } catch {
      setError("No pude leer ese archivo. Prueba con un .pdf, .txt, .md o .csv.");
    } finally {
      setBusy(false);
    }
  }

  async function submit() {
    setError(null);
    setBusy(true);
    try {
      await ingestDocument({ title: title.trim(), text, category, source: title.trim() });
      setTitle("");
      setText("");
      setCategory("general");
      if (fileRef.current) fileRef.current.value = "";
      onAdded();
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }

  const ready = title.trim().length > 1 && text.trim().length > 19 && !busy;

  return (
    <div className="space-y-3">
      <label
        className="flex cursor-pointer flex-col items-center justify-center gap-1 rounded-lg border border-dashed border-line bg-surface px-4 py-6 text-center transition-colors hover:border-viridian"
        onDragOver={(e) => e.preventDefault()}
        onDrop={(e) => {
          e.preventDefault();
          if (e.dataTransfer.files[0]) handleFile(e.dataTransfer.files[0]);
        }}
      >
        <span className="text-sm font-medium text-ink">Arrastra un archivo o elígelo</span>
        <span className="font-mono text-xs text-ink-soft">PDF · TXT · MD · CSV</span>
        <input
          ref={fileRef}
          type="file"
          accept=".pdf,.txt,.md,.csv,.markdown"
          className="hidden"
          onChange={(e) => e.target.files?.[0] && handleFile(e.target.files[0])}
        />
      </label>

      <input
        value={title}
        onChange={(e) => setTitle(e.target.value)}
        placeholder="Título (p. ej. Contrato de alquiler local)"
        className="w-full rounded-lg border border-line bg-surface px-3 py-2 text-sm outline-none placeholder:text-ink-soft/70 focus:border-viridian"
      />

      <div className="flex gap-2">
        {CATEGORY_OPTIONS.map((c) => (
          <button
            key={c}
            onClick={() => setCategory(c)}
            className={`flex-1 rounded-md border px-2 py-1.5 text-xs font-medium transition-colors ${
              category === c
                ? "border-viridian bg-viridian text-surface"
                : "border-line bg-surface text-ink-soft hover:border-viridian"
            }`}
          >
            {CATEGORY_LABEL[c]}
          </button>
        ))}
      </div>

      <textarea
        value={text}
        onChange={(e) => setText(e.target.value)}
        placeholder="…o pega aquí el texto del documento"
        rows={4}
        className="w-full resize-y rounded-lg border border-line bg-surface px-3 py-2 text-sm outline-none placeholder:text-ink-soft/70 focus:border-viridian"
      />

      {error && <p className="text-xs text-red-700">{error}</p>}

      <button
        onClick={submit}
        disabled={!ready}
        className="w-full rounded-lg bg-viridian px-4 py-2.5 text-sm font-semibold text-surface transition-opacity hover:bg-viridian-ink disabled:cursor-not-allowed disabled:opacity-40"
      >
        {busy ? "Procesando…" : "Añadir al archivo"}
      </button>
    </div>
  );
}
__PYME_COPILOT_EOF__

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

export function listDocuments(): Promise<{ documents: Doc[] }> {
  return fetch("/api/documents").then((r) => json<{ documents: Doc[] }>(r));
}

export function ingestDocument(payload: {
  title: string;
  text: string;
  category: Category;
  source?: string;
}): Promise<{ document: Doc; chunks: number }> {
  return fetch("/api/ingest", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  }).then((r) => json<{ document: Doc; chunks: number }>(r));
}

export function deleteDocument(id: string): Promise<{ ok: true }> {
  return fetch(`/api/documents?id=${encodeURIComponent(id)}`, { method: "DELETE" }).then((r) =>
    json<{ ok: true }>(r)
  );
}

export function askQuestion(question: string, category: Category | "all"): Promise<Answer> {
  return fetch("/api/query", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ question, category }),
  }).then((r) => json<Answer>(r));
}
__PYME_COPILOT_EOF__

cat > "src/lib/categories.ts" <<'__PYME_COPILOT_EOF__'
import type { Category } from "./api";

export const CATEGORY_LABEL: Record<Category, string> = {
  legal: "Legal",
  contable: "Contable",
  administrativo: "Administrativo",
  general: "General",
};

export const CATEGORY_OPTIONS: Category[] = ["legal", "contable", "administrativo", "general"];
__PYME_COPILOT_EOF__

cat > "src/lib/extract.ts" <<'__PYME_COPILOT_EOF__'
import * as pdfjs from "pdfjs-dist";
import workerUrl from "pdfjs-dist/build/pdf.worker.min.mjs?url";

pdfjs.GlobalWorkerOptions.workerSrc = workerUrl;

export async function extractText(file: File): Promise<string> {
  if (file.name.toLowerCase().endsWith(".pdf")) {
    const data = await file.arrayBuffer();
    const pdf = await pdfjs.getDocument({ data }).promise;
    const pages: string[] = [];
    for (let i = 1; i <= pdf.numPages; i++) {
      const page = await pdf.getPage(i);
      const content = await page.getTextContent();
      pages.push(content.items.map((it: any) => ("str" in it ? it.str : "")).join(" "));
    }
    return pages.join("\n\n").trim();
  }
  return (await file.text()).trim();
}
__PYME_COPILOT_EOF__

cat > "supabase/schema.sql" <<'__PYME_COPILOT_EOF__'
-- PYME Copilot — Supabase schema
-- Run this in the Supabase SQL editor (or `supabase db push`).
-- Embeddings: gemini-embedding-001 truncated to 768 dims (Matryoshka), cosine distance.

create extension if not exists vector;

create table if not exists documents (
  id           uuid primary key default gen_random_uuid(),
  title        text not null,
  category     text not null default 'general',      -- legal | contable | administrativo | general
  source       text,                                  -- file name or origin
  char_count   int  not null default 0,
  created_at   timestamptz not null default now()
);

create table if not exists chunks (
  id           uuid primary key default gen_random_uuid(),
  document_id  uuid not null references documents(id) on delete cascade,
  chunk_index  int  not null,
  content      text not null,
  embedding    vector(768) not null,
  created_at   timestamptz not null default now()
);

create index if not exists chunks_document_id_idx on chunks (document_id);

-- HNSW index for fast cosine similarity search.
create index if not exists chunks_embedding_idx
  on chunks using hnsw (embedding vector_cosine_ops);

-- Similarity search. Returns the closest chunks with a 0..1 similarity score.
create or replace function match_chunks(
  query_embedding vector(768),
  match_count int default 6,
  filter_category text default null
)
returns table (
  id uuid,
  document_id uuid,
  document_title text,
  category text,
  chunk_index int,
  content text,
  similarity float
)
language sql stable
as $$
  select
    c.id,
    c.document_id,
    d.title as document_title,
    d.category,
    c.chunk_index,
    c.content,
    1 - (c.embedding <=> query_embedding) as similarity
  from chunks c
  join documents d on d.id = c.document_id
  where filter_category is null or d.category = filter_category
  order by c.embedding <=> query_embedding
  limit match_count;
$$;

-- Lock the tables down. All access goes through the serverless API using the
-- service_role key (server-side only), which bypasses RLS. The anon key can't
-- read or write anything, so nothing is exposed to the browser.
alter table documents enable row level security;
alter table chunks    enable row level security;
__PYME_COPILOT_EOF__

echo "→ Removing stale loose files from repo root (if any)…"
for f in "App.tsx" "main.tsx" "index.css" "api.ts" "categories.ts" "extract.ts" "gemini.ts" "supabase.ts" "chunk.ts" "documents.ts" "ingest.ts" "query.ts" "schema.sql" "Chat.tsx" "SourceList.tsx" "Uploader.tsx" "favicon.svg" "contrato-alquiler-local.md" "factura-2025-041.md" "notas-modelo-303.md" "env.example" "download"; do
  [ -f "./$f" ] && rm -f "./$f" && echo "   removed ./$f" || true
done

echo ""
echo "✓ Done. Structure:"
command -v tree >/dev/null && tree -a -I 'node_modules' || find . -type f -not -path './node_modules/*' | sort
echo ""
echo "Next:  npm install   then   cp .env.example .env  (fill it)   then   npm run dev:full"
