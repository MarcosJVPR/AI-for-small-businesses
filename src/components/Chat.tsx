import { useRef, useState, type ReactNode } from "react";
import { askQuestion, type Category, type Source } from "../lib/api";
import { CATEGORY_LABEL } from "../lib/categories";
import SourceList from "./SourceList";

type Msg = { role: "user" } | { role: "assistant"; sources: Source[] };
type Turn = Msg & { text: string; id: number };

const SAMPLES = [
  "¿Cuándo vence y cómo se renueva este contrato?",
  "¿Qué tipo de IVA aplico en esta factura?",
  "¿Qué plazo tengo para presentar este modelo?",
  "Resume mis obligaciones de este documento.",
];

function renderCitations(text: string): ReactNode[] {
  return text.split(/(\[\d+\])/g).map((part, i) => {
    const m = part.match(/^\[(\d+)\]$/);
    return m ? (
      <sup key={i} className="cite">
        {m[1]}
      </sup>
    ) : (
      <span key={i}>{part}</span>
    );
  });
}

export default function Chat({ docCount }: { docCount: number }) {
  const [turns, setTurns] = useState<Turn[]>([]);
  const [input, setInput] = useState("");
  const [filter, setFilter] = useState<Category | "all">("all");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const nextId = useRef(0);

  async function ask(question: string) {
    const q = question.trim();
    if (!q || busy) return;
    setError(null);
    setInput("");
    setTurns((t) => [...t, { role: "user", text: q, id: nextId.current++ }]);
    setBusy(true);
    try {
      const res = await askQuestion(q, filter);
      setTurns((t) => [
        ...t,
        { role: "assistant", text: res.answer, sources: res.sources, id: nextId.current++ },
      ]);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="flex h-full flex-col">
      <div className="flex items-center gap-2 border-b border-line px-5 py-3">
        <h2 className="font-display text-lg font-semibold">Consulta</h2>
        <select
          value={filter}
          onChange={(e) => setFilter(e.target.value as Category | "all")}
          className="ml-auto rounded-md border border-line bg-surface px-2 py-1 font-mono text-xs outline-none focus:border-viridian"
        >
          <option value="all">Todas las áreas</option>
          {(Object.keys(CATEGORY_LABEL) as Category[]).map((c) => (
            <option key={c} value={c}>
              {CATEGORY_LABEL[c]}
            </option>
          ))}
        </select>
      </div>

      <div className="flex-1 space-y-4 overflow-y-auto px-5 py-5">
        {turns.length === 0 && (
          <div className="mx-auto max-w-md pt-6 text-center">
            <p className="font-display text-xl text-ink">
              Pregunta como si tuvieras un equipo legal, contable y administrativo.
            </p>
            <p className="mt-2 text-sm text-ink-soft">
              {docCount === 0
                ? "Primero añade algún documento al archivo. Luego prueba una de estas:"
                : "Cada respuesta se ancla en tus documentos y cita el fragmento exacto. Prueba una:"}
            </p>
            <div className="mt-4 flex flex-wrap justify-center gap-2">
              {SAMPLES.map((s) => (
                <button
                  key={s}
                  onClick={() => ask(s)}
                  disabled={busy}
                  className="rounded-full border border-line bg-surface px-3 py-1.5 text-xs text-ink-soft transition-colors hover:border-viridian hover:text-ink disabled:opacity-40"
                >
                  {s}
                </button>
              ))}
            </div>
          </div>
        )}

        {turns.map((turn) =>
          turn.role === "user" ? (
            <div key={turn.id} className="flex justify-end">
              <div className="max-w-[85%] rounded-2xl rounded-br-sm bg-viridian px-4 py-2.5 text-sm text-surface">
                {turn.text}
              </div>
            </div>
          ) : (
            <div key={turn.id} className="max-w-[92%]">
              <div className="rounded-2xl rounded-bl-sm border border-line bg-surface px-4 py-3">
                <p className="whitespace-pre-wrap text-sm leading-relaxed text-ink">
                  {renderCitations(turn.text)}
                </p>
                <SourceList sources={turn.sources} />
              </div>
            </div>
          )
        )}

        {busy && (
          <div className="flex gap-1.5 px-2 text-ink-soft">
            <Dot /> <Dot delay="0.15s" /> <Dot delay="0.3s" />
          </div>
        )}
        {error && <p className="text-xs text-red-700">{error}</p>}
      </div>

      <div className="border-t border-line px-5 py-3">
        <div className="flex items-end gap-2">
          <textarea
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter" && !e.shiftKey) {
                e.preventDefault();
                ask(input);
              }
            }}
            rows={1}
            placeholder="Escribe tu pregunta…"
            className="max-h-32 flex-1 resize-none rounded-lg border border-line bg-surface px-3 py-2.5 text-sm outline-none placeholder:text-ink-soft/70 focus:border-viridian"
          />
          <button
            onClick={() => ask(input)}
            disabled={busy || input.trim().length < 3}
            className="rounded-lg bg-viridian px-4 py-2.5 text-sm font-semibold text-surface transition-opacity hover:bg-viridian-ink disabled:opacity-40"
          >
            Enviar
          </button>
        </div>
        <p className="mt-2 font-mono text-[10px] text-ink-soft">
          Orientativo. No sustituye a un abogado ni a un asesor fiscal colegiado.
        </p>
      </div>
    </div>
  );
}

function Dot({ delay = "0s" }: { delay?: string }) {
  return (
    <span
      className="inline-block h-2 w-2 animate-bounce rounded-full bg-ink-soft/60"
      style={{ animationDelay: delay }}
    />
  );
}
