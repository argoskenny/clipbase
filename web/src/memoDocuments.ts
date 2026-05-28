export type CopyableRange = {
  start: number;
  end: number;
};

export type MemoTextSegment = {
  text: string;
  copyable: boolean;
};

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

function splitMemoParagraphsWithOffsets(content: string): Array<{ start: number; end: number }> {
  const matches = [...content.matchAll(/\S[\s\S]*?(?=\n\s*\n|$)/g)];
  return matches.map((match) => ({
    start: match.index ?? 0,
    end: (match.index ?? 0) + match[0].trimEnd().length
  }));
}
