type ClipboardEnvironment = {
  navigator?: {
    clipboard?: {
      writeText?: (text: string) => Promise<void>;
    };
  };
  document?: {
    body?: {
      appendChild: (node: HTMLTextAreaElement) => void;
    };
    createElement: (tagName: "textarea") => HTMLTextAreaElement;
    execCommand?: (command: "copy") => boolean;
  };
};

export async function copyToClipboard(text: string, environment: ClipboardEnvironment = getBrowserEnvironment()) {
  try {
    if (environment.navigator?.clipboard?.writeText) {
      await environment.navigator.clipboard.writeText(text);
      return;
    }
  } catch {
    // Fall through to the legacy path when browser permissions block Clipboard API.
  }

  const documentRef = environment.document;
  if (!documentRef?.body || !documentRef.execCommand) {
    throw new Error("Clipboard copy is not available");
  }

  const textarea = documentRef.createElement("textarea");
  textarea.value = text;
  textarea.setAttribute("readonly", "");
  textarea.style.position = "fixed";
  textarea.style.left = "-9999px";
  textarea.style.top = "0";

  documentRef.body.appendChild(textarea);
  textarea.focus();
  textarea.select();

  try {
    const copied = documentRef.execCommand("copy");
    if (!copied) {
      throw new Error("Clipboard copy failed");
    }
  } finally {
    textarea.remove();
  }
}

function getBrowserEnvironment(): ClipboardEnvironment {
  return {
    navigator: globalThis.navigator,
    document: globalThis.document
  };
}
