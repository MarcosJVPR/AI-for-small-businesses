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

const post = (url: string, body: unknown) =>
  fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });

export function listDocuments(): Promise<{ documents: Doc[] }> {
  return fetch("/api/documents").then((r) => json<{ documents: Doc[] }>(r));
}

export function deleteDocument(id: string): Promise<{ ok: true }> {
  return fetch(`/api/documents?id=${encodeURIComponent(id)}`, { method: "DELETE" }).then((r) =>
    json<{ ok: true }>(r)
  );
}

export function createDocument(payload: {
  title: string;
  category: Category;
  source?: string;
  charCount: number;
}): Promise<{ document: Doc }> {
  return post("/api/ingest", payload).then((r) => json<{ document: Doc }>(r));
}

export function storeChunks(
  documentId: string,
  chunks: string[],
  startIndex: number
): Promise<{ added: number }> {
  return post("/api/chunks", { documentId, chunks, startIndex }).then((r) =>
    json<{ added: number }>(r)
  );
}

export function ocr(imageBase64: string, mimeType: string): Promise<{ text: string }> {
  return post("/api/ocr", { imageBase64, mimeType }).then((r) => json<{ text: string }>(r));
}

export function askQuestion(
  question: string,
  category: Category | "all",
  useWeb = false
): Promise<Answer> {
  return post("/api/query", { question, category, useWeb }).then((r) => json<Answer>(r));
}
