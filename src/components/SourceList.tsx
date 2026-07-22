import { useState } from "react";
import type { Source } from "../lib/api";
import { CATEGORY_LABEL } from "../lib/categories";

export default function SourceList({ sources }: { sources: Source[] }) {
  const [open, setOpen] = useState(false);
  if (sources.length === 0) return null;

  return (
    <div className="mt-3 border-t border-line pt-3">
      <button
        onClick={() => setOpen((o) => !o)}
        className="flex items-center gap-2 font-mono text-xs font-medium text-viridian"
      >
        <span>{open ? "▾" : "▸"}</span>
        {sources.length} {sources.length === 1 ? "fragmento citado" : "fragmentos citados"}
      </button>

      {open && (
        <ul className="mt-2 space-y-2">
          {sources.map((s) => (
            <li key={s.n} className="rounded-lg border border-line bg-paper/60 p-3">
              <div className="mb-1 flex items-center gap-2 text-xs">
                <span className="cite">{s.n}</span>
                <span className="font-medium text-ink">{s.documentTitle}</span>
                <span className="rounded bg-line/60 px-1.5 py-0.5 font-mono text-[10px] text-ink-soft">
                  {CATEGORY_LABEL[s.category]}
                </span>
                <span className="ml-auto font-mono text-[10px] text-ink-soft">
                  {Math.round(s.similarity * 100)}% afín
                </span>
              </div>
              <p className="text-xs leading-relaxed text-ink-soft">
                <span className="marked">{s.excerpt}</span>
              </p>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
