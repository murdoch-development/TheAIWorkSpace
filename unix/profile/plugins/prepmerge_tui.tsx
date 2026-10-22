/** @jsxImportSource @opentui/solid */
import type { TuiPlugin } from "@opencode-ai/plugin/tui"
import { useTerminalDimensions } from "@opentui/solid"
import type { TextareaRenderable } from "@opentui/core"
import { createContext, createEffect, createMemo, createResource, createSignal, For, Match, Show, Switch, useContext, onCleanup } from "solid-js"
import { $ } from "bun"

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

type DiffFile = {
  readonly file: string
  readonly patch?: string
  readonly additions: number
  readonly deletions: number
  readonly status: "added" | "deleted" | "modified"
}

type DiffView = "split" | "unified"
type Focus = "files" | "diff" | "ai-notes" | "dev-notes"
type FileStatus = DiffFile["status"]

type RouteParams = {
  base?: string
  head?: string
  directory?: string
  annotations?: Record<string, string>
  returnRoute?: { name: string; params?: unknown }
}

type DiffResult =
  | { readonly ok: true; readonly files: DiffFile[] }
  | { readonly ok: false; readonly error: string }

type TreeSection = "unapproved" | "approved"
type FlatRow =
  | { kind: "section"; section: TreeSection; count: number }
  | { kind: "file"; fileIndex: number; section: TreeSection }

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const ROUTE = "prepmerge"
const VCS_DIFF_CONTEXT_LINES = 12
const MIN_SPLIT_WIDTH = 100
const FILE_TREE_WIDTH = 33
const FILE_TREE_STATUS_WIDTH = 2
const PAGE_JUMP = 8
const VIEWPORT_FALLBACK = 10
const Z_INDEX = 2500
const KV_VIEW = "prepmerge-view"

const LANGUAGE_EXTENSIONS: Readonly<Record<string, string>> = {
  ".ts": "typescript", ".tsx": "typescript", ".mts": "typescript", ".cts": "typescript",
  ".js": "javascript", ".jsx": "javascript", ".mjs": "javascript", ".cjs": "javascript",
  ".json": "json", ".jsonc": "json",
  ".md": "markdown", ".markdown": "markdown",
  ".py": "python", ".ps1": "powershell", ".sh": "bash",
  ".sh": "bash", ".bash": "bash", ".zsh": "bash",
  ".go": "go", ".rs": "rust",
  ".css": "css", ".scss": "css",
  ".html": "html", ".htm": "html", ".xml": "xml",
  ".yaml": "yaml", ".yml": "yaml", ".toml": "toml",
  ".sql": "sql",
  ".c": "c", ".h": "c", ".cpp": "cpp", ".cc": "cpp", ".hpp": "cpp",
  ".java": "java", ".rb": "ruby", ".php": "php",
  ".swift": "swift", ".kt": "kotlin", ".lua": "lua", ".vim": "vim",
  ".dockerfile": "dockerfile",
}

const STATUS_LETTER: Record<FileStatus, string> = {
  added: "A",
  deleted: "D",
  modified: "M",
}

// Focus order for tab cycle
const FOCUS_ORDER: Focus[] = ["files", "diff", "ai-notes", "dev-notes"]
const FOCUS_ORDER_NOTES_HIDDEN: Focus[] = ["files", "diff"]

// ---------------------------------------------------------------------------
// Panel layout primitives
// ---------------------------------------------------------------------------

type Axis = "x" | "y"
type SeparatorEdge = "edge" | "edge-in" | "edge-out"
type PanelBorder = "start" | "end" | "both" | "none"

const PanelGroupContext = createContext<{ axis: Axis }>()

function crossAxis(axis: Axis): Axis {
  return axis === "x" ? "y" : "x"
}

function usePanelGroup(): { axis: Axis } | undefined {
  return useContext(PanelGroupContext)
}

function panelBorderSides(axis: Axis, border: Exclude<PanelBorder, "none">): string[] {
  if (axis === "x") return border === "both" ? ["top", "bottom"] : [border === "start" ? "top" : "bottom"]
  return border === "both" ? ["left", "right"] : [border === "start" ? "left" : "right"]
}

function PanelGroup(props: any) {
  return (
    <PanelGroupContext.Provider value={{ axis: props.axis }}>
      <box minWidth={0} minHeight={0} padding={0} flexDirection={props.axis === "x" ? "row" : "column"} {...props}>
        {props.children}
      </box>
    </PanelGroupContext.Provider>
  )
}

function Panel(props: any) {
  const group = usePanelGroup()
  const border = props.border ?? "start"
  const borderProps = border === "none" ? {} : {
    border: panelBorderSides(group?.axis ?? "y", border),
    borderColor: props.borderColor,
  }
  const { border: _b, borderColor: _bc, ...boxProps } = props
  return (
    <box
      minWidth={0}
      minHeight={0}
      flexDirection={crossAxis(group?.axis || "y") === "x" ? "row" : "column"}
      {...borderProps}
      {...boxProps}
    />
  )
}

function Separator(props: { axis?: Axis; color?: any; start?: SeparatorEdge; end?: SeparatorEdge }) {
  const group = usePanelGroup()
  const color = () => props.color
  const axis = () => props.axis ?? crossAxis(group?.axis ?? "y")
  if (axis() === "y") {
    return (
      <Show
        when={props.start || props.end}
        fallback={<box width={1} flexShrink={0} border={["left"]} borderColor={color()} />}
      >
        <box width={1} flexShrink={0} flexDirection="column">
          <Show when={props.start}>{(edge) => <text fg={color()}>{verticalEdge(edge(), "start")}</text>}</Show>
          <box flexGrow={1} border={["left"]} borderColor={color()} />
          <Show when={props.end}>{(edge) => <text fg={color()}>{verticalEdge(edge(), "end")}</text>}</Show>
        </box>
      </Show>
    )
  }
  return (
    <Show
      when={props.start || props.end}
      fallback={<box height={1} flexShrink={0} border={["top"]} borderColor={color()} />}
    >
      <box height={1} flexShrink={0} flexDirection="row">
        <Show when={props.start}>{(edge) => <text fg={color()}>{horizontalEdge(edge(), "start")}</text>}</Show>
        <box flexGrow={1} border={["top"]} borderColor={color()} />
        <Show when={props.end}>{(edge) => <text fg={color()}>{horizontalEdge(edge(), "end")}</text>}</Show>
      </box>
    </Show>
  )
}

function horizontalEdge(edge: SeparatorEdge, side: "start" | "end"): string {
  if (edge === "edge") return side === "start" ? "\u251C" : "\u2524"
  if (edge === "edge-in") return "\u2534"
  return "\u252C"
}

function verticalEdge(edge: SeparatorEdge, side: "start" | "end"): string {
  if (edge === "edge") return side === "start" ? "\u252C" : "\u2534"
  if (edge === "edge-in") return "\u2524"
  return "\u251C"
}

// ---------------------------------------------------------------------------
// Utilities
// ---------------------------------------------------------------------------

function getFiletype(filename: string): string {
  const dot = filename.lastIndexOf(".")
  if (dot < 0) {
    const lower = filename.toLowerCase()
    if (lower === "dockerfile") return "dockerfile"
    if (lower === "makefile" || lower === "gnumakefile") return "make"
    return "none"
  }
  const lang = LANGUAGE_EXTENSIONS[filename.slice(dot).toLowerCase()]
  return lang === "javascript" ? "typescript" : (lang ?? "none")
}

function truncate(str: string, len: number): string {
  if (str.length <= len) return str
  return str.slice(0, Math.max(0, len - 1)) + "."
}

function basename(path: string): string {
  const slash = Math.max(path.lastIndexOf("/"), path.lastIndexOf("\\"))
  return slash >= 0 ? path.slice(slash + 1) : path
}

function dirname(path: string): string {
  const slash = Math.max(path.lastIndexOf("/"), path.lastIndexOf("\\"))
  return slash >= 0 ? path.slice(0, slash) : ""
}

function hasNonWhitespace(text: string | undefined): boolean {
  return !!text && text.trim().length > 0
}

function normalizePatch(patch: string): string {
  const lines = patch.replace(/\r\n?/g, "\n").split("\n")
  let inHunk = false
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]
    if (line.startsWith("@@")) { inHunk = true; continue }
    if (line.startsWith("diff --git") || line.startsWith("Index:") ||
        line.startsWith("--- ") || line.startsWith("+++ ")) { inHunk = false; continue }
    if (inHunk && line === "") lines[i] = " "
  }
  return lines.join("\n")
}

// ---------------------------------------------------------------------------
// Git helpers
// ---------------------------------------------------------------------------

async function runGit(cwd: string, args: readonly string[]): Promise<string> {
  try {
    const result = await $`git ${args}`.cwd(cwd).quiet()
    return result.stdout.toString().trim()
  } catch (e: any) {
    const msg = String(e?.stderr ?? e?.message ?? e)
    if (msg.includes("not a git repository") || msg.includes("not a git repo"))
      throw new Error("Not a git repository")
    throw new Error(`git ${args.join(" ")} failed: ${msg}`)
  }
}

function parseStatuses(output: string): Map<string, FileStatus> {
  const map = new Map<string, FileStatus>()
  for (const line of output.split("\n")) {
    const match = line.match(/^([AMD])\s+(.*)$/)
    if (match) {
      const [, code, file] = match
      map.set(file, code === "A" ? "added" : code === "D" ? "deleted" : "modified")
    }
  }
  return map
}

function parseStats(output: string): Map<string, { additions: number; deletions: number }> {
  const map = new Map<string, { additions: number; deletions: number }>()
  for (const line of output.split("\n")) {
    const match = line.match(/^(\d+|-)\s+(\d+|-)\s+(.*)$/)
    if (match) {
      const [, add, del, file] = match
      map.set(file, {
        additions: add === "-" ? 0 : parseInt(add, 10),
        deletions: del === "-" ? 0 : parseInt(del, 10),
      })
    }
  }
  return map
}

async function runGitDiff(cwd: string, base: string, head: string): Promise<DiffFile[]> {
  await runGit(cwd, ["rev-parse", "--is-inside-work-tree"])
  const ref = `${base}...${head}`
  const changedFiles = (await runGit(cwd, ["diff", "--name-only", ref]))
    .split("\n").filter((f) => f.length > 0)
  if (changedFiles.length === 0) return []
  const [statuses, stats] = await Promise.all([
    parseStatuses(await runGit(cwd, ["diff", "--name-status", ref])),
    parseStats(await runGit(cwd, ["diff", "--numstat", ref])),
  ])
  const files: DiffFile[] = []
  for (const file of changedFiles) {
    const patch = await runGit(cwd, ["diff", ref, "--", file])
    const s = stats.get(file) ?? { additions: 0, deletions: 0 }
    files.push({ file, patch: patch || undefined, additions: s.additions, deletions: s.deletions, status: statuses.get(file) ?? "modified" })
  }
  return files
}

async function getBranches(cwd: string): Promise<string[]> {
  try {
    const out = await runGit(cwd, ["branch", "--format=%(refname:short)"])
    return out.split("\n").map((b) => b.trim()).filter((b) => b.length > 0)
  } catch { return [] }
}

async function getAheadBehind(cwd: string, base: string, head: string): Promise<{ ahead: number; behind: number } | undefined> {
  try {
    const out = await runGit(cwd, ["rev-list", "--left-right", "--count", `${base}...${head}`])
    const parts = out.split(/\s+/).filter(Boolean)
    if (parts.length >= 2) return { ahead: parseInt(parts[1], 10), behind: parseInt(parts[0], 10) }
  } catch {}
  return undefined
}

// ---------------------------------------------------------------------------
// Command bridge
// ---------------------------------------------------------------------------

interface CommandBridge {
  scrollEl: any
  aiNotesScrollEl: any
  textareaEl: TextareaRenderable | undefined
  focus: () => Focus
  scrollBy: (n: number) => void
  scrollPage: (n: number) => void
  toggleView: () => void
  moveFileSelection: (offset: number) => void
  toggleApproval: () => void
  selectFile: () => void
  toggleTree: () => void
  cycleFocus: (reverse: boolean) => void
  switchSource: () => void
  toggleNotesSize: () => void
  returnToAgent: () => void
  close: () => void
}

const noop = () => {}

const bridge: CommandBridge = {
  scrollEl: undefined,
  aiNotesScrollEl: undefined,
  textareaEl: undefined,
  focus: () => "diff",
  scrollBy: noop,
  scrollPage: noop,
  toggleView: noop,
  moveFileSelection: noop,
  toggleApproval: noop,
  selectFile: noop,
  toggleTree: noop,
  cycleFocus: noop,
  switchSource: noop,
  toggleNotesSize: noop,
  returnToAgent: noop,
  close: noop,
}

// ---------------------------------------------------------------------------
// Plugin entry point
// ---------------------------------------------------------------------------

const tui: TuiPlugin = async (api) => {
  api.route.register([{ name: ROUTE, render: () => <PrepMergeViewer api={api} /> }])

  api.keymap.registerLayer({
    commands: [
      {
        name: "prepmerge.open",
        title: "Open prepmerge viewer",
        slashName: "prepmerge",
        category: "VCS",
        namespace: "palette",
        run() {
          const params: RouteParams = { directory: process.cwd(), returnRoute: api.route.current }
          api.route.navigate(ROUTE, params)
          api.ui.dialog.clear()
        },
      },
    ],
  })

  // Listen for prepmerge tool completion via message.part.updated event.
  // When a tool finishes, the server publishes PartUpdated with the full ToolPart,
  // including state.metadata where our __prepmergeOpen flag lives.
  api.event.on("message.part.updated", (event: any) => {
    const part = event?.properties?.part
    if (!part || part.type !== "tool" || part.tool !== "prepmerge") return
    const state = part.state
    if (!state || state.status !== "completed") return
    const meta = state.metadata
    if (!meta?.__prepmergeOpen) return

    const params: RouteParams = {
      base: meta.base,
      head: meta.head,
      directory: meta.directory,
      annotations: meta.annotations ?? {},
      returnRoute: api.route.current,
    }
    api.route.navigate(ROUTE, params)
  })
}

// ---------------------------------------------------------------------------
// In-viewer commands + bindings
// ---------------------------------------------------------------------------

const viewerLayer = {
  commands: [
{
        name: "prepmerge.navigate-down",
        title: "Move down",
        category: "VCS",
        run() {
          if (bridge.focus() === "dev-notes") return
          if (bridge.focus() === "files") bridge.moveFileSelection(1)
          else bridge.scrollBy(1)
        },
      },
      {
        name: "prepmerge.navigate-up",
        title: "Move up",
        category: "VCS",
        run() {
          if (bridge.focus() === "dev-notes") return
          if (bridge.focus() === "files") bridge.moveFileSelection(-1)
          else bridge.scrollBy(-1)
        },
      },
      {
        name: "prepmerge.page-down",
        title: "Page down",
        category: "VCS",
        run() {
          if (bridge.focus() === "dev-notes") return
          if (bridge.focus() === "files") bridge.moveFileSelection(PAGE_JUMP)
          else bridge.scrollPage(1)
        },
      },
      {
        name: "prepmerge.page-up",
        title: "Page up",
        category: "VCS",
        run() {
          if (bridge.focus() === "dev-notes") return
          if (bridge.focus() === "files") bridge.moveFileSelection(-PAGE_JUMP)
          else bridge.scrollPage(-1)
        },
      },
    { name: "prepmerge.toggle-view", title: "Toggle split/unified", category: "VCS", run: () => { if (bridge.focus() !== "dev-notes") bridge.toggleView() } },
    { name: "prepmerge.toggle-approval", title: "Toggle approval", category: "VCS", run: () => { if (bridge.focus() !== "dev-notes") bridge.toggleApproval() } },
    { name: "prepmerge.select-file", title: "Select file", category: "VCS", run: () => { if (bridge.focus() !== "dev-notes") bridge.selectFile() } },
    { name: "prepmerge.toggle-tree", title: "Toggle file tree", category: "VCS", run: () => { if (bridge.focus() !== "dev-notes") bridge.toggleTree() } },
    { name: "prepmerge.cycle-focus", title: "Cycle focus forward", category: "VCS", run: () => bridge.cycleFocus(false) },
    { name: "prepmerge.cycle-focus-reverse", title: "Cycle focus backward", category: "VCS", run: () => bridge.cycleFocus(true) },
    { name: "prepmerge.switch-source", title: "Switch diff source", category: "VCS", run: () => { if (bridge.focus() !== "dev-notes") bridge.switchSource() } },
    { name: "prepmerge.toggle-notes-size", title: "Cycle notes panel size", category: "VCS", run: () => bridge.toggleNotesSize() },
    { name: "prepmerge.return-to-agent", title: "Return to agent", category: "VCS", run: () => { if (bridge.focus() !== "dev-notes") bridge.returnToAgent() } },
    { name: "prepmerge.close", title: "Close prepmerge viewer", category: "VCS", run: () => bridge.close() },
  ],
  bindings: [
    { key: "q,esc", cmd: "prepmerge.close" },
    { key: "down", cmd: "prepmerge.navigate-down" },
    { key: "up", cmd: "prepmerge.navigate-up" },
    { key: "ctrl+d,pagedown", cmd: "prepmerge.page-down" },
    { key: "ctrl+u,pageup", cmd: "prepmerge.page-up" },
    { key: "s", cmd: "prepmerge.toggle-view" },
    { key: "m", cmd: "prepmerge.toggle-approval" },
    { key: "o", cmd: "prepmerge.switch-source" },
    { key: "n", cmd: "prepmerge.toggle-notes-size" },
    { key: "tab", cmd: "prepmerge.cycle-focus" },
    { key: "shift+tab", cmd: "prepmerge.cycle-focus-reverse" },
    { key: "t", cmd: "prepmerge.toggle-tree" },
    { key: "enter,right,l", cmd: "prepmerge.select-file" },
    { key: "r", cmd: "prepmerge.return-to-agent" },
  ],
}

const devNotesLayer = {
  commands: [
    { name: "prepmerge.cycle-focus", title: "Cycle focus forward", category: "VCS", run: () => bridge.cycleFocus(false) },
    { name: "prepmerge.cycle-focus-reverse", title: "Cycle focus backward", category: "VCS", run: () => bridge.cycleFocus(true) },
    { name: "prepmerge.close", title: "Close prepmerge viewer", category: "VCS", run: () => bridge.close() },
  ],
  bindings: [
    { key: "tab", cmd: "prepmerge.cycle-focus" },
    { key: "shift+tab", cmd: "prepmerge.cycle-focus-reverse" },
    { key: "esc", cmd: "prepmerge.cycle-focus" },
  ],
}

function getRouteParams(route: any): RouteParams | undefined {
  return "params" in route ? (route.params as RouteParams | undefined) : undefined
}

// ---------------------------------------------------------------------------
// Main component
// ---------------------------------------------------------------------------

function PrepMergeViewer(props: { api: any }) {
  const dimensions = useTerminalDimensions()
  const theme = () => props.api.theme.current

  const params = () => getRouteParams(props.api.route.current)
  const base = () => params()?.base
  const head = () => params()?.head
  const annotations = () => params()?.annotations ?? {}

  const [currentBranch, setCurrentBranch] = createSignal<string>("HEAD")
  const [repoRoot, setRepoRoot] = createSignal<string>("")
  createEffect(() => {
    runGit(process.cwd(), ["rev-parse", "--abbrev-ref", "HEAD"]).then(setCurrentBranch).catch(() => {})
    runGit(process.cwd(), ["rev-parse", "--show-toplevel"])
      .then((root) => {
        const normalized = root.replace(/\\/g, "/")
        const parts = normalized.split("/").filter(Boolean)
        const tail = parts.slice(-3).join("/")
        const drive = parts.length > 3 && /^[a-zA-Z]:$/.test(parts[0]) ? parts[0] + "/" : ""
        setRepoRoot(drive + (parts.length > 3 ? ".../" : "") + tail)
      }).catch(() => {})
  })

  const [aheadBehind, setAheadBehind] = createSignal<{ ahead: number; behind: number } | undefined>(undefined)
  createEffect(() => {
    const b = base(), h = head()
    if (b && h) getAheadBehind(process.cwd(), b, h).then(setAheadBehind).catch(() => setAheadBehind(undefined))
    else setAheadBehind(undefined)
  })

  const label = createMemo(() => {
    if (base() && head()) {
      const ab = aheadBehind()
      const suffix = ab ? ` (\u2191${ab.ahead} \u2193${ab.behind})` : ""
      return `${base()} \u2192 ${head()}${suffix}`
    }
    return `${currentBranch()} \u2192 ${currentBranch()} (uncommitted)`
  })

  // ---- Data fetching ----

  const diffInput = createMemo(() => ({ base: base(), head: head() }))
  const [diff] = createResource(diffInput, async (input): Promise<DiffResult> => {
    try {
      if (input.base && input.head) {
        const cwd = params()?.directory ?? process.cwd()
        return { ok: true, files: await runGitDiff(cwd, input.base, input.head) }
      }
      const result = await props.api.client.vcs.diff({ mode: "git", context: VCS_DIFF_CONTEXT_LINES }, { throwOnError: true })
      const files: DiffFile[] = (result.data ?? []).filter((f: any) => f.file).map((f: any) => ({
        file: f.file, patch: f.patch, additions: f.additions, deletions: f.deletions, status: f.status ?? "modified" as FileStatus,
      }))
      return { ok: true, files }
    } catch (e: any) { return { ok: false, error: String(e?.message ?? e) } }
  })

  const result = () => diff() ?? { ok: true as const, files: [] as DiffFile[] }
  const files = () => (result().ok ? result().files : [])
  const errorMsg = () => (result().ok ? undefined : result().error)
  const totalAdd = () => files().reduce((s, f) => s + f.additions, 0)
  const totalDel = () => files().reduce((s, f) => s + f.deletions, 0)

  // ---- View state ----

  const [showFileTree, setShowFileTree] = createSignal(true)
  const [focus, setFocus] = createSignal<Focus>("diff")

  // Notes panel size: 0=hidden, 1=1/3, 2=1/2, 3=2/3
  type NotesSize = 0 | 1 | 2 | 3
  const NOTES_RATIOS: Record<Exclude<NotesSize, 0>, number> = { 1: 1 / 3, 2: 1 / 2, 3: 2 / 3 }
  const [notesSize, setNotesSize] = createSignal<NotesSize>(1)

  const contentHeight = createMemo(() => Math.max(0, dimensions().height - 4))
  const notesHeight = createMemo(() => {
    const s = notesSize()
    if (s === 0) return 0
    return Math.max(4, Math.floor(contentHeight() * NOTES_RATIOS[s]))
  })
  const diffHeight = createMemo(() => Math.max(0, contentHeight() - notesHeight()))

  const patchPaneWidth = createMemo(() => dimensions().width - (showFileTree() ? FILE_TREE_WIDTH : 0) - 4)
  const splitAvailable = createMemo(() => patchPaneWidth() >= MIN_SPLIT_WIDTH)
  const [viewOverride, setViewOverride] = createSignal<DiffView | undefined>(props.api.kv.get(KV_VIEW) as DiffView | undefined)
  const view = createMemo<DiffView>(() => splitAvailable() ? (viewOverride() ?? "split") : "unified")

  // ---- Approval state (ephemeral, no KV) ----

  const [approved, setApproved] = createSignal<Set<string>>(new Set())

  // ---- Developer notes (ephemeral, no KV) ----

  const [devNotes, setDevNotes] = createSignal<Record<string, string>>({})
  let textareaEl: TextareaRenderable | undefined

  // Save current textarea content to devNotes
  function saveDevNote() {
    if (!textareaEl || textareaEl.isDestroyed) return
    const file = selectedFile()
    if (!file) return
    const text = textareaEl.plainText
    setDevNotes((prev) => {
      if (prev[file.file] === text) return prev
      return { ...prev, [file.file]: text }
    })
  }

  // Update textarea content when selected file changes
  createEffect(() => {
    const file = selectedFile()
    if (!file || !textareaEl || textareaEl.isDestroyed) return
    const note = devNotes()[file.file] ?? ""
    if (textareaEl.plainText !== note) {
      textareaEl.setText(note)
    }
  })

  // ---- Flat tree rows ----

  const flatRows = createMemo<FlatRow[]>(() => {
    const approvedSet = approved()
    const allFiles = files()
    const unapproved: number[] = []
    const approvedIdx: number[] = []
    for (let i = 0; i < allFiles.length; i++) {
      if (approvedSet.has(allFiles[i].file)) approvedIdx.push(i)
      else unapproved.push(i)
    }
    const rows: FlatRow[] = []
    if (unapproved.length > 0) {
      rows.push({ kind: "section", section: "unapproved", count: unapproved.length })
      for (const idx of unapproved) rows.push({ kind: "file", fileIndex: idx, section: "unapproved" })
    }
    if (approvedIdx.length > 0) {
      rows.push({ kind: "section", section: "approved", count: approvedIdx.length })
      for (const idx of approvedIdx) rows.push({ kind: "file", fileIndex: idx, section: "approved" })
    }
    if (unapproved.length === 0 && approvedIdx.length > 0) {
      rows.unshift({ kind: "section", section: "unapproved", count: 0 })
    }
    return rows
  })

  const [selectedRowIndex, setSelectedRowIndex] = createSignal<number>(0)
  const [selectedFileIndex, setSelectedFileIndex] = createSignal<number | undefined>(undefined)
  let fileTreeScroll: any

  createEffect(() => {
    const rows = flatRows()
    if (rows.length > 0 && selectedFileIndex() === undefined) {
      const firstFile = rows.find((r) => r.kind === "file")
      if (firstFile && firstFile.kind === "file") {
        setSelectedFileIndex(firstFile.fileIndex)
        setSelectedRowIndex(rows.indexOf(firstFile))
      }
    }
  })

  createEffect(() => {
    const idx = selectedRowIndex()
    if (!fileTreeScroll) return
    if (idx < fileTreeScroll.scrollTop) fileTreeScroll.scrollTo(idx)
    else if (idx >= fileTreeScroll.scrollTop + fileTreeScroll.viewport.height)
      fileTreeScroll.scrollTo(idx - fileTreeScroll.viewport.height + 1)
  })

  createEffect(() => {
    if (files().length === 0) {
      setSelectedFileIndex(undefined)
      setSelectedRowIndex(0)
      setApproved(new Set())
      setDevNotes({})
    }
  })

  const selectedFile = createMemo<DiffFile | undefined>(() => {
    const idx = selectedFileIndex()
    if (idx === undefined) return undefined
    return files()[idx]
  })

  const normalizedPatch = createMemo(() => {
    const f = selectedFile()
    return f?.patch ? normalizePatch(f.patch) : undefined
  })

  // ---- Navigation ----

  function moveSelection(offset: number) {
    const rows = flatRows()
    if (rows.length === 0) return
    let idx = selectedRowIndex()
    for (let i = 0; i < Math.abs(offset) * 2 + 2; i++) {
      const next = idx + (offset > 0 ? 1 : -1)
      if (next < 0 || next >= rows.length) return
      const row = rows[next]
      if (row.kind === "file") {
        idx = next
        if (offset > 0) { offset--; i = 0 } else { offset++; i = 0 }
        if (offset === 0) break
      } else { idx = next }
    }
    setSelectedRowIndex(idx)
    const row = rows[idx]
    if (row.kind === "file") setSelectedFileIndex(row.fileIndex)
  }

  // ---- Focus cycling ----

  function doCycleFocus(reverse: boolean) {
    // Save textarea if leaving dev-notes
    if (focus() === "dev-notes") {
      saveDevNote()
      textareaEl?.blur()
    }
    const order = notesSize() > 0 ? FOCUS_ORDER : FOCUS_ORDER_NOTES_HIDDEN
    const current = focus()
    const currentIdx = order.indexOf(current)
    // If current not in order (e.g. notes focused but hidden), start from diff
    const startIdx = currentIdx >= 0 ? currentIdx : order.indexOf("diff")
    const dir = reverse ? -1 : 1
    const nextIdx = (startIdx + dir + order.length) % order.length
    const next = order[nextIdx]
    setFocus(next)
    if (next === "dev-notes") {
      setTimeout(() => { if (!textareaEl || textareaEl.isDestroyed) return; textareaEl.focus() }, 1)
    }
  }

  // ---- Register keybindings (reactive layer swapping) ----

  createEffect(() => {
    const f = focus()
    const layer = f === "dev-notes" ? devNotesLayer : viewerLayer
    let cleanup: (() => void) | undefined
    try {
      const ret = props.api.keymap.registerLayer(layer)
      if (typeof ret === "function") cleanup = ret
      else if (ret && typeof ret.dispose === "function") cleanup = ret.dispose
      else if (ret && typeof ret.off === "function") cleanup = ret.off
    } catch {}
    onCleanup(() => cleanup?.())
  })

  // ---- Wire command bridge ----

  bridge.focus = () => focus()
  bridge.scrollBy = (n: number) => {
    const el = focus() === "ai-notes" ? bridge.aiNotesScrollEl : bridge.scrollEl
    el?.scrollBy(n)
  }
  bridge.scrollPage = (n: number) => {
    const el = focus() === "ai-notes" ? bridge.aiNotesScrollEl : bridge.scrollEl
    const h = el?.viewport?.height ?? VIEWPORT_FALLBACK
    el?.scrollBy(n * h)
  }
  bridge.toggleView = () => {
    if (!splitAvailable()) return
    const next: DiffView = view() === "split" ? "unified" : "split"
    setViewOverride(next)
    props.api.kv.set(KV_VIEW, next)
  }
  bridge.moveFileSelection = (offset: number) => moveSelection(offset)
  bridge.toggleApproval = () => {
    const file = selectedFile()
    if (!file) return
    const fname = file.file
    setApproved((prev) => {
      const next = new Set(prev)
      if (next.has(fname)) next.delete(fname)
      else next.add(fname)
      return next
    })
  }
  bridge.selectFile = () => {
    const rows = flatRows()
    const row = rows[selectedRowIndex()]
    if (row && row.kind === "file") {
      setSelectedFileIndex(row.fileIndex)
      setFocus("diff")
    }
  }
  bridge.toggleTree = () => setShowFileTree((v) => !v)
  bridge.cycleFocus = doCycleFocus
  bridge.toggleNotesSize = () => {
    // If cycling to hidden while notes focused, switch to diff
    const next = ((notesSize() + 1) % 4) as NotesSize
    setNotesSize(next)
    if (next === 0 && (focus() === "ai-notes" || focus() === "dev-notes")) {
      setFocus("diff")
      textareaEl?.blur()
    }
  }
  bridge.switchSource = () => {
    const cwd = process.cwd()
    getBranches(cwd).then((branches) => {
      if (branches.length === 0) return
      const current = currentBranch()
      const DialogSelect = props.api.ui.DialogSelect
      if (!DialogSelect) return
      const pickBase = () => {
        props.api.ui.dialog.replace(() => (
          <DialogSelect
            title={`Diff source — step 1: LEFT side (base)`}
            options={branches.map((b) => ({
              title: b,
              description: b === current ? "\u2713 checked out" : undefined,
              value: b,
              onSelect() { props.api.ui.dialog.clear(); pickHead(b) },
            }))}
          />
        ))
      }
      const pickHead = (baseBranch: string) => {
        props.api.ui.dialog.replace(() => (
          <DialogSelect
            title={`Diff source — step 2: RIGHT side (head)  —  ${baseBranch} → ?`}
            options={branches.map((b) => ({
              title: b,
              description: b === current ? "\u2713 checked out" : b === baseBranch ? "(same as left)" : undefined,
              value: b,
              disabled: b === baseBranch,
              onSelect() {
                props.api.ui.dialog.clear()
                props.api.route.navigate(ROUTE, { ...params(), base: baseBranch, head: b, returnRoute: params()?.returnRoute })
              },
            }))}
          />
        ))
      }
      pickBase()
    }).catch(() => {})
  }

  // ---- Return to agent ----

  bridge.returnToAgent = () => {
    const allFiles = files()
    if (allFiles.length === 0) return

    const approvedSet = approved()
    const notes = devNotes()
    const approvedFiles = allFiles.filter((f) => approvedSet.has(f.file))
    const unapprovedFiles = allFiles.filter((f) => !approvedSet.has(f.file))
    const filesWithNotes = allFiles.filter((f) => hasNonWhitespace(notes[f.file]))

    // Build compact preview for confirm dialog
    const fileLines = allFiles.slice(0, 10).map((f) => {
      const status = approvedSet.has(f.file) ? "\u2713" : "\u2717"
      const notesFlag = hasNonWhitespace(notes[f.file]) ? "\u2713" : "\u2014"
      const name = truncate(f.file, 38)
      return `${status} ${notesFlag}  ${name}`
    }).join("\n")
    const moreLine = allFiles.length > 10 ? `\n... and ${allFiles.length - 10} more` : ""
    const summary = `${fileLines}${moreLine}\n\n${approvedFiles.length} approved, ${unapprovedFiles.length} unapproved, ${filesWithNotes.length} with notes`

    const DialogConfirm = props.api.ui.DialogConfirm
    if (!DialogConfirm) return

    props.api.ui.dialog.replace(() => (
      <DialogConfirm
        title="Return to agent"
        message={summary}
        label="cancel"
        onConfirm={() => {
          props.api.ui.dialog.clear()

          // Build full summary for the agent
          const lines: string[] = []
          lines.push(`I've reviewed the diff: ${label()}. Here's my assessment:`)
          lines.push("")

          if (approvedFiles.length > 0) {
            lines.push(`**Approved changes** (${approvedFiles.length} files):`)
            for (const f of approvedFiles) {
              const note = notes[f.file]
              lines.push(hasNonWhitespace(note) ? `- ${f.file}\n  Note: ${note!.trim()}` : `- ${f.file}`)
            }
            lines.push("")
          }

          if (unapprovedFiles.length > 0) {
            lines.push(`**Unapproved changes** (${unapprovedFiles.length} files) — need discussion before proceeding:`)
            for (const f of unapprovedFiles) {
              const note = notes[f.file]
              lines.push(hasNonWhitespace(note) ? `- ${f.file}\n  Note: ${note!.trim()}` : `- ${f.file}`)
            }
            lines.push("")
          }

          if (approvedFiles.length === 0 && unapprovedFiles.length === 0) {
            lines.push("No files changed.")
          } else if (unapprovedFiles.length === 0) {
            lines.push("All changes approved, ready to proceed.")
          } else {
            lines.push("Please address the unapproved changes. I'd like to discuss how these should be adjusted before we proceed.")
          }

          const summaryText = lines.join("\n")

          // Get session ID from returnRoute
          const ret = params()?.returnRoute
          const routeParams = getRouteParams(ret as any)
          const sessionId = routeParams?.sessionID
          if (!sessionId) {
            const DialogAlert = props.api.ui.DialogAlert
            if (DialogAlert) {
              props.api.ui.dialog.replace(() => <DialogAlert title="No session" message="No active session to return to." onConfirm={() => props.api.ui.dialog.clear()} />)
            }
            return
          }

          // Send to agent via promptAsync
          props.api.client.session.promptAsync({
            sessionID: sessionId,
            parts: [{ type: "text", text: summaryText }],
          }).then(() => {
            // Navigate back to session
            props.api.route.navigate(ret?.name ?? "home", routeParams)
          }).catch(() => {})
        }}
        onCancel={() => {}
        }
      />
    ))
  }

  // ---- Close with warning ----

  bridge.close = () => {
    const allFiles = files()
    if (allFiles.length === 0) {
      doClose()
      return
    }

    const approvedSet = approved()
    const notes = devNotes()
    const unapprovedCount = allFiles.filter((f) => !approvedSet.has(f.file)).length
    const notesCount = allFiles.filter((f) => hasNonWhitespace(notes[f.file])).length

    if (unapprovedCount === 0 && notesCount === 0) {
      doClose()
      return
    }

    const DialogConfirm = props.api.ui.DialogConfirm
    if (!DialogConfirm) { doClose(); return }

    const parts: string[] = []
    if (unapprovedCount > 0) parts.push(`${unapprovedCount} unapproved file${unapprovedCount > 1 ? "s" : ""}`)
    if (notesCount > 0) parts.push(`${notesCount} file${notesCount > 1 ? "s" : ""} with developer notes`)
    const message = `You have ${parts.join(" and ")} that will be lost.`

    props.api.ui.dialog.replace(() => (
      <DialogConfirm
        title="Close prepmerge viewer?"
        message={message}
        label="cancel"
        onConfirm={() => { props.api.ui.dialog.clear(); doClose() }}
        onCancel={() => props.api.ui.dialog.clear()}
      />
    ))
  }

  function doClose() {
    saveDevNote()
    const ret = params()?.returnRoute
    props.api.route.navigate(ret?.name ?? "home", getRouteParams(ret as any))
  }

  // ---- onCleanup ----

  onCleanup(() => {
    saveDevNote()
    bridge.scrollEl = undefined
    bridge.aiNotesScrollEl = undefined
    bridge.textareaEl = undefined
    bridge.focus = () => "diff"
    bridge.scrollBy = noop
    bridge.scrollPage = noop
    bridge.toggleView = noop
    bridge.moveFileSelection = noop
    bridge.toggleApproval = noop
    bridge.selectFile = noop
    bridge.toggleTree = noop
    bridge.cycleFocus = noop
    bridge.switchSource = noop
    bridge.toggleNotesSize = noop
    bridge.returnToAgent = noop
    bridge.close = noop
  })

  const t = () => theme()

  // ---- Render ----

  const focusOrder = createMemo(() => notesSize() > 0 ? FOCUS_ORDER : FOCUS_ORDER_NOTES_HIDDEN)
  const nextFocus = createMemo(() => {
    const order = focusOrder()
    const idx = order.indexOf(focus())
    if (idx < 0) return order[0]
    return order[(idx + 1) % order.length]
  })

  return (
    <box position="absolute" zIndex={Z_INDEX} left={0} top={0} width={dimensions().width} height={dimensions().height}>
      <PanelGroup axis="y" width="100%" height="100%">
        {/* Header */}
        <Panel border="none" flexShrink={0} padding={0} paddingLeft={1}>
          <text fg={t().textMuted}>{repoRoot()} </text>
          <text fg={t().text}>PrepMerge </text>
          <text fg={t().textMuted}>{label()}</text>
          <box flexGrow={1} />
          <text fg={t().textMuted}>{files().length} {files().length === 1 ? "file" : "files"}</text>
          <text fg={t().textMuted}>  {splitAvailable() ? view() : "unified"}</text>
        </Panel>

        {/* Body */}
        <box flexGrow={1} minHeight={0}>
          <Switch>
            <Match when={diff.loading}>
              <Separator axis="x" color={t().border} />
              <box flexGrow={1} paddingLeft={1}><text fg={t().textMuted}>Loading diff...</text></box>
            </Match>
            <Match when={!diff.loading && errorMsg()}>
              <Separator axis="x" color={t().border} />
              <box flexGrow={1} paddingLeft={1}><text fg={t().error}>{errorMsg()}</text></box>
            </Match>
            <Match when={!diff.loading && !errorMsg() && files().length === 0}>
              <Separator axis="x" color={t().border} />
              <box flexGrow={1} paddingLeft={1}><text fg={t().textMuted}>No diff!</text></box>
            </Match>
            <Match when={!diff.loading && !errorMsg() && files().length > 0}>
              <PanelGroup axis="x">
                {/* File tree */}
                <Show when={showFileTree()}>
                  <Panel border="both" width={FILE_TREE_WIDTH} borderColor={t().border}>
                    <scrollbox
                      ref={(el: any) => { fileTreeScroll = el }}
                      flexGrow={1} minHeight={0}
                      verticalScrollbarOptions={{ visible: false }}
                      horizontalScrollbarOptions={{ visible: false }}
                    >
                      <For each={flatRows()}>
                        {(row, index) => {
                          const isHighlighted = () => focus() === "files" && selectedRowIndex() === index()
                          const isSelectedFile = () => row.kind === "file" && selectedFileIndex() === row.fileIndex
                          if (row.kind === "section") {
                            return (
                              <box flexDirection="row" width="100%" paddingLeft={1}>
                                <text fg={t().textMuted} bold>{row.section === "unapproved" ? "Unapproved" : "Approved"}</text>
                                <box flexGrow={1} />
                                <text fg={t().textMuted}>{row.count} </text>
                              </box>
                            )
                          }
                          const file = () => files()[row.fileIndex]
                          const isApproved = () => row.section === "approved"
                          const statusChar = () => {
                            const s = file()?.status
                            return s === "added" ? "A" : s === "deleted" ? "D" : "M"
                          }
                          const nameWidth = FILE_TREE_WIDTH - FILE_TREE_STATUS_WIDTH - 4
                          const name = () => truncate(basename(file()?.file ?? ""), nameWidth)
                          const dir = () => dirname(file()?.file ?? "")
                          const nameColor = () =>
                            isHighlighted() ? t().background
                            : isApproved() ? t().textMuted
                            : isSelectedFile() ? t().primary
                            : t().text
                          const statusColor = () =>
                            isHighlighted() ? t().background
                            : file()?.status === "added" ? t().diffAdded
                            : file()?.status === "deleted" ? t().diffRemoved
                            : t().textMuted
                          return (
                            <box flexDirection="row" width="100%" backgroundColor={isHighlighted() ? t().primary : undefined}>
                              <text fg={isHighlighted() ? t().background : t().textMuted} wrapMode="none" flexShrink={0}>{"  "}</text>
                              <box flexGrow={1} minWidth={0}>
                                <text fg={nameColor()} wrapMode="none">{name()}</text>
                                <Show when={dir() && isSelectedFile()}>
                                  <text fg={t().textMuted} wrapMode="none"> {dir()}</text>
                                </Show>
                              </box>
                              <text fg={statusColor()} wrapMode="none" flexShrink={0}>{isApproved() ? "\u2713" : statusChar()}</text>
                            </box>
                          )
                        }}
                      </For>
                    </scrollbox>
                  </Panel>
                </Show>

                {/* Right side: diff (top) + notes (bottom) */}
                <Panel flexGrow={1} minHeight={0} border="none" borderColor={t().border}>
                  <Separator axis="x" color={t().border} start={showFileTree() ? "edge-out" : undefined} />
                  <PanelGroup axis="y" flexGrow={1} minHeight={0}>
                    {/* Diff inspector */}
                    <Panel flexGrow={notesSize() === 0 ? 1 : undefined} height={notesSize() === 0 ? undefined : diffHeight()} minHeight={0} border="none" borderColor={t().border}>
                      <Show when={selectedFile()} fallback={
                        <box flexGrow={1} paddingLeft={1}><text fg={t().textMuted}>Select a file from the tree</text></box>
                      }>
                        {(file) => (
                          <scrollbox
                            ref={(el: any) => { bridge.scrollEl = el }}
                            flexGrow={1} minHeight={0}
                            verticalScrollbarOptions={{ visible: true }}
                            horizontalScrollbarOptions={{ visible: false }}
                          >
                            <box flexDirection="row" gap={1} flexShrink={0} paddingLeft={1} paddingRight={1} border={["left"]} borderColor={focus() === "diff" ? t().primary : t().border}>
                              <text fg={file().status === "added" ? t().diffAdded : file().status === "deleted" ? t().diffRemoved : t().text}>{file().file}</text>
                              <box flexGrow={1} />
                              <text fg={t().diffAdded}>+{file().additions}</text>
                              <text fg={t().diffRemoved}>-{file().deletions}</text>
                            </box>
                            <Show when={normalizedPatch()} fallback={<text fg={t().textMuted} paddingLeft={1}>No patch available for this file.</text>}>
                              <box border={["left"]} borderColor={t().border}>
                                <diff
                                  diff={normalizedPatch()!} view={view()} filetype={getFiletype(file().file)}
                                  showLineNumbers={true} width="100%" wrapMode="char" fg={t().text}
                                  addedBg={t().diffAddedBg} removedBg={t().diffRemovedBg}
                                  addedSignColor={t().diffHighlightAdded} removedSignColor={t().diffHighlightRemoved}
                                  lineNumberFg={t().diffLineNumber}
                                  addedLineNumberBg={t().diffAddedLineNumberBg} removedLineNumberBg={t().diffRemovedLineNumberBg}
                                />
                              </box>
                            </Show>
                          </scrollbox>
                        )}
                      </Show>
                    </Panel>

                    {/* Notes panel — side by side AI notes + Developer notes */}
                    <Show when={notesSize() > 0}>
                      <Panel flexShrink={0} height={notesHeight()} minHeight={0} border="start" borderColor={t().border}>
                        <PanelGroup axis="x" flexGrow={1} minHeight={0}>
                          {/* AI notes (left) */}
                          <Panel width="50%" minWidth={0} border="end" borderColor={focus() === "ai-notes" ? t().primary : t().border}>
                            <box flexDirection="row" paddingLeft={1} flexShrink={0}>
                              <text fg={focus() === "ai-notes" ? t().primary : t().textMuted} bold>AI notes</text>
                              <box flexGrow={1} />
                            </box>
                            <scrollbox
                              ref={(el: any) => { bridge.aiNotesScrollEl = el }}
                              flexGrow={1} minHeight={0}
                              paddingLeft={1} paddingRight={1}
                              verticalScrollbarOptions={{ visible: true }}
                              horizontalScrollbarOptions={{ visible: false }}
                            >
                              <Show when={selectedFile()} fallback={<text fg={t().textMuted}>No file selected</text>}>
                                {(file) => (
                                  <Show when={annotations()[file().file]} fallback={<text fg={t().textMuted}>No AI notes for this file.</text>}>
                                    <text fg={t().syntaxComment} wrapMode="word">{annotations()[file().file]}</text>
                                  </Show>
                                )}
                              </Show>
                            </scrollbox>
                          </Panel>

                          {/* Developer notes (right) */}
                          <Panel width="50%" minWidth={0} border="none" borderColor={focus() === "dev-notes" ? t().primary : t().border}>
                            <box flexDirection="row" paddingLeft={1} flexShrink={0}>
                              <text fg={focus() === "dev-notes" ? t().primary : t().textMuted} bold>Developer notes</text>
                              <box flexGrow={1} />
                            </box>
                            <textarea
                              ref={(el: TextareaRenderable) => { textareaEl = el; bridge.textareaEl = el }}
                              flexGrow={1}
                              minHeight={0}
                              paddingLeft={1}
                              paddingRight={1}
                              placeholder="Start typing to add notes..."
                              placeholderColor={t().textMuted}
                              textColor={t().text}
                              cursorColor={t().text}
                            />
                          </Panel>
                        </PanelGroup>
                      </Panel>
                    </Show>
                  </PanelGroup>
                  <Separator axis="x" color={t().border} start={showFileTree() ? "edge-in" : undefined} />
                </Panel>
              </PanelGroup>
            </Match>
          </Switch>
        </box>

        {/* Footer */}
        <Panel flexShrink={0} gap={2} paddingLeft={1} border="none" borderColor={t().border}>
          <Show when={focus() === "files"} fallback={
            <Show when={focus() === "diff"} fallback={
              <Show when={focus() === "ai-notes"} fallback={
                <text fg={t().text}>type to edit <span style={{ fg: t().textMuted }}>tab/shift+tab next panel</span></text>
              }>
                <text fg={t().text}>{"\u2191/\u2193"} <span style={{ fg: t().textMuted }}>scroll notes</span></text>
              </Show>
            }>
              <text fg={t().text}>{"\u2191/\u2193"} <span style={{ fg: t().textMuted }}>scroll</span></text>
              <text fg={t().text}>pgup/pgdn <span style={{ fg: t().textMuted }}>page</span></text>
              <Show when={splitAvailable()}>
                <text fg={t().text}>s <span style={{ fg: t().textMuted }}>{view() === "split" ? "unified" : "split"}</span></text>
              </Show>
            </Show>
          }>
            <text fg={t().text}>{"\u2191/\u2193"} <span style={{ fg: t().textMuted }}>navigate</span></text>
            <text fg={t().text}>m <span style={{ fg: t().textMuted }}>approve</span></text>
            <text fg={t().text}>enter <span style={{ fg: t().textMuted }}>open</span></text>
          </Show>
          <text fg={t().text}>tab <span style={{ fg: t().textMuted }}>{nextFocus()}</span></text>
          <Show when={focus() !== "dev-notes"}>
            <text fg={t().text}>o <span style={{ fg: t().textMuted }}>source</span></text>
            <text fg={t().text}>m <span style={{ fg: t().textMuted }}>approve</span></text>
          </Show>
          <text fg={t().text}>n <span style={{ fg: t().textMuted }}>notes {notesSize() === 0 ? "1/3" : ["off", "1/2", "2/3", "off"][notesSize()]}</span></text>
          <text fg={t().text}>r <span style={{ fg: t().textMuted }}>return</span></text>
          <text fg={t().text}>t <span style={{ fg: t().textMuted }}>{showFileTree() ? "hide tree" : "show tree"}</span></text>
          <text fg={t().text}>q <span style={{ fg: t().textMuted }}>close</span></text>
          <box flexGrow={1} />
          <text fg={t().textMuted}>{approved().size}/{files().length} approved</text>
          <text fg={t().diffAdded}>+{totalAdd()}</text>
          <text fg={t().diffRemoved}>-{totalDel()}</text>
        </Panel>
      </PanelGroup>
    </box>
  )
}

export default { id: "prepmerge", tui }