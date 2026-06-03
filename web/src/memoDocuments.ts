export type CopyableRange = {
  start: number;
  end: number;
};

export type MemoTextSegment = {
  text: string;
  copyable: boolean;
};

export type MemoReaderInline =
  | { type: "text"; text: string }
  | { type: "copyable"; text: string }
  | { type: "strong"; children: MemoReaderInline[] }
  | { type: "emphasis"; children: MemoReaderInline[] }
  | { type: "code"; text: string }
  | { type: "link"; href: string; children: MemoReaderInline[] };

export type MemoReaderBlock =
  | { type: "paragraph"; children: MemoReaderInline[] }
  | { type: "heading"; level: 1 | 2 | 3 | 4 | 5 | 6; children: MemoReaderInline[] }
  | { type: "unordered-list"; items: MemoReaderInline[][] }
  | { type: "ordered-list"; items: MemoReaderInline[][] }
  | { type: "blockquote"; children: MemoReaderInline[] }
  | { type: "code-block"; text: string };

export function splitMemoParagraphs(content: string): string[] {
  const normalized = content.replace(/\r\n/g, "\n").trim();
  if (!normalized) {
    return [];
  }

  return normalized.split(/\n\s*\n/g).map((paragraph) => paragraph.trim()).filter(Boolean);
}

export function getCopyableRangeForSelection(content: string, selectionStart: number, selectionEnd: number): CopyableRange | null {
  const normalized = content.replace(/\r\n/g, "\n");
  const start = Math.max(0, Math.min(selectionStart, selectionEnd, normalized.length));
  const end = Math.max(0, Math.min(Math.max(selectionStart, selectionEnd), normalized.length));
  const selectedText = normalized.slice(start, end);
  const leadingWhitespace = selectedText.match(/^\s*/)?.[0].length ?? 0;
  const trailingWhitespace = selectedText.match(/\s*$/)?.[0].length ?? 0;
  const trimmedStart = start + leadingWhitespace;
  const trimmedEnd = end - trailingWhitespace;

  return trimmedStart < trimmedEnd ? { start: trimmedStart, end: trimmedEnd } : null;
}

export function normalizeCopyableRanges(ranges: CopyableRange[], content: string): CopyableRange[] {
  const contentLength = content.replace(/\r\n/g, "\n").length;
  const normalized = ranges
    .map((range) => ({
      start: Number(range.start),
      end: Number(range.end)
    }))
    .filter((range) => (
      Number.isInteger(range.start) &&
      Number.isInteger(range.end) &&
      range.start >= 0 &&
      range.end <= contentLength &&
      range.start < range.end
    ))
    .sort((left, right) => left.start - right.start || left.end - right.end);

  const merged: CopyableRange[] = [];
  for (const range of normalized) {
    const previous = merged.at(-1);
    if (previous && range.start <= previous.end) {
      previous.end = Math.max(previous.end, range.end);
      continue;
    }
    merged.push({ ...range });
  }

  return merged;
}

export function splitMemoParagraphsIntoSegments(content: string, ranges: CopyableRange[]): MemoTextSegment[][] {
  const normalized = content.replace(/\r\n/g, "\n");
  const copyableRanges = normalizeCopyableRanges(ranges, normalized);
  const paragraphs = splitMemoParagraphsWithOffsets(normalized);

  return paragraphs.map((paragraph) => {
    const paragraphRanges = copyableRanges
      .map((range) => ({
        start: Math.max(range.start, paragraph.start),
        end: Math.min(range.end, paragraph.end)
      }))
      .filter((range) => range.start < range.end);
    const segments: MemoTextSegment[] = [];
    let cursor = paragraph.start;

    for (const range of paragraphRanges) {
      if (cursor < range.start) {
        segments.push({ text: normalized.slice(cursor, range.start), copyable: false });
      }
      segments.push({ text: normalized.slice(range.start, range.end), copyable: true });
      cursor = range.end;
    }

    if (cursor < paragraph.end) {
      segments.push({ text: normalized.slice(cursor, paragraph.end), copyable: false });
    }

    return segments.filter((segment) => segment.text.length > 0);
  });
}

export function getMemoReaderBlocks(paragraphs: MemoTextSegment[][]): MemoReaderBlock[] {
  return paragraphs.map((segments) => {
    const plainText = segments.map((segment) => segment.text).join("");
    if (!segments.some((segment) => segment.copyable)) {
      const codeBlockMatch = plainText.match(/^```[^\n]*\n([\s\S]*?)\n?```$/);
      if (codeBlockMatch) {
        return { type: "code-block", text: codeBlockMatch[1] };
      }

      const headingMatch = plainText.match(/^(#{1,6})\s+(.+)$/s);
      if (headingMatch && !headingMatch[2].includes("\n")) {
        return {
          type: "heading",
          level: headingMatch[1].length as 1 | 2 | 3 | 4 | 5 | 6,
          children: parseMemoMarkdownInline(headingMatch[2])
        };
      }

      const lines = plainText.split("\n");
      if (lines.every((line) => /^\s*[-*+]\s+/.test(line))) {
        return {
          type: "unordered-list",
          items: lines.map((line) => parseMemoMarkdownInline(line.replace(/^\s*[-*+]\s+/, "")))
        };
      }

      if (lines.every((line) => /^\s*\d+[.)]\s+/.test(line))) {
        return {
          type: "ordered-list",
          items: lines.map((line) => parseMemoMarkdownInline(line.replace(/^\s*\d+[.)]\s+/, "")))
        };
      }

      if (lines.every((line) => /^\s*>\s?/.test(line))) {
        return {
          type: "blockquote",
          children: parseMemoMarkdownInline(lines.map((line) => line.replace(/^\s*>\s?/, "")).join("\n"))
        };
      }
    }

    return {
      type: "paragraph",
      children: segments.flatMap((segment) => (
        segment.copyable ? [{ type: "copyable" as const, text: segment.text }] : parseMemoMarkdownInline(segment.text)
      ))
    };
  });
}

export function parseMemoMarkdownInline(text: string): MemoReaderInline[] {
  const tokens: MemoReaderInline[] = [];
  let cursor = 0;

  while (cursor < text.length) {
    const next = findNextMarkdownToken(text, cursor);
    if (!next) {
      tokens.push({ type: "text", text: text.slice(cursor) });
      break;
    }

    if (next.start > cursor) {
      tokens.push({ type: "text", text: text.slice(cursor, next.start) });
    }
    tokens.push(next.token);
    cursor = next.end;
  }

  return tokens.filter((token) => token.type !== "text" || token.text.length > 0);
}

function splitMemoParagraphsWithOffsets(content: string): Array<{ start: number; end: number }> {
  const matches = [...content.matchAll(/\S[\s\S]*?(?=\n\s*\n|$)/g)];
  return matches.map((match) => ({
    start: match.index ?? 0,
    end: (match.index ?? 0) + match[0].trimEnd().length
  }));
}

function findNextMarkdownToken(text: string, from: number): { start: number; end: number; token: MemoReaderInline } | null {
  const candidates = [
    findInlineCode(text, from),
    findDelimitedInline(text, from, "**", "strong"),
    findDelimitedInline(text, from, "*", "emphasis"),
    findMarkdownLink(text, from)
  ].filter((candidate): candidate is { start: number; end: number; token: MemoReaderInline } => candidate !== null);

  return candidates.sort((left, right) => left.start - right.start || left.end - right.end)[0] ?? null;
}

function findInlineCode(text: string, from: number): { start: number; end: number; token: MemoReaderInline } | null {
  const start = text.indexOf("`", from);
  if (start < 0) {
    return null;
  }
  const end = text.indexOf("`", start + 1);
  if (end < 0) {
    return null;
  }
  return { start, end: end + 1, token: { type: "code", text: text.slice(start + 1, end) } };
}

function findDelimitedInline(
  text: string,
  from: number,
  delimiter: "*" | "**",
  type: "strong" | "emphasis"
): { start: number; end: number; token: MemoReaderInline } | null {
  const start = text.indexOf(delimiter, from);
  if (start < 0 || (delimiter === "*" && text[start + 1] === "*")) {
    return null;
  }
  const contentStart = start + delimiter.length;
  const end = text.indexOf(delimiter, contentStart);
  if (end <= contentStart || (delimiter === "*" && text[end + 1] === "*")) {
    return null;
  }

  return {
    start,
    end: end + delimiter.length,
    token: { type, children: parseMemoMarkdownInline(text.slice(contentStart, end)) }
  };
}

function findMarkdownLink(text: string, from: number): { start: number; end: number; token: MemoReaderInline } | null {
  const match = /\[([^\]]+)\]\(([^)\s]+)\)/g;
  match.lastIndex = from;
  const result = match.exec(text);
  if (!result) {
    return null;
  }
  const href = sanitizeMarkdownHref(result[2]);
  if (!href) {
    return null;
  }

  return {
    start: result.index,
    end: result.index + result[0].length,
    token: { type: "link", href, children: parseMemoMarkdownInline(result[1]) }
  };
}

function sanitizeMarkdownHref(href: string): string | null {
  if (/^(https?:|mailto:)/i.test(href)) {
    return href;
  }
  return null;
}
