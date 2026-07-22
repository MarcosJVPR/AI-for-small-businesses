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
