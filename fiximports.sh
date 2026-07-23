#!/usr/bin/env bash
# Fixes ERR_MODULE_NOT_FOUND on Vercel: Node ESM requires explicit .js
# extensions on relative imports between your own files.
# Run from the repo root:  bash fiximports.sh
set -euo pipefail
echo "→ Restoring .js extensions on internal imports…"

cat > "api/ingest.ts" <<'__PYME_COPILOT_EOF__'
import type { VercelRequest, VercelResponse } from "@vercel/node";
import { supabase } from "./_lib/supabase.js";

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
echo "   fixed api/ingest.ts"

cat > "api/chunks.ts" <<'__PYME_COPILOT_EOF__'
import type { VercelRequest, VercelResponse } from "@vercel/node";
import { supabase } from "./_lib/supabase.js";
import { embedDocuments } from "./_lib/gemini.js";

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
echo "   fixed api/chunks.ts"

cat > "api/query.ts" <<'__PYME_COPILOT_EOF__'
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
__PYME_COPILOT_EOF__
echo "   fixed api/query.ts"

cat > "api/documents.ts" <<'__PYME_COPILOT_EOF__'
import type { VercelRequest, VercelResponse } from "@vercel/node";
import { supabase } from "./_lib/supabase.js";

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
echo "   fixed api/documents.ts"

cat > "api/ocr.ts" <<'__PYME_COPILOT_EOF__'
import type { VercelRequest, VercelResponse } from "@vercel/node";
import { ocrImage } from "./_lib/gemini.js";

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
echo "   fixed api/ocr.ts"

echo ""
echo "✓ Done. Commit and push to trigger a redeploy:"
echo "    git add -A && git commit -m \"fix: ESM import extensions\" && git push"
