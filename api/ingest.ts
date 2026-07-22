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
