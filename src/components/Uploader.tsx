import { useRef, useState } from "react";
import { createDocument, storeChunks, deleteDocument, type Category } from "../lib/api";
import { CATEGORY_LABEL, CATEGORY_OPTIONS } from "../lib/categories";
import { extractText, type Progress } from "../lib/extract";
import { chunkText } from "../lib/chunk";

const BATCH = 15;

type Status = "reading" | "ocr" | "indexing" | "done" | "error";
type Item = { id: number; name: string; status: Status; detail: string };

function guessCategory(name: string): Category {
  const n = name.toLowerCase();
  if (/(contrato|acuerdo|nda|clausul|arrendamiento|laboral|estatuto|convenio|escritura)/.test(n))
    return "legal";
  if (/(factura|iva|nomina|nómina|modelo|303|130|349|390|impuesto|contab|balance|libro|ticket)/.test(n))
    return "contable";
  if (/(permiso|licencia|registro|solicitud|tramite|trámite|certificado|alta|baja)/.test(n))
    return "administrativo";
  return "general";
}

const STATUS_DOT: Record<Status, string> = {
  reading: "bg-highlight animate-pulse",
  ocr: "bg-highlight animate-pulse",
  indexing: "bg-highlight animate-pulse",
  done: "bg-viridian",
  error: "bg-red-600",
};

export default function Uploader({ onAdded }: { onAdded: () => void }) {
  const [items, setItems] = useState<Item[]>([]);
  const [category, setCategory] = useState<Category | "auto">("auto");
  const [pasteOpen, setPasteOpen] = useState(false);
  const [pasteTitle, setPasteTitle] = useState("");
  const [pasteText, setPasteText] = useState("");
  const nextId = useRef(0);
  const fileRef = useRef<HTMLInputElement>(null);

  const busy = items.some((i) => i.status === "reading" || i.status === "ocr" || i.status === "indexing");

  function update(id: number, patch: Partial<Item>) {
    setItems((list) => list.map((it) => (it.id === id ? { ...it, ...patch } : it)));
  }

  async function ingestText(name: string, text: string, cat: Category, source: string, id: number) {
    const chunks = chunkText(text);
    if (chunks.length === 0) {
      update(id, { status: "error", detail: "Documento vacío tras el procesado" });
      return;
    }
    update(id, { status: "indexing", detail: `Indexando · 0/${chunks.length}` });
    const { document } = await createDocument({ title: name, category: cat, source, charCount: text.length });
    try {
      for (let i = 0; i < chunks.length; i += BATCH) {
        await storeChunks(document.id, chunks.slice(i, i + BATCH), i);
        update(id, { detail: `Indexando · ${Math.min(i + BATCH, chunks.length)}/${chunks.length}` });
      }
    } catch (e) {
      await deleteDocument(document.id).catch(() => {});
      throw e;
    }
    update(id, { status: "done", detail: `${chunks.length} fragmentos indexados` });
    onAdded();
  }

  async function processFile(file: File) {
    const id = nextId.current++;
    setItems((list) => [...list, { id, name: file.name, status: "reading", detail: "Leyendo…" }]);
    try {
      const text = await extractText(file, (p: Progress) =>
        update(id, {
          status: p.phase === "ocr" ? "ocr" : "reading",
          detail:
            p.phase === "ocr"
              ? `Reconociendo texto con IA · pág. ${p.page}/${p.total}`
              : `Leyendo · pág. ${p.page}/${p.total}`,
        })
      );
      if (text.trim().length < 20) {
        update(id, { status: "error", detail: "No se pudo extraer texto legible" });
        return;
      }
      const cat: Category = category === "auto" ? guessCategory(file.name) : category;
      await ingestText(file.name.replace(/\.[^.]+$/, ""), text, cat, file.name, id);
    } catch (e) {
      update(id, { status: "error", detail: (e as Error).message || "Error al procesar" });
    }
  }

  async function handleFiles(files: FileList | File[]) {
    for (const f of Array.from(files)) await processFile(f); // sequential: clear progress, gentle on rate limits
    if (fileRef.current) fileRef.current.value = "";
  }

  async function submitPaste() {
    if (pasteTitle.trim().length < 2 || pasteText.trim().length < 20) return;
    const id = nextId.current++;
    setItems((list) => [...list, { id, name: pasteTitle.trim(), status: "indexing", detail: "Indexando…" }]);
    const cat: Category = category === "auto" ? "general" : category;
    try {
      await ingestText(pasteTitle.trim(), pasteText, cat, "texto pegado", id);
      setPasteTitle("");
      setPasteText("");
      setPasteOpen(false);
    } catch (e) {
      update(id, { status: "error", detail: (e as Error).message });
    }
  }

  return (
    <div className="space-y-3">
      <label
        className="flex cursor-pointer flex-col items-center justify-center gap-1 rounded-lg border border-dashed border-line bg-surface px-4 py-6 text-center transition-colors hover:border-viridian"
        onDragOver={(e) => e.preventDefault()}
        onDrop={(e) => {
          e.preventDefault();
          if (e.dataTransfer.files.length) handleFiles(e.dataTransfer.files);
        }}
      >
        <span className="text-sm font-medium text-ink">Arrastra tus documentos o elígelos</span>
        <span className="font-mono text-xs text-ink-soft">
          PDF (también escaneados) · Word · imágenes · TXT · CSV
        </span>
        <input
          ref={fileRef}
          type="file"
          multiple
          accept=".pdf,.docx,.txt,.md,.csv,.png,.jpg,.jpeg,.webp,.gif,.bmp"
          className="hidden"
          onChange={(e) => e.target.files?.length && handleFiles(e.target.files)}
        />
      </label>

      <div className="flex items-center gap-2">
        <span className="font-mono text-[10px] uppercase tracking-wide text-ink-soft">Área</span>
        <select
          value={category}
          onChange={(e) => setCategory(e.target.value as Category | "auto")}
          className="flex-1 rounded-md border border-line bg-surface px-2 py-1.5 text-xs outline-none focus:border-viridian"
        >
          <option value="auto">Detectar automáticamente</option>
          {CATEGORY_OPTIONS.map((c) => (
            <option key={c} value={c}>
              {CATEGORY_LABEL[c]}
            </option>
          ))}
        </select>
      </div>

      {items.length > 0 && (
        <ul className="space-y-1.5">
          {items.map((it) => (
            <li key={it.id} className="flex items-start gap-2 rounded-lg border border-line bg-surface px-3 py-2">
              <span className={`mt-1.5 inline-block h-2 w-2 shrink-0 rounded-full ${STATUS_DOT[it.status]}`} />
              <div className="min-w-0">
                <p className="truncate text-sm font-medium text-ink">{it.name}</p>
                <p className={`font-mono text-[10px] ${it.status === "error" ? "text-red-700" : "text-ink-soft"}`}>
                  {it.detail}
                </p>
              </div>
            </li>
          ))}
        </ul>
      )}

      <button
        onClick={() => setPasteOpen((o) => !o)}
        className="font-mono text-xs text-viridian underline-offset-2 hover:underline"
      >
        {pasteOpen ? "▾ Pegar texto" : "▸ …o pegar texto a mano"}
      </button>

      {pasteOpen && (
        <div className="space-y-2">
          <input
            value={pasteTitle}
            onChange={(e) => setPasteTitle(e.target.value)}
            placeholder="Título"
            className="w-full rounded-lg border border-line bg-surface px-3 py-2 text-sm outline-none placeholder:text-ink-soft/70 focus:border-viridian"
          />
          <textarea
            value={pasteText}
            onChange={(e) => setPasteText(e.target.value)}
            placeholder="Pega aquí el texto del documento"
            rows={4}
            className="w-full resize-y rounded-lg border border-line bg-surface px-3 py-2 text-sm outline-none placeholder:text-ink-soft/70 focus:border-viridian"
          />
          <button
            onClick={submitPaste}
            disabled={busy || pasteTitle.trim().length < 2 || pasteText.trim().length < 20}
            className="w-full rounded-lg bg-viridian px-4 py-2.5 text-sm font-semibold text-surface transition-opacity hover:bg-viridian-ink disabled:opacity-40"
          >
            Añadir texto
          </button>
        </div>
      )}
    </div>
  );
}
