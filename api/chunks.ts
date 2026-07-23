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
