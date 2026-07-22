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

export function listDocuments(): Promise<{ documents: Doc[] }> {
  return fetch("/api/documents").then((r) => json<{ documents: Doc[] }>(r));
}

export function ingestDocument(payload: {
  title: string;
  text: string;
  category: Category;
  source?: string;
}): Promise<{ document: Doc; chunks: number }> {
  return fetch("/api/ingest", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  }).then((r) => json<{ document: Doc; chunks: number }>(r));
}

export function deleteDocument(id: string): Promise<{ ok: true }> {
  return fetch(`/api/documents?id=${encodeURIComponent(id)}`, { method: "DELETE" }).then((r) =>
    json<{ ok: true }>(r)
  );
}

export function askQuestion(
  question: string,
  category: Category | "all",
  useWeb = false
): Promise<Answer> {
  return fetch("/api/query", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ question, category, useWeb }),
  }).then((r) => json<Answer>(r));
}
