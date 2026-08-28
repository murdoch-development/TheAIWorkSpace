import { type Plugin, tool } from "@opencode-ai/plugin"
import { $ } from "bun"

type GitFileStatus = "added" | "deleted" | "modified"

interface DiffFile {
  file: string
  patch?: string
  additions: number
  deletions: number
  status: GitFileStatus
}

async function runPrepMergeDiff(cwd: string, base: string, head: string): Promise<DiffFile[]> {
  const files: DiffFile[] = []

  const nameResult = await $`git diff --name-only ${base}...${head}`.cwd(cwd).quiet()
  const changedFiles = nameResult.stdout.toString().trim().split("\n").filter((f) => f.length > 0)

  if (changedFiles.length === 0) return files

  const statusResult = await $`git diff --name-status ${base}...${head}`.cwd(cwd).quiet()
  const statusLines = statusResult.stdout.toString().trim().split("\n")

  const statusMap = new Map<string, GitFileStatus>()
  for (const line of statusLines) {
    const match = line.match(/^([AMD])\s+(.*)$/)
    if (match) {
      const [, status, file] = match
      statusMap.set(file, status === "A" ? "added" : status === "D" ? "deleted" : "modified")
    }
  }

  const numstatResult = await $`git diff --numstat ${base}...${head}`.cwd(cwd).quiet()
  const numstatLines = numstatResult.stdout.toString().trim().split("\n")

  const statsMap = new Map<string, { additions: number; deletions: number }>()
  for (const line of numstatLines) {
    const match = line.match(/^(\d+|-)\s+(\d+|-)\s+(.*)$/)
    if (match) {
      const [, add, del, file] = match
      statsMap.set(file, {
        additions: add === "-" ? 0 : parseInt(add, 10),
        deletions: del === "-" ? 0 : parseInt(del, 10),
      })
    }
  }

  for (const file of changedFiles) {
    const patchResult = await $`git diff ${base}...${head} -- ${file}`.cwd(cwd).quiet()
    const patch = patchResult.stdout.toString()
    const stats = statsMap.get(file) ?? { additions: 0, deletions: 0 }
    files.push({
      file,
      patch: patch.trim() || undefined,
      additions: stats.additions,
      deletions: stats.deletions,
      status: statusMap.get(file) ?? "modified",
    })
  }

  return files
}

function buildDiffArgs(base?: string, head?: string): string[] {
  if (!base && !head) return ["diff", "HEAD"]
  if (base && head) return ["diff", `${base}...${head}`]
  throw new Error("Provide both 'base' and 'head', or neither for working tree mode.")
}

async function getFileStatusMap(cwd: string, diffArgs: string[]): Promise<Map<string, GitFileStatus>> {
  const statusResult = await $`git ${["diff", "--name-status", ...diffArgs.slice(1)]}`.cwd(cwd).quiet()
  const lines = statusResult.stdout.toString().trim().split("\n").filter((l) => l.length > 0)
  const map = new Map<string, GitFileStatus>()
  for (const line of lines) {
    const match = line.match(/^([AMD])\s+(.*)$/)
    if (match) {
      const [, status, file] = match
      map.set(file, status === "A" ? "added" : status === "D" ? "deleted" : "modified")
    }
  }
  return map
}

async function getNumstatMap(cwd: string, diffArgs: string[]): Promise<Map<string, { additions: number; deletions: number; binary: boolean }>> {
  const numstatResult = await $`git ${["diff", "--numstat", ...diffArgs.slice(1)]}`.cwd(cwd).quiet()
  const lines = numstatResult.stdout.toString().trim().split("\n").filter((l) => l.length > 0)
  const map = new Map<string, { additions: number; deletions: number; binary: boolean }>()
  for (const line of lines) {
    const match = line.match(/^(\d+|-)\s+(\d+|-)\s+(.*)$/)
    if (match) {
      const [, add, del, file] = match
      const binary = add === "-" && del === "-"
      map.set(file, {
        additions: binary ? 0 : add === "-" ? 0 : parseInt(add, 10),
        deletions: binary ? 0 : del === "-" ? 0 : parseInt(del, 10),
        binary,
      })
    }
  }
  return map
}

async function getDefaultBranch(cwd: string): Promise<string> {
  try {
    const result =
      await $`git symbolic-ref refs/remotes/origin/HEAD`.cwd(cwd).quiet()
    const ref = result.stdout.toString().trim()
    if (ref.startsWith("refs/remotes/origin/")) return ref.slice("refs/remotes/origin/".length)
    return ref || "main"
  } catch {
    try {
      const result = await $`git rev-parse --abbrev-ref origin/HEAD`.cwd(cwd).quiet()
      const ref = result.stdout.toString().trim()
      return ref.replace(/^origin\//, "") || "main"
    } catch {
      return "main"
    }
  }
}

const PrepMergePlugin: Plugin = async (ctx) => {
  return {
    config: (opencodeConfig) => {
      const existing = opencodeConfig.experimental?.primary_tools ?? []
      opencodeConfig.experimental = {
        ...opencodeConfig.experimental,
        primary_tools: [...existing, "prepmerge", "get_diff_files_list", "get_diff_file"],
      }
    },
    tool: {
      prepmerge: tool({
        description:
          "Prepare for a merge: show a git diff between two git refs (branches, commits, tags, etc.) and open an interactive prepmerge viewer panel. " +
          "Supports branch-to-branch, commit-to-commit, and any git ref comparison. " +
          "Examples: prepmerge(base='main', head='feature-branch'), prepmerge(base='abc123', head='def456'), prepmerge(base='v1.0', head='HEAD'). " +
          "If base/head are omitted, shows the working tree diff. " +
          "Pass 'annotations' with per-file AI notes assembled from your review of the changes.",
        args: {
          base: tool.schema
            .string()
            .optional()
            .describe("The base git ref to compare FROM (e.g. 'main', 'abc123', 'v1.0'). Defaults to working tree."),
          head: tool.schema
            .string()
            .optional()
            .describe("The head git ref to compare TO (e.g. 'feature-branch', 'def456', 'HEAD'). Defaults to working tree."),
          mode: tool.schema
            .string()
            .optional()
            .describe("Direct mode selection: 'git' (working tree), 'branch' (vs default branch). Overrides base/head if specified."),
          file: tool.schema
            .string()
            .optional()
            .describe("Optional: show diff for a single file only. If omitted, shows all changed files."),
          repo: tool.schema
            .string()
            .optional()
            .describe("Optional: path to the git repo. Defaults to the session directory."),
          annotations: tool.schema
            .record(tool.schema.string(), tool.schema.string())
            .optional()
            .describe("Optional: per-file AI notes. JSON object mapping filenames to note strings. Displayed in the AI notes panel."),
        },
        async execute(args, context) {
          const { base, head, mode, file, repo, annotations } = args
          const cwd = repo || context.directory

          // Working tree mode (no base/head or mode=git)
          if (mode === "git" || (mode === undefined && !base && !head)) {
            return {
              title: "Working tree diff",
              output:
                "Interactive diff panel opened in git (working tree) mode. " +
                "The panel shows the diff with full syntax highlighting, file tree, and split/unified views.",
              metadata: {
                __prepmergeOpen: true,
                mode: "git",
                directory: cwd,
                annotations: annotations ?? {},
              },
            }
          }

          // Branch mode: resolve default branch as base, HEAD as head
          if (mode === "branch") {
            const baseRef = await getDefaultBranch(cwd)
            return {
              title: `Branch diff: ${baseRef} → HEAD`,
              output: `Interactive diff panel opened comparing ${baseRef} to HEAD.`,
              metadata: {
                __prepmergeOpen: true,
                mode: "branch",
                base: baseRef,
                head: "HEAD",
                directory: cwd,
                annotations: annotations ?? {},
              },
            }
          }

          if (!base || !head) {
            return {
              title: "Missing refs",
              output:
                "Both 'base' and 'head' are required for branch-to-branch diff. " +
                "Example: diff(base='main', head='feature-branch').",
            }
          }

          try {
            let diffFiles: DiffFile[]
            if (file) {
              const allFiles = await runPrepMergeDiff(cwd, base, head)
              diffFiles = allFiles.filter((f) => f.file === file)
            } else {
              diffFiles = await runPrepMergeDiff(cwd, base, head)
            }

            if (diffFiles.length === 0) {
              return {
                title: "No changes",
                output: `No files changed between ${base} and ${head}.`,
              }
            }

            const totalAdd = diffFiles.reduce((sum, f) => sum + f.additions, 0)
            const totalDel = diffFiles.reduce((sum, f) => sum + f.deletions, 0)
            const title = `${base} \u2192 ${head}`

            return {
              title: `Diff: ${title}`,
              output:
                `Diff panel opened: **${title}**\n\n` +
                `${diffFiles.length} file(s) changed \u2014 +${totalAdd} additions, -${totalDel} deletions.\n\n` +
                `Files:\n${diffFiles.map((f) => `- ${f.file} (+${f.additions} -${f.deletions})`).join("\n")}`,
              metadata: {
                __prepmergeOpen: true,
                mode: "custom",
                base,
                head,
                directory: cwd,
                annotations: annotations ?? {},
                files: diffFiles.map((f) => ({
                  file: f.file,
                  additions: f.additions,
                  deletions: f.deletions,
                  status: f.status,
                })),
                fileCount: diffFiles.length,
                additions: totalAdd,
                deletions: totalDel,
              },
            }
          } catch (err: any) {
            return {
              title: "Diff failed",
              output: `Failed to compute diff between ${base} and ${head}: ${err?.message ?? err}`,
            }
          }
        },
      }),

      get_diff_files_list: tool({
        description:
          "Get a structured list of files changed in a git diff. Read-only — safe to call. " +
          "Use this to see which files changed and their stats before reviewing individual diffs. " +
          "Modes: both base+head omitted → working tree (git diff HEAD, staged+unstaged vs last commit); " +
          "both provided → branch-to-branch (git diff base...head). " +
          "Examples: get_diff_files_list(), get_diff_files_list(base='main', head='feature-branch').",
        args: {
          base: tool.schema
            .string()
            .optional()
            .describe("The base git ref to compare FROM. Omit for working tree mode."),
          head: tool.schema
            .string()
            .optional()
            .describe("The head git ref to compare TO. Omit for working tree mode."),
          repo: tool.schema
            .string()
            .optional()
            .describe("Optional: path to the git repo. Defaults to the session directory."),
        },
        async execute(args, context) {
          const { base, head, repo } = args
          const cwd = repo || context.directory
          try {
            const diffArgs = buildDiffArgs(base, head)
            const statusMap = await getFileStatusMap(cwd, diffArgs)
            const numstatMap = await getNumstatMap(cwd, diffArgs)

            const allFiles = new Set<string>([...statusMap.keys(), ...numstatMap.keys()])
            if (allFiles.size === 0) {
              return {
                title: "No changes",
                output: base && head
                  ? `No files changed between ${base} and ${head}.`
                  : "No uncommitted changes in the working tree.",
              }
            }

            const byStatus: Record<string, { file: string; additions: number; deletions: number; binary: boolean }[]> = {
              modified: [],
              added: [],
              deleted: [],
            }
            let totalAdd = 0
            let totalDel = 0
            for (const file of allFiles) {
              const status = statusMap.get(file) ?? "modified"
              const stats = numstatMap.get(file) ?? { additions: 0, deletions: 0, binary: false }
              byStatus[status]?.push({ file, ...stats })
              totalAdd += stats.additions
              totalDel += stats.deletions
            }

            const lines: string[] = []
            const statusLabels: Record<string, string> = { modified: "Modified", added: "Added", deleted: "Deleted" }
            for (const status of ["modified", "added", "deleted"]) {
              const items = byStatus[status]
              if (items.length === 0) continue
              lines.push(`## ${statusLabels[status]} (${items.length})`)
              for (const item of items) {
                const binTag = item.binary ? " [binary]" : ""
                lines.push(`  ${item.file} (+${item.additions} -${item.deletions})${binTag}`)
              }
              lines.push("")
            }
            lines.push(`Total: ${allFiles.size} file(s) changed — +${totalAdd} -${totalDel}`)

            return {
              title: `Diff file list: ${base && head ? `${base} → ${head}` : "working tree"}`,
              output: lines.join("\n"),
            }
          } catch (err: any) {
            return {
              title: "Diff list failed",
              output: `Failed to list changed files: ${err?.message ?? err}`,
            }
          }
        },
      }),

      get_diff_file: tool({
        description:
          "Get the full git diff patch for a single file. Read-only — safe to call. " +
          "Use after get_diff_files_list to review individual files. " +
          "Modes: both base+head omitted → working tree (git diff HEAD); both provided → branch-to-branch (git diff base...head). " +
          "Binary files are detected and skipped (cannot be reviewed). " +
          "Examples: get_diff_file(file='src/components/Button.tsx'), get_diff_file(file='src/utils/date.ts', base='main', head='feature-branch').",
        args: {
          file: tool.schema
            .string()
            .describe("The file path to get the diff for (as shown in get_diff_files_list)."),
          base: tool.schema
            .string()
            .optional()
            .describe("The base git ref to compare FROM. Omit for working tree mode."),
          head: tool.schema
            .string()
            .optional()
            .describe("The head git ref to compare TO. Omit for working tree mode."),
          repo: tool.schema
            .string()
            .optional()
            .describe("Optional: path to the git repo. Defaults to the session directory."),
        },
        async execute(args, context) {
          const { file, base, head, repo } = args
          const cwd = repo || context.directory
          try {
            const diffArgs = buildDiffArgs(base, head)
            const numstatMap = await getNumstatMap(cwd, diffArgs)
            const stats = numstatMap.get(file)
            if (!stats) {
              return {
                title: "File not changed",
                output: `'${file}' is not changed in this diff.`,
              }
            }

            const statusMap = await getFileStatusMap(cwd, diffArgs)
            const status = statusMap.get(file) ?? "modified"
            const statusLabel = status === "added" ? "Added" : status === "deleted" ? "Deleted" : "Modified"

            if (stats.binary) {
              return {
                title: `Binary file: ${file}`,
                output:
                  `File: ${file}\nStatus: ${statusLabel} [binary]\n\n` +
                  `Binary files differ — cannot be reviewed as text.`,
              }
            }

            const patchResult = await $`git ${["diff", ...diffArgs.slice(1), "--", file]}`.cwd(cwd).quiet()
            const patch = patchResult.stdout.toString().trim()

            return {
              title: `Diff: ${file}`,
              output:
                `File: ${file}\nStatus: ${statusLabel} (+${stats.additions} -${stats.deletions})\n\n` +
                (patch || "(no textual changes)"),
            }
          } catch (err: any) {
            return {
              title: "Diff file failed",
              output: `Failed to get diff for '${file}': ${err?.message ?? err}`,
            }
          }
        },
      }),
    },
  }
}

export default PrepMergePlugin