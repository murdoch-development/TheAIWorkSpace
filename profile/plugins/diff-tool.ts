import { type Plugin, tool } from "@opencode-ai/plugin"
import { $ } from "bun"
import { parsePatch } from "diff"

type Row = { left: string; right: string; leftMark: string; rightMark: string }

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

function buildRows(lines: string[]): Row[] {
  const rows: Row[] = []
  let i = 0
  while (i < lines.length) {
    const line = lines[i]
    if (line.startsWith("\\")) { i++; continue }
    if (line.startsWith(" ")) {
      const text = line.slice(1)
      rows.push({ left: text, right: text, leftMark: " ", rightMark: " " })
      i++
      continue
    }
    if (line.startsWith("-") && !line.startsWith("--")) {
      const dels: string[] = []
      while (i < lines.length && lines[i].startsWith("-") && !lines[i].startsWith("--")) {
        dels.push(lines[i].slice(1)); i++
      }
      const adds: string[] = []
      while (i < lines.length && lines[i].startsWith("+")) {
        adds.push(lines[i].slice(1)); i++
      }
      const max = Math.max(dels.length, adds.length)
      for (let j = 0; j < max; j++) {
        rows.push({
          left: dels[j] ?? "",
          right: adds[j] ?? "",
          leftMark: dels[j] ? "-" : " ",
          rightMark: adds[j] ? "+" : " ",
        })
      }
      continue
    }
    if (line.startsWith("+")) {
      const adds: string[] = []
      while (i < lines.length && lines[i].startsWith("+")) {
        adds.push(lines[i].slice(1)); i++
      }
      for (const al of adds) rows.push({ left: "", right: al, leftMark: " ", rightMark: "+" })
      continue
    }
    i++
  }
  return rows
}

function renderSideBySide(patch: string, width: number): string {
  const GREEN = "\x1b[32m", RED = "\x1b[31m", CYAN = "\x1b[36m", BOLD = "\x1b[1m", DIM = "\x1b[2m", RESET = "\x1b[0m"
  const colWidth = Math.max(20, Math.floor((width - 4) / 2))
  const parsed = parsePatch(normalizePatch(patch))[0]
  if (!parsed || !parsed.hunks) return patch

  const m = patch.match(/^diff --git a\/(\S+) b\/(\S+)/)
  const file = m ? m[2] : ""
  let out = `${CYAN}${BOLD}── ${file} ──${RESET}\n`

  let totalAdd = 0, totalDel = 0
  for (const h of parsed.hunks) {
    out += `${DIM}  @@ ${h.oldStart},${h.oldLines} → ${h.newStart},${h.newLines} @@${RESET}\n`
    const rows = buildRows(h.lines)
    for (const r of rows) {
      if (r.leftMark === "-") totalDel++
      if (r.rightMark === "+") totalAdd++
      const left = r.leftMark === "-" ? `${RED}${r.left}${RESET}` : r.left
      const right = r.rightMark === "+" ? `${GREEN}${r.right}${RESET}` : r.right
      const lm = r.leftMark === "-" ? `${RED}-${RESET}` : `${DIM} ${RESET}`
      const rm = r.rightMark === "+" ? `${GREEN}+${RESET}` : `${DIM} ${RESET}`
      const visibleLeft = stripAnsi(r.left)
      const padL = visibleLeft.length >= colWidth ? r.left : r.left + " ".repeat(colWidth - visibleLeft.length)
      const leftCell = r.leftMark === "-" ? `${RED}${padL.slice(0, colWidth)}${RESET}` : padL.slice(0, colWidth)
      const rightCell = r.rightMark === "+" ? `${GREEN}${r.right.slice(0, colWidth)}${RESET}` : r.right.slice(0, colWidth)
      out += `${lm} ${leftCell} ${DIM}│${RESET} ${rm} ${rightCell}\n`
    }
    out += "\n"
  }
  out += `${DIM}  ${GREEN}+${totalAdd}${RESET} ${RED}-${totalDel}${RESET}${DIM} in ${file}${RESET}\n`
  return out
}

function stripAnsi(str: string): string {
  return str.replace(/\x1b\[[0-9;]*m/g, "")
}

const DiffToolPlugin: Plugin = async (ctx) => {
  return {
    tool: {
      diff: tool({
        description: "Show a git diff between a task branch and the merge target branch. Returns a readable side-by-side diff with per-file breakdown. Use this to review code changes before merging.",
        args: {
          branch: tool.schema.string().describe("The task branch to diff (e.g. 'task-1')"),
          target: tool.schema.string().describe("The merge target branch to diff against (e.g. 'main')"),
          file: tool.schema.string().optional().describe("Optional: show diff for a single file only. If omitted, shows all changed files."),
          repo: tool.schema.string().optional().describe("Optional: path to the git repo. Defaults to the session directory."),
        },
        async execute(args, context) {
          const { branch, target, file, repo } = args
          const cwd = repo || context.directory

          let files: string[]
          if (file) {
            files = [file]
          } else {
            const result = await $`git diff --name-only ${target}...${branch}`.cwd(cwd).quiet()
            files = result.stdout.toString().trim().split("\n").filter((f: string) => f.length > 0)
          }

          if (files.length === 0) {
            return {
              title: "No changes",
              output: `No files changed between ${target} and ${branch}.`,
            }
          }

          const width = (process.stdout && process.stdout.columns ? process.stdout.columns : 120) || 120
          let output = ""
          let totalAdd = 0, totalDel = 0

          for (const f of files) {
            const diffResult = await $`git diff ${target}...${branch} -- ${f}`.cwd(cwd).quiet()
            const patch = diffResult.stdout.toString()
            if (!patch.trim()) continue
            output += renderSideBySide(patch, width) + "\n"
            const m = patch.match(/^\+[^+]/gm)
            const d = patch.match(/^-[^-]/gm)
            totalAdd += m ? m.length : 0
            totalDel += d ? d.length : 0
          }

          if (!output.trim()) {
            return {
              title: "No changes",
              output: `No files changed between ${target} and ${branch}.`,
            }
          }

          const BOLD = "\x1b[1m", GREEN = "\x1b[32m", RED = "\x1b[31m", RESET = "\x1b[0m", CYAN = "\x1b[36m"
          const header = `${BOLD}========================================${RESET}\n` +
            `${BOLD}  ${CYAN}${target}${RESET}${BOLD}  (left)  →  ${CYAN}${branch}${RESET}${BOLD}  (right)${RESET}\n` +
            `${BOLD}  ${files.length} file(s) changed  ${GREEN}+${totalAdd}${RESET} ${RED}-${totalDel}${RESET}\n` +
            `${BOLD}========================================${RESET}\n\n`

          return {
            title: `Diff: ${branch} → ${target}`,
            output: header + output.trim(),
          }
        },
      }),
    },
  }
}

export default DiffToolPlugin