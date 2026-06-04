import {
  Clipboard,
  Database,
  Download,
  Edit3,
  Eye,
  FileText,
  FileUp,
  ListPlus,
  LogOut,
  Moon,
  Plus,
  Save,
  Search,
  Sparkles,
  Sun,
  Trash2,
  X
} from "lucide-react";
import { FormEvent, ReactNode, useEffect, useMemo, useRef, useState } from "react";
import { copyToClipboard } from "./clipboard";
import {
  getMemoReaderBlocks,
  getCopyableRangeForSelection,
  normalizeCopyableRanges,
  splitMemoParagraphs,
  splitMemoParagraphsIntoSegments,
  type CopyableRange,
  type MemoReaderBlock,
  type MemoReaderInline
} from "./memoDocuments";
import { applyTheme, getInitialTheme, type ThemeMode } from "./theme";

type ClipItem = {
  id: string;
  name: string;
  content: string;
  metadata: string | null;
};

type ClipSection = {
  id: string;
  title: string;
  items: ClipItem[];
};

type PromptOptimizer = {
  id: string;
  title: string;
  placement: "prefix" | "suffix";
  affixText: string;
};

type MemoDocument = {
  id: string;
  title: string;
  content: string;
  copyableRanges: CopyableRange[];
};

type AppState = {
  sections: ClipSection[];
  optimizers: PromptOptimizer[];
  memoDocuments: MemoDocument[];
};

type ActiveTab = "clips" | "optimizers" | "memos";

const emptyState: AppState = {
  sections: [],
  optimizers: [],
  memoDocuments: []
};

export function App() {
  const [theme, setTheme] = useState<ThemeMode>(() => getInitialTheme(
    typeof window === "undefined" ? null : window.localStorage,
    () => typeof window !== "undefined" && window.matchMedia("(prefers-color-scheme: dark)").matches
  ));
  const [session, setSession] = useState<{ authenticated: boolean; username: string | null } | null>(null);
  const [state, setState] = useState<AppState>(emptyState);
  const [activeTab, setActiveTab] = useState<ActiveTab>("clips");
  const [selectedSectionId, setSelectedSectionId] = useState<string | null>(null);
  const [selectedOptimizerId, setSelectedOptimizerId] = useState<string | null>(null);
  const [selectedMemoDocumentId, setSelectedMemoDocumentId] = useState<string | null>(null);
  const [notice, setNotice] = useState("");

  useEffect(() => {
    applyTheme(theme, document.documentElement, window.localStorage);
  }, [theme]);

  useEffect(() => {
    void api<{ authenticated: boolean; username: string | null }>("/api/session", { skipAuthRedirect: true })
      .then((result) => {
        setSession(result);
        if (result.authenticated) {
          void refreshState();
        }
      });
  }, []);

  useEffect(() => {
    if (!selectedSectionId && state.sections[0]) {
      setSelectedSectionId(state.sections[0].id);
    }
    if (selectedSectionId && !state.sections.some((section) => section.id === selectedSectionId)) {
      setSelectedSectionId(state.sections[0]?.id ?? null);
    }
  }, [selectedSectionId, state.sections]);

  useEffect(() => {
    if (!selectedOptimizerId && state.optimizers[0]) {
      setSelectedOptimizerId(state.optimizers[0].id);
    }
    if (selectedOptimizerId && !state.optimizers.some((optimizer) => optimizer.id === selectedOptimizerId)) {
      setSelectedOptimizerId(state.optimizers[0]?.id ?? null);
    }
  }, [selectedOptimizerId, state.optimizers]);

  useEffect(() => {
    if (!selectedMemoDocumentId && state.memoDocuments[0]) {
      setSelectedMemoDocumentId(state.memoDocuments[0].id);
    }
    if (selectedMemoDocumentId && !state.memoDocuments.some((document) => document.id === selectedMemoDocumentId)) {
      setSelectedMemoDocumentId(state.memoDocuments[0]?.id ?? null);
    }
  }, [selectedMemoDocumentId, state.memoDocuments]);

  async function refreshState() {
    const nextState = await api<AppState>("/api/state");
    setState(nextState);
  }

  async function handleLogin(username: string, password: string) {
    const result = await api<{ username: string }>("/api/login", {
      method: "POST",
      body: JSON.stringify({ username, password }),
      skipAuthRedirect: true
    });
    setSession({ authenticated: true, username: result.username });
    await refreshState();
  }

  async function handleLogout() {
    await api("/api/logout", { method: "POST", skipAuthRedirect: true });
    setSession({ authenticated: false, username: null });
    setState(emptyState);
  }

  function flash(message: string) {
    setNotice(message);
    window.setTimeout(() => setNotice(""), 1600);
  }

  function toggleTheme() {
    setTheme((currentTheme) => currentTheme === "dark" ? "light" : "dark");
  }

  if (session === null) {
    return <div className="loading">載入中...</div>;
  }

  if (!session.authenticated) {
    return <LoginPage onLogin={handleLogin} />;
  }

  const itemCount = state.sections.reduce((total, section) => total + section.items.length, 0);

  return (
    <div className="app-shell">
      <header className="topbar">
        <div className="brand-lockup">
          <div className="app-mark" aria-hidden="true">
            <img src="/appicon.png" alt="" />
          </div>
          <div>
            <h1>ClipBase</h1>
            <p>剪貼資料庫與提示詞優化器</p>
          </div>
        </div>

        <div className="topbar-actions">
          {notice && <span className="notice">{notice}</span>}
          <span className="user-chip">{session.username}</span>
          <button
            className="icon-button theme-toggle"
            onClick={toggleTheme}
            title={theme === "dark" ? "切換為淺色模式" : "切換為深色模式"}
            aria-label={theme === "dark" ? "切換為淺色模式" : "切換為深色模式"}
            aria-pressed={theme === "dark"}
          >
            {theme === "dark" ? <Sun size={18} /> : <Moon size={18} />}
            <span>{theme === "dark" ? "淺色" : "深色"}</span>
          </button>
          <button className="icon-button" onClick={handleLogout} title="登出">
            <LogOut size={18} />
            <span>登出</span>
          </button>
        </div>
      </header>

      <main className="workspace">
        <nav className="rail" aria-label="主要功能">
          <button className={activeTab === "clips" ? "active" : ""} onClick={() => setActiveTab("clips")}>
            <Database size={18} />
            <span className="tab-label">
              <strong>剪貼內容</strong>
              <small>{state.sections.length} 分類 / {itemCount} 項</small>
            </span>
          </button>
          <button className={activeTab === "optimizers" ? "active" : ""} onClick={() => setActiveTab("optimizers")}>
            <Sparkles size={18} />
            <span className="tab-label">
              <strong>提示詞優化器</strong>
              <small>{state.optimizers.length} 個模板</small>
            </span>
          </button>
          <button className={activeTab === "memos" ? "active" : ""} onClick={() => setActiveTab("memos")}>
            <FileText size={18} />
            <span className="tab-label">
              <strong>備忘文件</strong>
              <small>{state.memoDocuments.length} 份文件</small>
            </span>
          </button>
        </nav>

        {activeTab === "clips" ? (
          <ClipLibrary
            sections={state.sections}
            selectedSectionId={selectedSectionId}
            onSelectSection={setSelectedSectionId}
            onRefresh={refreshState}
            onNotice={flash}
          />
        ) : activeTab === "optimizers" ? (
          <PromptOptimizers
            optimizers={state.optimizers}
            selectedOptimizerId={selectedOptimizerId}
            onSelectOptimizer={setSelectedOptimizerId}
            onRefresh={refreshState}
            onNotice={flash}
          />
        ) : (
          <MemoDocuments
            documents={state.memoDocuments}
            selectedDocumentId={selectedMemoDocumentId}
            onSelectDocument={setSelectedMemoDocumentId}
            onRefresh={refreshState}
            onNotice={flash}
          />
        )}
      </main>
    </div>
  );
}

function LoginPage({ onLogin }: { onLogin: (username: string, password: string) => Promise<void> }) {
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);

  async function submit(event: FormEvent) {
    event.preventDefault();
    setError("");
    setIsSubmitting(true);
    try {
      await onLogin(username, password);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "登入失敗");
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <main className="login-page">
      <form className="login-panel" onSubmit={submit}>
        <div className="login-heading">
          <div className="login-mark">
            <img src="/appicon.png" alt="" />
          </div>
          <div>
            <h1>ClipBase</h1>
            <p>登入後管理剪貼內容與提示詞模板</p>
          </div>
        </div>
        <label>
          帳號
          <input autoFocus value={username} onChange={(event) => setUsername(event.target.value)} />
        </label>
        <label>
          密碼
          <input type="password" value={password} onChange={(event) => setPassword(event.target.value)} />
        </label>
        {error && <p className="form-error">{error}</p>}
        <button className="primary-button" disabled={isSubmitting}>
          {isSubmitting ? "登入中..." : "登入"}
        </button>
      </form>
    </main>
  );
}

function ImportExportActions({ onImported, onNotice }: { onImported: () => Promise<void>; onNotice: (message: string) => void }) {
  const fileInputRef = useRef<HTMLInputElement | null>(null);
  const backupInputRef = useRef<HTMLInputElement | null>(null);

  async function importCsvFile(file: File | undefined) {
    if (!file) {
      return;
    }

    const csv = await file.text();
    await api("/api/import", {
      method: "POST",
      body: JSON.stringify({ csv })
    });
    await onImported();
    onNotice("CSV 已匯入");
    if (fileInputRef.current) {
      fileInputRef.current.value = "";
    }
  }

  async function exportCsvFile() {
    const response = await fetch("/api/export", { credentials: "include" });
    if (!response.ok) {
      throw new Error("匯出失敗");
    }
    const blob = await response.blob();
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = "clipbase-export.csv";
    link.click();
    URL.revokeObjectURL(url);
    onNotice("CSV 已匯出");
  }

  async function exportBackupFile() {
    const response = await fetch("/api/backup", { credentials: "include" });
    if (!response.ok) {
      throw new Error("備份失敗");
    }
    const blob = await response.blob();
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = "clipbase-backup.json";
    link.click();
    URL.revokeObjectURL(url);
    onNotice("完整備份已匯出");
  }

  async function restoreBackupFile(file: File | undefined) {
    if (!file) {
      return;
    }
    if (!window.confirm("還原完整備份會覆蓋目前所有資料，確定要繼續？")) {
      if (backupInputRef.current) {
        backupInputRef.current.value = "";
      }
      return;
    }

    const backup = JSON.parse(await file.text());
    await api("/api/backup/restore", {
      method: "POST",
      body: JSON.stringify(backup)
    });
    await onImported();
    onNotice("完整備份已還原");
    if (backupInputRef.current) {
      backupInputRef.current.value = "";
    }
  }

  return (
    <>
      <input
        ref={fileInputRef}
        className="hidden-input"
        type="file"
        accept=".csv,text/csv"
        onChange={(event) => void importCsvFile(event.target.files?.[0])}
      />
      <input
        ref={backupInputRef}
        className="hidden-input"
        type="file"
        accept=".json,application/json"
        onChange={(event) => void restoreBackupFile(event.target.files?.[0])}
      />
      <button className="icon-button" onClick={() => fileInputRef.current?.click()} title="匯入 CSV">
        <FileUp size={18} />
        <span>匯入</span>
      </button>
      <button className="icon-button" onClick={() => void exportCsvFile()} title="匯出 CSV">
        <Download size={18} />
        <span>匯出</span>
      </button>
      <button className="icon-button" onClick={() => void exportBackupFile()} title="下載完整備份 JSON">
        <Download size={18} />
        <span>備份</span>
      </button>
      <button className="icon-button" onClick={() => backupInputRef.current?.click()} title="還原完整備份 JSON">
        <FileUp size={18} />
        <span>還原</span>
      </button>
    </>
  );
}

function ClipLibrary({
  sections,
  selectedSectionId,
  onSelectSection,
  onRefresh,
  onNotice
}: {
  sections: ClipSection[];
  selectedSectionId: string | null;
  onSelectSection: (id: string) => void;
  onRefresh: () => Promise<void>;
  onNotice: (message: string) => void;
}) {
  const selectedSection = sections.find((section) => section.id === selectedSectionId) ?? sections[0] ?? null;
  const [isCategoryEditMode, setIsCategoryEditMode] = useState(false);
  const [searchTerm, setSearchTerm] = useState("");
  const [sectionModal, setSectionModal] = useState<{ mode: "create" } | { mode: "edit"; section: ClipSection } | null>(null);
  const [itemModal, setItemModal] = useState<{ mode: "create"; sectionId: string } | { mode: "edit"; item: ClipItem; sectionId: string } | null>(null);

  const filteredItems = useMemo(() => {
    if (!selectedSection) {
      return [];
    }
    const query = searchTerm.trim().toLowerCase();
    if (!query) {
      return selectedSection.items;
    }
    return selectedSection.items.filter((item) => {
      return [item.name, item.content, item.metadata ?? ""].some((value) => value.toLowerCase().includes(query));
    });
  }, [searchTerm, selectedSection]);

  async function addSection(title: string) {
    const section = await api<ClipSection>("/api/sections", {
      method: "POST",
      body: JSON.stringify({ title })
    });
    await onRefresh();
    onSelectSection(section.id);
  }

  async function addItem(name: string, content: string, sectionId: string) {
    await api("/api/items", {
      method: "POST",
      body: JSON.stringify({ name, content, sectionId })
    });
    onSelectSection(sectionId);
    await onRefresh();
  }

  async function updateSection(sectionId: string, title: string) {
    await api(`/api/sections/${sectionId}`, {
      method: "PATCH",
      body: JSON.stringify({ title })
    });
    await onRefresh();
  }

  async function deleteSection(section: ClipSection) {
    if (!window.confirm(`刪除「${section.title}」？分類內項目會移到「其它」。`)) {
      return;
    }

    const fallback = await api<{ id: string; title: string }>(`/api/sections/${section.id}`, { method: "DELETE" });
    await onRefresh();
    onSelectSection(fallback.id);
  }

  async function updateItem(itemId: string, name: string, content: string, sectionId: string) {
    await api(`/api/items/${itemId}`, {
      method: "PATCH",
      body: JSON.stringify({ name, content, sectionId })
    });
    onSelectSection(sectionId);
    await onRefresh();
  }

  async function moveItem(itemId: string, sectionId: string) {
    await api(`/api/items/${itemId}/move`, {
      method: "PATCH",
      body: JSON.stringify({ sectionId })
    });
    onSelectSection(sectionId);
    await onRefresh();
  }

  async function deleteItem(itemId: string) {
    await api(`/api/items/${itemId}`, { method: "DELETE" });
    await onRefresh();
  }

  async function copyText(text: string) {
    await copyToClipboard(text);
    onNotice("已複製");
  }

  return (
    <section className="content-grid">
      <aside className="side-panel">
        <div className="panel-header stacked">
          <div>
            <h2>分類</h2>
            <span>{sections.length}</span>
          </div>
          <div className="panel-actions">
            <button className="icon-button compact" onClick={() => setIsCategoryEditMode((value) => !value)}>
              <Edit3 size={16} />
              <span>{isCategoryEditMode ? "完成" : "編輯"}</span>
            </button>
            <button className="primary-button compact" onClick={() => setSectionModal({ mode: "create" })}>
              <Plus size={16} />
              <span>新增</span>
            </button>
          </div>
        </div>
        <div className="section-list">
          {sections.map((section) => (
            <div
              key={section.id}
              className={`section-row ${section.id === selectedSection?.id ? "selected" : ""}`}
            >
              <button onClick={() => onSelectSection(section.id)}>
                <span>{section.title}</span>
                <small>{section.items.length}</small>
              </button>
              {isCategoryEditMode && (
                <div className="row-actions">
                  <button className="icon-only" onClick={() => setSectionModal({ mode: "edit", section })} title="編輯分類">
                    <Edit3 size={16} />
                  </button>
                  <button
                    className="icon-only danger"
                    disabled={section.title === "其它"}
                    onClick={() => void deleteSection(section)}
                    title={section.title === "其它" ? "其它分類不可刪除" : "刪除分類"}
                  >
                    <Trash2 size={16} />
                  </button>
                </div>
              )}
            </div>
          ))}
        </div>
      </aside>

      <section className="detail-panel">
        {selectedSection ? (
          <>
            <div className="detail-header">
              <div>
                <h2>{selectedSection.title}</h2>
                <p>
                  {searchTerm.trim()
                    ? `找到 ${filteredItems.length} / ${selectedSection.items.length} 個項目`
                    : `目前分類共有 ${selectedSection.items.length} 個可複製項目`}
                </p>
              </div>
              <div className="header-command-group">
                <ImportExportActions onImported={onRefresh} onNotice={onNotice} />
                <button className="primary-button" onClick={() => setItemModal({ mode: "create", sectionId: selectedSection.id })}>
                  <ListPlus size={17} />
                  <span>新增項目</span>
                </button>
              </div>
            </div>
            <label className="search-field">
              <Search size={17} />
              <span>搜尋項目</span>
              <input
                value={searchTerm}
                onChange={(event) => setSearchTerm(event.target.value)}
                placeholder="輸入名稱、內容或備註"
              />
            </label>
            <div className="table-wrap">
              <table>
                <thead>
                  <tr>
                    <th>項目名稱</th>
                    <th>項目內容</th>
                    <th>操作</th>
                  </tr>
                </thead>
                <tbody>
                  {filteredItems.map((item) => (
                    <tr key={item.id}>
                      <td>
                        <strong>{item.name}</strong>
                        {item.metadata && <small>{item.metadata}</small>}
                      </td>
                      <td className="clip-content">{item.content}</td>
                      <td>
                        <div className="row-actions item-actions">
                          <button className="primary-button compact copy-button" onClick={() => void copyText(item.content)}>
                            <Clipboard size={16} />
                            <span>複製</span>
                          </button>
                          <select
                            className="move-select"
                            aria-label={`移動 ${item.name} 到其它分類`}
                            value={selectedSection.id}
                            onChange={(event) => void moveItem(item.id, event.target.value)}
                          >
                            {sections.map((section) => (
                              <option key={section.id} value={section.id}>
                                {section.title}
                              </option>
                            ))}
                          </select>
                          <button
                            className="icon-only"
                            onClick={() => setItemModal({ mode: "edit", item, sectionId: selectedSection.id })}
                            title="編輯"
                          >
                            <Edit3 size={17} />
                          </button>
                          <button className="icon-only danger" onClick={() => void deleteItem(item.id)} title="刪除">
                            <Trash2 size={17} />
                          </button>
                        </div>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
              {selectedSection.items.length === 0 && <div className="empty">這個分類目前沒有項目。</div>}
              {selectedSection.items.length > 0 && filteredItems.length === 0 && <div className="empty">沒有符合搜尋的項目。</div>}
            </div>
          </>
        ) : (
          <div className="empty fill">請先新增分類，或從 CSV 匯入資料。</div>
        )}
      </section>

      {sectionModal && (
        <SectionModal
          mode={sectionModal.mode}
          section={sectionModal.mode === "edit" ? sectionModal.section : undefined}
          onClose={() => setSectionModal(null)}
          onSave={async (title) => {
            if (sectionModal.mode === "create") {
              await addSection(title);
            } else {
              await updateSection(sectionModal.section.id, title);
            }
            setSectionModal(null);
          }}
        />
      )}

      {itemModal && (
        <ItemModal
          mode={itemModal.mode}
          sections={sections}
          item={itemModal.mode === "edit" ? itemModal.item : undefined}
          initialSectionId={itemModal.sectionId}
          onClose={() => setItemModal(null)}
          onSave={async (name, content, sectionId) => {
            if (itemModal.mode === "create") {
              await addItem(name, content, sectionId);
            } else {
              await updateItem(itemModal.item.id, name, content, sectionId);
            }
            setItemModal(null);
          }}
        />
      )}
    </section>
  );
}

function SectionModal({
  mode,
  section,
  onClose,
  onSave
}: {
  mode: "create" | "edit";
  section?: ClipSection;
  onClose: () => void;
  onSave: (title: string) => Promise<void>;
}) {
  const [title, setTitle] = useState(section?.title ?? "");
  const [error, setError] = useState("");

  async function submit(event: FormEvent) {
    event.preventDefault();
    setError("");
    if (!title.trim()) {
      setError("分類名稱不可空白");
      return;
    }
    try {
      await onSave(title);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "儲存失敗");
    }
  }

  return (
    <Modal title={mode === "create" ? "新增分類" : "編輯分類"} onClose={onClose}>
      <form className="modal-form" onSubmit={submit}>
        <label>
          分類名稱
          <input autoFocus value={title} onChange={(event) => setTitle(event.target.value)} />
        </label>
        {error && <p className="form-error">{error}</p>}
        <ModalActions onClose={onClose} submitLabel={mode === "create" ? "新增" : "儲存"} />
      </form>
    </Modal>
  );
}

function ItemModal({
  mode,
  sections,
  item,
  initialSectionId,
  onClose,
  onSave
}: {
  mode: "create" | "edit";
  sections: ClipSection[];
  item?: ClipItem;
  initialSectionId: string;
  onClose: () => void;
  onSave: (name: string, content: string, sectionId: string) => Promise<void>;
}) {
  const [name, setName] = useState("");
  const [content, setContent] = useState("");
  const [sectionId, setSectionId] = useState(initialSectionId);
  const [error, setError] = useState("");

  useEffect(() => {
    setName(item?.name ?? "");
    setContent(item?.content ?? "");
    setSectionId(initialSectionId);
  }, [initialSectionId, item]);

  async function submit(event: FormEvent) {
    event.preventDefault();
    setError("");
    if (!name.trim() || !content.trim()) {
      setError("項目名稱與內容不可空白");
      return;
    }
    try {
      await onSave(name, content, sectionId);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "儲存失敗");
    }
  }

  return (
    <Modal title={mode === "create" ? "新增項目" : "編輯項目"} onClose={onClose}>
      <form className="modal-form" onSubmit={submit}>
        <label>
          分類
          <select value={sectionId} onChange={(event) => setSectionId(event.target.value)}>
            {sections.map((section) => (
              <option key={section.id} value={section.id}>
                {section.title}
              </option>
            ))}
          </select>
        </label>
        <label>
          項目名稱
          <input autoFocus value={name} onChange={(event) => setName(event.target.value)} />
        </label>
        <label>
          項目內容
          <textarea value={content} onChange={(event) => setContent(event.target.value)} />
        </label>
        {error && <p className="form-error">{error}</p>}
        <ModalActions onClose={onClose} submitLabel={mode === "create" ? "新增" : "儲存"} />
      </form>
    </Modal>
  );
}

function PromptOptimizers({
  optimizers,
  selectedOptimizerId,
  onSelectOptimizer,
  onRefresh,
  onNotice
}: {
  optimizers: PromptOptimizer[];
  selectedOptimizerId: string | null;
  onSelectOptimizer: (id: string) => void;
  onRefresh: () => Promise<void>;
  onNotice: (message: string) => void;
}) {
  const selectedOptimizer = optimizers.find((optimizer) => optimizer.id === selectedOptimizerId) ?? optimizers[0] ?? null;
  const [input, setInput] = useState("");
  const [optimizerSearchTerm, setOptimizerSearchTerm] = useState("");
  const [optimizerModal, setOptimizerModal] = useState<{ mode: "create" } | { mode: "edit"; optimizer: PromptOptimizer } | null>(null);

  const filteredOptimizers = useMemo(() => {
    const query = optimizerSearchTerm.trim().toLowerCase();
    if (!query) {
      return optimizers;
    }
    return optimizers.filter((optimizer) => {
      return [optimizer.title, optimizer.affixText, optimizer.placement].some((value) => value.toLowerCase().includes(query));
    });
  }, [optimizerSearchTerm, optimizers]);

  const combinedPrompt = useMemo(() => {
    if (!selectedOptimizer) {
      return "";
    }
    const affixText = selectedOptimizer.affixText.trim();
    const trimmedInput = input.trim();
    if (!trimmedInput) {
      return affixText;
    }
    return selectedOptimizer.placement === "prefix"
      ? [affixText, trimmedInput].filter(Boolean).join("\n\n")
      : [trimmedInput, affixText].filter(Boolean).join("\n\n");
  }, [input, selectedOptimizer]);

  async function addOptimizer(title: string, placement: "prefix" | "suffix", affixText: string) {
    const optimizer = await api<PromptOptimizer>("/api/optimizers", {
      method: "POST",
      body: JSON.stringify({ title, placement, affixText })
    });
    await onRefresh();
    onSelectOptimizer(optimizer.id);
  }

  async function updateOptimizer(id: string, title: string, placement: "prefix" | "suffix", affixText: string) {
    await api(`/api/optimizers/${id}`, {
      method: "PATCH",
      body: JSON.stringify({ title, placement, affixText })
    });
    await onRefresh();
  }

  async function deleteOptimizer(id: string) {
    await api(`/api/optimizers/${id}`, { method: "DELETE" });
    await onRefresh();
  }

  async function copyPrompt() {
    await copyToClipboard(combinedPrompt);
    onNotice("已複製");
  }

  return (
    <section className="content-grid">
      <aside className="side-panel">
        <div className="panel-header">
          <h2>優化器</h2>
          <div className="panel-actions">
            <span>{optimizers.length}</span>
            <button className="primary-button compact" onClick={() => setOptimizerModal({ mode: "create" })}>
              <Plus size={16} />
              <span>新增</span>
            </button>
          </div>
        </div>
        <label className="search-field compact-search">
          <Search size={16} />
          <span>搜尋優化器</span>
          <input
            value={optimizerSearchTerm}
            onChange={(event) => setOptimizerSearchTerm(event.target.value)}
            placeholder="搜尋名稱或內容"
          />
        </label>
        <div className="section-list">
          {filteredOptimizers.map((optimizer) => (
            <button
              key={optimizer.id}
              className={optimizer.id === selectedOptimizer?.id ? "selected" : ""}
              onClick={() => onSelectOptimizer(optimizer.id)}
            >
              <span>{optimizer.title}</span>
              <small>{optimizer.placement === "prefix" ? "前綴" : "後綴"}</small>
            </button>
          ))}
          {optimizers.length > 0 && filteredOptimizers.length === 0 && <div className="empty small-empty">沒有符合搜尋的優化器。</div>}
        </div>
      </aside>

      <section className="detail-panel">
        {selectedOptimizer ? (
          <>
            <div className="detail-header">
              <div>
                <h2>{selectedOptimizer.title}</h2>
                <p>{selectedOptimizer.placement === "prefix" ? "前綴會放在輸入內容之前" : "後綴會放在輸入內容之後"}</p>
              </div>
              <div className="row-actions">
                <button className="icon-button" onClick={() => setOptimizerModal({ mode: "edit", optimizer: selectedOptimizer })}>
                  <Edit3 size={17} />
                  <span>編輯</span>
                </button>
                <button className="primary-button" onClick={() => void copyPrompt()}>
                  <Clipboard size={17} />
                  <span>複製</span>
                </button>
                <button className="icon-only danger" onClick={() => void deleteOptimizer(selectedOptimizer.id)} title="刪除優化器">
                  <Trash2 size={17} />
                </button>
              </div>
            </div>

            <div className="optimizer-layout">
              <section>
                <h3>輸入內容</h3>
                <textarea
                  value={input}
                  onChange={(event) => setInput(event.target.value)}
                  placeholder="貼上要優化的提示詞；留空時會只輸出固定段落"
                />
              </section>
              <section>
                <div className="panel-title-row">
                  <h3>合併結果</h3>
                  <button className="primary-button compact" onClick={() => void copyPrompt()}>
                    <Clipboard size={16} />
                    <span>複製</span>
                  </button>
                </div>
                <pre>{combinedPrompt}</pre>
              </section>
              <section>
                <h3>{selectedOptimizer.placement === "prefix" ? "固定前綴" : "固定後綴"}</h3>
                <pre>{selectedOptimizer.affixText}</pre>
              </section>
            </div>
          </>
        ) : (
          <div className="empty fill">請先新增一個優化器。</div>
        )}
      </section>

      {optimizerModal && (
        <OptimizerModal
          mode={optimizerModal.mode}
          optimizer={optimizerModal.mode === "edit" ? optimizerModal.optimizer : undefined}
          onClose={() => setOptimizerModal(null)}
          onSave={async (title, placement, affixText) => {
            if (optimizerModal.mode === "create") {
              await addOptimizer(title, placement, affixText);
            } else {
              await updateOptimizer(optimizerModal.optimizer.id, title, placement, affixText);
            }
            setOptimizerModal(null);
          }}
        />
      )}
    </section>
  );
}

function OptimizerModal({
  mode,
  optimizer,
  onClose,
  onSave
}: {
  mode: "create" | "edit";
  optimizer?: PromptOptimizer;
  onClose: () => void;
  onSave: (title: string, placement: "prefix" | "suffix", affixText: string) => Promise<void>;
}) {
  const [title, setTitle] = useState(optimizer?.title ?? "");
  const [placement, setPlacement] = useState<"prefix" | "suffix">(optimizer?.placement ?? "prefix");
  const [affixText, setAffixText] = useState(optimizer?.affixText ?? "");
  const [error, setError] = useState("");

  async function submit(event: FormEvent) {
    event.preventDefault();
    setError("");
    if (!title.trim() || !affixText.trim()) {
      setError("優化器名稱與內容不可空白");
      return;
    }
    try {
      await onSave(title, placement, affixText);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "儲存失敗");
    }
  }

  return (
    <Modal title={mode === "create" ? "新增優化器" : "編輯優化器"} onClose={onClose}>
      <form className="modal-form" onSubmit={submit}>
        <label>
          優化器名稱
          <input autoFocus value={title} onChange={(event) => setTitle(event.target.value)} />
        </label>
        <label>
          類型
          <div className="segmented">
            <button type="button" className={placement === "prefix" ? "selected" : ""} onClick={() => setPlacement("prefix")}>
              前綴
            </button>
            <button type="button" className={placement === "suffix" ? "selected" : ""} onClick={() => setPlacement("suffix")}>
              後綴
            </button>
          </div>
        </label>
        <label>
          {placement === "prefix" ? "前綴內容" : "後綴內容"}
          <textarea value={affixText} onChange={(event) => setAffixText(event.target.value)} />
        </label>
        {error && <p className="form-error">{error}</p>}
        <ModalActions onClose={onClose} submitLabel={mode === "create" ? "新增" : "儲存"} />
      </form>
    </Modal>
  );
}

function MemoDocuments({
  documents,
  selectedDocumentId,
  onSelectDocument,
  onRefresh,
  onNotice
}: {
  documents: MemoDocument[];
  selectedDocumentId: string | null;
  onSelectDocument: (id: string) => void;
  onRefresh: () => Promise<void>;
  onNotice: (message: string) => void;
}) {
  const selectedDocument = documents.find((document) => document.id === selectedDocumentId) ?? documents[0] ?? null;
  const [searchTerm, setSearchTerm] = useState("");
  const [editor, setEditor] = useState<{ mode: "create" } | { mode: "edit"; document: MemoDocument } | null>(null);

  const filteredDocuments = useMemo(() => {
    const query = searchTerm.trim().toLowerCase();
    if (!query) {
      return documents;
    }
    return documents.filter((document) => {
      return [document.title, document.content].some((value) => value.toLowerCase().includes(query));
    });
  }, [documents, searchTerm]);

  async function createDocument(title: string, content: string, copyableRanges: CopyableRange[]) {
    const document = await api<MemoDocument>("/api/memo-documents", {
      method: "POST",
      body: JSON.stringify({ title, content, copyableRanges })
    });
    await onRefresh();
    onSelectDocument(document.id);
  }

  async function updateDocument(documentId: string, title: string, content: string, copyableRanges: CopyableRange[]) {
    await api(`/api/memo-documents/${documentId}`, {
      method: "PATCH",
      body: JSON.stringify({ title, content, copyableRanges })
    });
    await onRefresh();
  }

  async function deleteDocument(document: MemoDocument) {
    if (!window.confirm(`刪除「${document.title}」？`)) {
      return;
    }
    await api(`/api/memo-documents/${document.id}`, { method: "DELETE" });
    await onRefresh();
  }

  async function copyMarkedText(text: string) {
    await copyToClipboard(text);
    onNotice("文字已複製");
  }

  if (editor) {
    return (
      <MemoDocumentEditor
        mode={editor.mode}
        document={editor.mode === "edit" ? editor.document : undefined}
        onCancel={() => setEditor(null)}
        onSave={async (title, content, copyableRanges) => {
          if (editor.mode === "create") {
            await createDocument(title, content, copyableRanges);
          } else {
            await updateDocument(editor.document.id, title, content, copyableRanges);
          }
          setEditor(null);
          onNotice("文件已儲存");
        }}
      />
    );
  }

  return (
    <section className="content-grid">
      <aside className="side-panel">
        <div className="panel-header stacked">
          <div>
            <h2>備忘文件</h2>
            <span>{documents.length}</span>
          </div>
          <button className="primary-button compact" onClick={() => setEditor({ mode: "create" })}>
            <Plus size={16} />
            <span>新增文件</span>
          </button>
        </div>
        <label className="search-field compact-search">
          <Search size={16} />
          <span>搜尋文件</span>
          <input
            value={searchTerm}
            onChange={(event) => setSearchTerm(event.target.value)}
            placeholder="搜尋標題或內容"
          />
        </label>
        <div className="section-list memo-list">
          {filteredDocuments.map((document) => (
            <button
              key={document.id}
              className={document.id === selectedDocument?.id ? "selected" : ""}
              onClick={() => onSelectDocument(document.id)}
            >
              <span>{document.title}</span>
              <small>{splitMemoParagraphs(document.content).length} 段 / {document.copyableRanges.length} 標記</small>
            </button>
          ))}
          {documents.length > 0 && filteredDocuments.length === 0 && <div className="empty small-empty">沒有符合搜尋的文件。</div>}
        </div>
      </aside>

      <section className="detail-panel memo-detail-panel">
        {selectedDocument ? (
          <>
            <div className="detail-header">
              <div>
                <h2>{selectedDocument.title}</h2>
                <p>{selectedDocument.copyableRanges.length} 個文字片段已標記為可複製</p>
              </div>
              <div className="row-actions">
                <button className="icon-button" onClick={() => setEditor({ mode: "edit", document: selectedDocument })}>
                  <Edit3 size={17} />
                  <span>編輯文件</span>
                </button>
                <button className="icon-only danger" onClick={() => void deleteDocument(selectedDocument)} title="刪除文件">
                  <Trash2 size={17} />
                </button>
              </div>
            </div>
            <MemoDocumentReader document={selectedDocument} onCopyMarkedText={copyMarkedText} />
          </>
        ) : (
          <div className="empty fill">
            <button className="primary-button" onClick={() => setEditor({ mode: "create" })}>
              <Plus size={17} />
              <span>新增文件</span>
            </button>
          </div>
        )}
      </section>
    </section>
  );
}

function MemoDocumentEditor({
  mode,
  document,
  onCancel,
  onSave
}: {
  mode: "create" | "edit";
  document?: MemoDocument;
  onCancel: () => void;
  onSave: (title: string, content: string, copyableRanges: CopyableRange[]) => Promise<void>;
}) {
  const textareaRef = useRef<HTMLTextAreaElement | null>(null);
  const [title, setTitle] = useState(document?.title ?? "");
  const [content, setContent] = useState(document?.content ?? "");
  const [copyableRanges, setCopyableRanges] = useState<CopyableRange[]>(document?.copyableRanges ?? []);
  const [error, setError] = useState("");
  const paragraphs = splitMemoParagraphs(content);
  const normalizedRanges = normalizeCopyableRanges(copyableRanges, content);
  const previewParagraphs = splitMemoParagraphsIntoSegments(content, normalizedRanges);

  function markSelectedText() {
    const textarea = textareaRef.current;
    if (!textarea) {
      return;
    }
    const range = getCopyableRangeForSelection(content, textarea.selectionStart, textarea.selectionEnd);
    if (!range) {
      setError("請先選取要標記的文字");
      return;
    }
    setError("");
    setCopyableRanges((current) => normalizeCopyableRanges([...current, range], content));
  }

  function removeRange(range: CopyableRange) {
    setCopyableRanges((current) => current.filter((entry) => entry.start !== range.start || entry.end !== range.end));
  }

  async function submit(event: FormEvent) {
    event.preventDefault();
    setError("");
    if (!title.trim()) {
      setError("文件標題不可空白");
      return;
    }
    try {
      await onSave(title, content, normalizedRanges);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "儲存失敗");
    }
  }

  return (
    <section className="editor-shell">
      <form className="editor-panel" onSubmit={submit}>
        <div className="detail-header">
          <div>
            <h2>{mode === "create" ? "新增文件" : "編輯文件"}</h2>
            <p>{normalizedRanges.length} 個文字片段已標記為可複製</p>
          </div>
          <div className="row-actions">
            <button className="icon-button" type="button" onClick={onCancel}>
              <Eye size={17} />
              <span>返回瀏覽</span>
            </button>
            <button className="primary-button" type="submit">
              <Save size={17} />
              <span>儲存文件</span>
            </button>
          </div>
        </div>

        <label className="editor-title-field">
          文件標題
          <input autoFocus value={title} onChange={(event) => setTitle(event.target.value)} />
        </label>

        <div className="editor-toolbar">
          <button className="icon-button" type="button" onClick={markSelectedText}>
            <Clipboard size={17} />
            <span>標記為可複製</span>
          </button>
          <span>{paragraphs.length} 段內容 / {normalizedRanges.length} 個標記</span>
        </div>

        <textarea
          ref={textareaRef}
          className="memo-editor-textarea"
          value={content}
          onChange={(event) => {
            const nextContent = event.target.value;
            setContent(nextContent);
            setCopyableRanges((current) => normalizeCopyableRanges(current, nextContent));
          }}
          placeholder="輸入長篇備忘內容。選取任意文字後點擊「標記為可複製」。"
        />

        {error && <p className="form-error">{error}</p>}
      </form>

      <aside className="editor-preview">
        <h3>文字標記</h3>
        <div className="memo-paragraphs compact">
          {previewParagraphs.map((segments, paragraphIndex) => (
            <p className="memo-paragraph-preview" key={`preview-${paragraphIndex}`}>
              {segments.map((segment, segmentIndex) => (
                segment.copyable ? (
                  <span className="memo-copyable-text preview" key={`${paragraphIndex}-${segmentIndex}`}>{segment.text}</span>
                ) : (
                  <span key={`${paragraphIndex}-${segmentIndex}`}>{segment.text}</span>
                )
              ))}
            </p>
          ))}
          {paragraphs.length === 0 && <div className="empty small-empty">尚未輸入內容。</div>}
        </div>
        {normalizedRanges.length > 0 && (
          <div className="marked-range-list">
            {normalizedRanges.map((range) => (
              <button className="marked-range-row" key={`${range.start}-${range.end}`} type="button" onClick={() => removeRange(range)}>
                <span>移除</span>
                <strong>{content.slice(range.start, range.end)}</strong>
              </button>
            ))}
          </div>
        )}
      </aside>
    </section>
  );
}

function MemoDocumentReader({
  document,
  onCopyMarkedText
}: {
  document: MemoDocument;
  onCopyMarkedText: (text: string) => Promise<void>;
}) {
  const blocks = getMemoReaderBlocks(splitMemoParagraphsIntoSegments(document.content, document.copyableRanges));

  return (
    <article className="memo-reader">
      {blocks.map((block, blockIndex) => renderMemoReaderBlock(block, blockIndex, onCopyMarkedText))}
      {blocks.length === 0 && <div className="empty fill">這份文件目前沒有內容。</div>}
    </article>
  );
}

function renderMemoReaderBlock(block: MemoReaderBlock, blockIndex: number, onCopyMarkedText: (text: string) => Promise<void>) {
  switch (block.type) {
    case "heading": {
      const HeadingTag = `h${block.level}` as "h1" | "h2" | "h3" | "h4" | "h5" | "h6";
      return (
        <HeadingTag className="memo-reader-heading" key={`heading-${blockIndex}`}>
          {renderMemoReaderInline(block.children, `heading-${blockIndex}`, onCopyMarkedText)}
        </HeadingTag>
      );
    }
    case "unordered-list":
      return (
        <ul className="memo-reader-list" key={`ul-${blockIndex}`}>
          {block.items.map((item, itemIndex) => (
            <li key={`ul-${blockIndex}-${itemIndex}`}>
              {renderMemoReaderInline(item, `ul-${blockIndex}-${itemIndex}`, onCopyMarkedText)}
            </li>
          ))}
        </ul>
      );
    case "ordered-list":
      return (
        <ol className="memo-reader-list" key={`ol-${blockIndex}`}>
          {block.items.map((item, itemIndex) => (
            <li key={`ol-${blockIndex}-${itemIndex}`}>
              {renderMemoReaderInline(item, `ol-${blockIndex}-${itemIndex}`, onCopyMarkedText)}
            </li>
          ))}
        </ol>
      );
    case "blockquote":
      return (
        <blockquote className="memo-reader-quote" key={`quote-${blockIndex}`}>
          {renderMemoReaderInline(block.children, `quote-${blockIndex}`, onCopyMarkedText)}
        </blockquote>
      );
    case "code-block":
      return <pre className="memo-reader-code-block" key={`code-${blockIndex}`}><code>{block.text}</code></pre>;
    case "paragraph":
      return (
        <p className="memo-reader-paragraph" key={`paragraph-${blockIndex}`}>
          {renderMemoReaderInline(block.children, `paragraph-${blockIndex}`, onCopyMarkedText)}
        </p>
      );
  }
}

function renderMemoReaderInline(tokens: MemoReaderInline[], keyPrefix: string, onCopyMarkedText: (text: string) => Promise<void>): ReactNode[] {
  return tokens.map((token, index) => {
    const key = `${keyPrefix}-${index}`;
    switch (token.type) {
      case "copyable":
        return (
          <button
            key={key}
            className="memo-copyable-text"
            onClick={() => void onCopyMarkedText(token.text)}
            title="點擊複製此文字"
          >
            {token.text}
          </button>
        );
      case "strong":
        return <strong key={key}>{renderMemoReaderInline(token.children, key, onCopyMarkedText)}</strong>;
      case "emphasis":
        return <em key={key}>{renderMemoReaderInline(token.children, key, onCopyMarkedText)}</em>;
      case "code":
        return <code className="memo-reader-inline-code" key={key}>{token.text}</code>;
      case "link":
        return (
          <a href={token.href} key={key} rel="noreferrer" target="_blank">
            {renderMemoReaderInline(token.children, key, onCopyMarkedText)}
          </a>
        );
      case "text":
        return <span key={key}>{token.text}</span>;
    }
  });
}

function Modal({ title, onClose, children }: { title: string; onClose: () => void; children: ReactNode }) {
  return (
    <div className="modal-backdrop" role="presentation" onMouseDown={onClose}>
      <section className="modal-panel" role="dialog" aria-modal="true" aria-labelledby="modal-title" onMouseDown={(event) => event.stopPropagation()}>
        <div className="modal-header">
          <h2 id="modal-title">{title}</h2>
          <button className="icon-only" onClick={onClose} title="關閉" type="button">
            <X size={18} />
          </button>
        </div>
        {children}
      </section>
    </div>
  );
}

function ModalActions({ onClose, submitLabel }: { onClose: () => void; submitLabel: string }) {
  return (
    <div className="modal-actions">
      <button className="icon-button" type="button" onClick={onClose}>
        取消
      </button>
      <button className="primary-button" type="submit">
        {submitLabel}
      </button>
    </div>
  );
}

async function api<T = unknown>(
  path: string,
  options: RequestInit & { skipAuthRedirect?: boolean } = {}
): Promise<T> {
  const response = await fetch(path, {
    credentials: "include",
    headers: {
      "Content-Type": "application/json",
      ...options.headers
    },
    ...options
  });

  if (response.status === 401 && !options.skipAuthRedirect) {
    window.location.reload();
  }

  if (!response.ok) {
    const body = await response.json().catch(() => ({ error: "請求失敗" }));
    throw new Error(body.error || "請求失敗");
  }

  return response.json() as Promise<T>;
}
