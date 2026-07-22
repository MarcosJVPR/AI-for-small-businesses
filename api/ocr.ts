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
