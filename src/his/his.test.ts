// his modülü: hareket azaltmada hareketsiz karşılık (A35), ses ve titreşim aynı çağrıda (A32), yalnız transform (A33).
import { test } from "node:test";
import assert from "node:assert/strict";
import { esne, titre, dalga, hisVer, hisAyarla, hareketAzaltildi } from "./index.ts";

function oge() {
  const siniflar = new Set<string>(), kareler: Keyframe[][] = [];
  return {
    siniflar, kareler,
    classList: { add: (s: string) => siniflar.add(s), remove: (s: string) => siniflar.delete(s) },
    animate(k: Keyframe[]) { kareler.push(k); return { finished: Promise.resolve() }; },
  } as unknown as Element & { siniflar: Set<string>; kareler: Keyframe[][] };
}

test("hareket açık: esne ve titre yalnız transform kareleri oynatır", async () => {
  hisAyarla({ hareketiAzalt: false, sure: { orta: 1, uzun: 1 } });
  const el = oge();
  await esne(el); await titre(el);
  assert.equal(el.kareler.length, 2);
  for (const k of el.kareler.flat()) assert.deepEqual(Object.keys(k), ["transform"]);
});

test("hareket azaltma: animasyon yok, kısa sınıf eklenir ve kaldırılır (bilgi kaybolmaz)", async () => {
  hisAyarla({ hareketiAzalt: true, sure: { orta: 1, uzun: 1 } });
  assert.equal(hareketAzaltildi(), true);
  const el = oge();
  const p = titre(el);
  assert.ok(el.siniflar.has("his-hata"));
  await p;
  assert.equal(el.siniflar.has("his-hata"), false);
  assert.equal(el.kareler.length, 0);
  const a = oge(), b = oge();
  await dalga([a, b]);
  assert.equal(a.kareler.length + b.kareler.length, 0);
  hisAyarla({ hareketiAzalt: null });
});

test("hisVer: ses aynı çağrıda çalar; titreşim yoksa hata vermez", async () => {
  hisAyarla({ hareketiAzalt: false, sure: { orta: 1, uzun: 1 } });
  let caldi = 0;
  const el = oge();
  await hisVer({ el, tur: "dogru", ses: () => caldi++, titresim: 20 });
  assert.equal(caldi, 1);
  assert.equal(el.kareler.length, 1);
  hisAyarla({ hareketiAzalt: null });
});
