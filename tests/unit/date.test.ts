import { assertEquals } from "assert"
import { formatDate } from "../src/utils/date"

Deno.test("formatDate", () => {
  const result = formatDate(new Date("2026-01-01"))
  assertEquals(result, "2026-01-01T00:00:00.000Z")
})