import * as pdfjs from "pdfjs-dist";
import workerUrl from "pdfjs-dist/build/pdf.worker.min.mjs?url";
import * as mammoth from "mammoth/mammoth.browser";
import { ocr } from "./api";

pdfjs.GlobalWorkerOptions.workerSrc = workerUrl;

export type Progress = { phase: "reading" | "ocr"; page: number; total: number };
type OnProgress = (p: Progress) => void;

const OCR_MAX_PAGES = 60; // cap OCR on very long scans so a demo can't run away

export async function extractText(file: File, onProgress?: OnProgress): Promise<string> {
  const name = file.name.toLowerCase();
  if (name.endsWith(".pdf")) return extractPdf(file, onProgress);
  if (/\.(png|jpe?g|webp|gif|bmp)$/.test(name)) return extractImage(file, onProgress);
  if (name.endsWith(".docx")) {
    const arrayBuffer = await file.arrayBuffer();
    const { value } = await mammoth.extractRawText({ arrayBuffer });
    return value.trim();
  }
  return (await file.text()).trim();
}

async function extractPdf(file: File, onProgress?: OnProgress): Promise<string> {
  const data = await file.arrayBuffer();
  const pdf = await pdfjs.getDocument({ data }).promise;
  const total = pdf.numPages;

  const pagesText: string[] = [];
  for (let i = 1; i <= total; i++) {
    onProgress?.({ phase: "reading", page: i, total });
    const page = await pdf.getPage(i);
    const content = await page.getTextContent();
    pagesText.push(content.items.map((it: any) => ("str" in it ? it.str : "")).join(" "));
  }
  const joined = pagesText.join("\n\n").trim();

  // A real text layer yields plenty of characters. If it's nearly empty, the
  // PDF is scanned images → OCR each page instead.
  if (joined.replace(/\s/g, "").length >= total * 40) return joined;

  const limit = Math.min(total, OCR_MAX_PAGES);
  const ocrText: string[] = [];
  for (let i = 1; i <= limit; i++) {
    onProgress?.({ phase: "ocr", page: i, total: limit });
    const page = await pdf.getPage(i);
    const base64 = await renderPageToJpeg(page);
    const { text } = await ocr(base64, "image/jpeg");
    if (text.trim()) ocrText.push(text.trim());
  }
  return ocrText.join("\n\n").trim();
}

async function renderPageToJpeg(page: any): Promise<string> {
  const viewport = page.getViewport({ scale: 1.4 });
  const canvas = document.createElement("canvas");
  canvas.width = Math.ceil(viewport.width);
  canvas.height = Math.ceil(viewport.height);
  const ctx = canvas.getContext("2d")!;
  await page.render({ canvasContext: ctx, viewport }).promise;
  return canvas.toDataURL("image/jpeg", 0.8).split(",")[1];
}

async function extractImage(file: File, onProgress?: OnProgress): Promise<string> {
  onProgress?.({ phase: "ocr", page: 1, total: 1 });
  const base64 = await fileToBase64(file);
  const { text } = await ocr(base64, file.type || "image/jpeg");
  return text.trim();
}

function fileToBase64(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const r = new FileReader();
    r.onload = () => resolve(String(r.result).split(",")[1]);
    r.onerror = () => reject(new Error("No se pudo leer el archivo"));
    r.readAsDataURL(file);
  });
}
