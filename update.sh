
set -euo pipefail
echo "→ Updating 4 files for the web-search toggle…"

mkdir -p "api/_lib"
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
__PYME_COPILOT_EOF__
echo "   updated api/_lib/gemini.ts"

mkdir -p "api"
cat > "api/query.ts" <<'__PYME_COPILOT_EOF__'
import type { VercelRequest, VercelResponse } from "@vercel/node";
import { supabase } from "./_lib/supabase";
import { embedQuery, generateAnswer, type Passage } from "./_lib/gemini";

const MATCH_COUNT = 6;
const MIN_SIMILARITY = 0.35; // below this, retrieved chunks are treated as irrelevant

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "POST") return res.status(405).json({ error: "Method not allowed" });

  try {
    const { question, category, useWeb = false } = req.body ?? {};
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

    // Nothing in the documents. With web off (default) we stop here and say so —
    // we never fall back to the model's own knowledge. With web on, the user has
    // explicitly allowed a web-assisted answer.
    if (relevant.length === 0 && !useWeb) {
      return res.status(200).json({
        answer:
          "No encuentro nada sobre esto en tus documentos. Sube el documento relevante (un contrato, una factura, un modelo fiscal…) y vuelve a preguntar, o activa la búsqueda en internet.",
        sources: [],
      });
    }

    const passages: Passage[] = relevant.map((m: any, i: number) => ({
      n: i + 1,
      documentTitle: m.document_title,
      category: m.category,
      content: m.content,
    }));

    const answer = await generateAnswer(question.trim(), passages, Boolean(useWeb));

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
echo "   updated api/query.ts"

mkdir -p "src/lib"
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

export function askQuestion(
  question: string,
  category: Category | "all",
  useWeb = false
): Promise<Answer> {
  return fetch("/api/query", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ question, category, useWeb }),
  }).then((r) => json<Answer>(r));
}
__PYME_COPILOT_EOF__
echo "   updated src/lib/api.ts"

mkdir -p "src/components"
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
  const [web, setWeb] = useState(false);
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
      const res = await askQuestion(q, filter, web);
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
        <div className="mt-2 flex items-center justify-between gap-3">
          <button
            onClick={() => setWeb((w) => !w)}
            aria-pressed={web}
            className={`flex items-center gap-1.5 rounded-full border px-2.5 py-1 font-mono text-[10px] transition-colors ${
              web
                ? "border-viridian bg-viridian text-surface"
                : "border-line bg-surface text-ink-soft hover:border-viridian"
            }`}
          >
            <span
              className={`inline-block h-1.5 w-1.5 rounded-full ${web ? "bg-highlight" : "bg-ink-soft/40"}`}
            />
            {web ? "Internet: activado" : "Solo mis documentos"}
          </button>
          <p className="font-mono text-[10px] text-ink-soft">
            Orientativo. No sustituye a un profesional.
          </p>
        </div>
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
echo "   updated src/components/Chat.tsx"

echo ""
echo "✓ Done. Commit with:  git add -A && git commit -m \"web-search toggle\" && git push"
