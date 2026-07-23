import type { VercelRequest, VercelResponse } from "@vercel/node";
import { supabase } from "./_lib/supabase.js";
import { embedQuery, generateAnswer, type Passage } from "./_lib/gemini.js";

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
