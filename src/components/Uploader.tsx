import { useRef, useState } from "react";
import { ingestDocument, type Category } from "../lib/api";
import { CATEGORY_LABEL, CATEGORY_OPTIONS } from "../lib/categories";
import { extractText } from "../lib/extract";

export default function Uploader({ onAdded }: { onAdded: () => void }) {
  const [title, setTitle] = useState("");
  const [category, setCategory] = useState<Category>("general");
  const [text, setText] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const fileRef = useRef<HTMLInputElement>(null);

  async function handleFile(file: File) {
    setError(null);
    setBusy(true);
    try {
      const extracted = await extractText(file);
      setText(extracted);
      if (!title) setTitle(file.name.replace(/\.[^.]+$/, ""));
    } catch {
      setError("No pude leer ese archivo. Prueba con un .pdf, .txt, .md o .csv.");
    } finally {
      setBusy(false);
    }
  }

  async function submit() {
    setError(null);
    setBusy(true);
    try {
      await ingestDocument({ title: title.trim(), text, category, source: title.trim() });
      setTitle("");
      setText("");
      setCategory("general");
      if (fileRef.current) fileRef.current.value = "";
      onAdded();
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }

  const ready = title.trim().length > 1 && text.trim().length > 19 && !busy;

  return (
    <div className="space-y-3">
      <label
        className="flex cursor-pointer flex-col items-center justify-center gap-1 rounded-lg border border-dashed border-line bg-surface px-4 py-6 text-center transition-colors hover:border-viridian"
        onDragOver={(e) => e.preventDefault()}
        onDrop={(e) => {
          e.preventDefault();
          if (e.dataTransfer.files[0]) handleFile(e.dataTransfer.files[0]);
        }}
      >
        <span className="text-sm font-medium text-ink">Arrastra un archivo o elígelo</span>
        <span className="font-mono text-xs text-ink-soft">PDF · TXT · MD · CSV</span>
        <input
          ref={fileRef}
          type="file"
          accept=".pdf,.txt,.md,.csv,.markdown"
          className="hidden"
          onChange={(e) => e.target.files?.[0] && handleFile(e.target.files[0])}
        />
      </label>

      <input
        value={title}
        onChange={(e) => setTitle(e.target.value)}
        placeholder="Título (p. ej. Contrato de alquiler local)"
        className="w-full rounded-lg border border-line bg-surface px-3 py-2 text-sm outline-none placeholder:text-ink-soft/70 focus:border-viridian"
      />

      <div className="flex gap-2">
        {CATEGORY_OPTIONS.map((c) => (
          <button
            key={c}
            onClick={() => setCategory(c)}
            className={`flex-1 rounded-md border px-2 py-1.5 text-xs font-medium transition-colors ${
              category === c
                ? "border-viridian bg-viridian text-surface"
                : "border-line bg-surface text-ink-soft hover:border-viridian"
            }`}
          >
            {CATEGORY_LABEL[c]}
          </button>
        ))}
      </div>

      <textarea
        value={text}
        onChange={(e) => setText(e.target.value)}
        placeholder="…o pega aquí el texto del documento"
        rows={4}
        className="w-full resize-y rounded-lg border border-line bg-surface px-3 py-2 text-sm outline-none placeholder:text-ink-soft/70 focus:border-viridian"
      />

      {error && <p className="text-xs text-red-700">{error}</p>}

      <button
        onClick={submit}
        disabled={!ready}
        className="w-full rounded-lg bg-viridian px-4 py-2.5 text-sm font-semibold text-surface transition-opacity hover:bg-viridian-ink disabled:cursor-not-allowed disabled:opacity-40"
      >
        {busy ? "Procesando…" : "Añadir al archivo"}
      </button>
    </div>
  );
}
