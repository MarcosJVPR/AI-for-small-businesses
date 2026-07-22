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
