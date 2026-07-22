import { useEffect, useState } from "react";
import { listDocuments, deleteDocument, type Doc } from "./lib/api";
import { CATEGORY_LABEL } from "./lib/categories";
import Uploader from "./components/Uploader";
import Chat from "./components/Chat";

export default function App() {
  const [docs, setDocs] = useState<Doc[]>([]);
  const [loading, setLoading] = useState(true);

  async function refresh() {
    try {
      const { documents } = await listDocuments();
      setDocs(documents);
    } catch {
      /* API not reachable yet — the empty state still guides the user */
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    refresh();
  }, []);

  async function remove(id: string) {
    setDocs((d) => d.filter((x) => x.id !== id));
    await deleteDocument(id).catch(refresh);
  }

  return (
    <div className="flex min-h-screen flex-col">
      <header className="flex h-16 items-center gap-3 border-b border-line px-5">
        <div className="flex h-8 w-8 items-center justify-center rounded-md bg-viridian text-surface">
          <span className="font-display text-lg font-semibold leading-none">P</span>
        </div>
        <div>
          <h1 className="font-display text-lg font-semibold leading-tight">PYME Copilot</h1>
          <p className="text-xs text-ink-soft">Asesor IA anclado en los documentos de tu negocio</p>
        </div>
        <a
          href="https://github.com/MarcosJVPR"
          className="ml-auto font-mono text-xs text-ink-soft underline-offset-2 hover:text-viridian hover:underline"
        >
          RAG · Gemini · Supabase pgvector
        </a>
      </header>

      <main className="flex-1 lg:h-[calc(100vh-4rem)] lg:overflow-hidden">
        <div className="mx-auto grid h-full max-w-6xl grid-cols-1 lg:grid-cols-[340px_1fr]">
          <aside className="flex flex-col gap-4 border-line p-5 lg:h-full lg:overflow-y-auto lg:border-r">
            <div>
              <h2 className="font-display text-lg font-semibold">Archivo</h2>
              <p className="text-xs text-ink-soft">
                Sube contratos, facturas, nóminas, modelos… Se trocean, se indexan y quedan
                consultables.
              </p>
            </div>

            <Uploader onAdded={refresh} />

            <div className="mt-1">
              <p className="mb-2 font-mono text-xs uppercase tracking-wide text-ink-soft">
                {loading ? "Cargando…" : `${docs.length} documento${docs.length === 1 ? "" : "s"}`}
              </p>
              <ul className="space-y-1.5">
                {docs.map((d) => (
                  <li
                    key={d.id}
                    className="group flex items-center gap-2 rounded-lg border border-line bg-surface px-3 py-2"
                  >
                    <div className="min-w-0">
                      <p className="truncate text-sm font-medium text-ink">{d.title}</p>
                      <p className="font-mono text-[10px] text-ink-soft">
                        {CATEGORY_LABEL[d.category]} · {(d.char_count / 1000).toFixed(1)}k car.
                      </p>
                    </div>
                    <button
                      onClick={() => remove(d.id)}
                      aria-label={`Eliminar ${d.title}`}
                      className="ml-auto rounded p-1 text-ink-soft opacity-0 transition-opacity hover:text-red-700 focus:opacity-100 group-hover:opacity-100"
                    >
                      ✕
                    </button>
                  </li>
                ))}
              </ul>
            </div>
          </aside>

          <section className="min-h-[70vh] lg:h-full lg:min-h-0">
            <Chat docCount={docs.length} />
          </section>
        </div>
      </main>
    </div>
  );
}
