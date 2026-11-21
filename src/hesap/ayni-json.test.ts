import { test } from "node:test";
import assert from "node:assert/strict";
import { ayniJson } from "./index.ts";

test("GC-2: ayniJson jsonb gibi karşılaştırır", () => {
  assert.ok(ayniJson({ a: 1, b: { c: [1, { d: 2, e: 3 }] } }, { b: { c: [1, { e: 3, d: 2 }] }, a: 1 }));
  assert.ok(ayniJson({ a: 1, b: undefined }, { a: 1 }));
  assert.ok(!ayniJson({ a: [1, 2] }, { a: [2, 1] }));
  assert.ok(!ayniJson({ a: 1 }, { a: "1" }));
});
