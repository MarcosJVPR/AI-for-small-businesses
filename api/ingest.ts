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
