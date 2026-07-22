const TARGET = 1000; // chars per chunk (~250 tokens)
const OVERLAP = 150; // chars carried into the next chunk for continuity

// Split on the strongest boundary available so chunks stay semantically whole:
// paragraphs first, then sentences, then hard-wrap as a last resort.
export function chunkText(raw: string): string[] {
  const text = raw.replace(/\r\n/g, "\n").replace(/\n{3,}/g, "\n\n").trim();
  if (!text) return [];

  const paragraphs = text.split(/\n\s*\n/);
  const pieces: string[] = [];
  for (const p of paragraphs) {
    if (p.length <= TARGET) {
      pieces.push(p.trim());
    } else {
      for (const s of splitLong(p)) pieces.push(s);
    }
  }

  const chunks: string[] = [];
  let current = "";
  for (const piece of pieces) {
    if (!piece) continue;
    if (current && current.length + piece.length + 2 > TARGET) {
      chunks.push(current.trim());
      current = tail(current, OVERLAP) + "\n\n" + piece;
    } else {
      current = current ? current + "\n\n" + piece : piece;
    }
  }
  if (current.trim()) chunks.push(current.trim());
  return chunks.filter((c) => c.length > 0);
}

function splitLong(paragraph: string): string[] {
  const sentences = paragraph.match(/[^.!?\n]+[.!?]*\s*/g) ?? [paragraph];
  const out: string[] = [];
  let buf = "";
  for (const s of sentences) {
    if (buf.length + s.length > TARGET) {
      if (buf) out.push(buf.trim());
      buf = s.length > TARGET ? "" : s;
      if (s.length > TARGET) {
        for (let i = 0; i < s.length; i += TARGET) out.push(s.slice(i, i + TARGET).trim());
      }
    } else {
      buf += s;
    }
  }
  if (buf.trim()) out.push(buf.trim());
  return out;
}

function tail(s: string, n: number): string {
  return s.length <= n ? s : s.slice(s.length - n);
}
