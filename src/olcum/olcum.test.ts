import { test } from "node:test";
import assert from "node:assert/strict";
import { bellekDepo } from "../kayit/index.ts";
import { olcumBaslat, temizOzellikler, type OlcumAyari } from "./index.ts";

const sahteFetch = (durum: number | "ag-yok") => {
  const istekler: { url: string; govde: { api_key: string; batch: { event: string; properties: Record<string, unknown> }[] } }[] = [];
  const f = (async (url: string, init: RequestInit) => {
    if (durum === "ag-yok") throw new TypeError("Failed to fetch");
    istekler.push({ url, govde: JSON.parse(String(init.body)) });
    return new Response(null, { status: durum });
  }) as unknown as typeof fetch;
  return { f, istekler };
};

const ayar = (ek: Partial<OlcumAyari>): OlcumAyari => ({
  oyunId: "halka",
  surum: "1.0.0",
  platform: "web",
  anahtar: "phc_test",
  cihaz: "c1",
  depo: bellekDepo(),
  aralik: 0,
  uzantiOlaylar: ["league_joined"],
  ...ek,
});

test("izinli olaylar ortak özelliklerle gider; izinsizler düşer", async () => {
  const { f, istekler } = sahteFetch(200);
  const o = await olcumBaslat(ayar({ fetch: f, cihaz: "t-grup1-x" }));
  o.olay("seviye_bitir", { sure: 12, zorluk: "kolay" });
  o.olay("league_joined");
  o.olay("bilinmeyen");
  await o.gonder();
  assert.equal(istekler.length, 1);
  assert.equal(istekler[0]!.url, "https://eu.i.posthog.com/batch/");
  const b = istekler[0]!.govde.batch;
  assert.deepEqual(b.map((x) => x.event), ["seviye_bitir", "league_joined"]);
  assert.deepEqual(b[0]!.properties, {
    sure: 12, zorluk: "kolay", distinct_id: "t-grup1-x", oyun_id: "halka", surum: "1.0.0", platform: "web", test: "grup1",
  });
  assert.equal(o.kuyruk.length, 0);
});

test("ağ yokken kuyruk depoda kalır, yeni açılışta gönderilir", async () => {
  const depo = bellekDepo();
  const yok = sahteFetch("ag-yok");
  const o = await olcumBaslat(ayar({ fetch: yok.f, depo }));
  o.olay("oturum_basla");
  await o.gonder();
  assert.equal(o.kuyruk.length, 1);
  await new Promise((r) => setTimeout(r, 0));
  const var_ = sahteFetch(200);
  const o2 = await olcumBaslat(ayar({ fetch: var_.f, depo }));
  await o2.gonder();
  assert.equal(var_.istekler[0]!.govde.batch.length, 1);
});

test("kalıcı 4xx: ölçüm sessizce durur; 429 ve 5xx yeniden denenir", async () => {
  for (const [durum, durmali] of [[401, true], [429, false], [503, false]] as const) {
    const { f } = sahteFetch(durum);
    const o = await olcumBaslat(ayar({ fetch: f }));
    o.olay("oturum_basla");
    await o.gonder();
    assert.equal(o.durdu, durmali, String(durum));
    o.olay("oturum_basla");
    assert.equal(o.kuyruk.length, durmali ? 0 : 2, String(durum));
  }
});

test("anahtar yoksa ölçüm kapalı ve hiç istek atmaz", async () => {
  const { f, istekler } = sahteFetch(200);
  const o = await olcumBaslat(ayar({ fetch: f, anahtar: "" }));
  o.olay("oturum_basla");
  await o.gonder();
  assert.equal(istekler.length, 0);
});

test("kuyruk 500 olayda kesilir, en eskiler düşer", async () => {
  const { f } = sahteFetch("ag-yok");
  const o = await olcumBaslat(ayar({ fetch: f, topluSinir: 10_000 }));
  for (let i = 0; i < 510; i++) o.olay("seviye_basla", { n: i });
  assert.equal(o.kuyruk.length, 500);
  assert.equal(o.kuyruk[0]!.properties.n, 10);
});

test("topluSinir dolunca kendiliğinden gönderir; aynı anda tek istek", async () => {
  const { f, istekler } = sahteFetch(200);
  const o = await olcumBaslat(ayar({ fetch: f, topluSinir: 2 }));
  o.olay("seviye_basla");
  o.olay("seviye_bitir");
  o.olay("seviye_basla");
  await o.gonder();
  await o.gonder();
  assert.equal(istekler.reduce((n, i) => n + i.govde.batch.length, 0), 3);
});

test("özellik temizliği", () => {
  assert.deepEqual(
    temizOzellikler({ a: "x".repeat(300), B: 1, n: Number.NaN, ok: true, z: null, d: {} as never }),
    { a: "x".repeat(200), ok: true, z: null },
  );
});

test("ölçüm kapatma: kapalıyken olay gitmez, kuyruk silinir, tercih kalır; adsız olay cihaz kimliksiz gider", async () => {
  const { f, istekler } = sahteFetch(200);
  const depo = bellekDepo();
  const o = await olcumBaslat(ayar({ fetch: f, depo }));
  o.olay("oturum_basla");
  await o.ayarla(false);
  assert.equal(o.acik(), false);
  assert.equal(o.kuyruk.length, 0);
  o.olay("oturum_basla");
  await o.gonder();
  assert.equal(istekler.length, 0);
  // tercih yeniden açılışta korunur
  const o2 = await olcumBaslat(ayar({ fetch: f, depo }));
  assert.equal(o2.acik(), false);
  await o2.adsizOlay("geri_bildirim", { tur: "hata", metin: "x" });
  assert.equal(istekler.length, 1);
  const p = istekler[0]!.govde.batch[0]!.properties;
  assert.notEqual(p.distinct_id, "c1");
  assert.equal(p.adsiz, true);
});

test("hemenOlay: kuyruksuz gider, ağ yoksa 'gonderilemedi'; ölçüm kapalıyken gitmez", async () => {
  const ok = sahteFetch(200);
  const o = await olcumBaslat(ayar({ fetch: ok.f }));
  await o.hemenOlay("geri_bildirim", { tur: "hata" });
  assert.equal(ok.istekler.length, 1);
  assert.equal(ok.istekler[0]!.govde.batch[0]!.properties.distinct_id, "c1");
  assert.equal(o.kuyruk.length, 0);
  const yok = sahteFetch("ag-yok");
  const o2 = await olcumBaslat(ayar({ fetch: yok.f }));
  await assert.rejects(o2.hemenOlay("geri_bildirim", {}), /gonderilemedi/);
  await assert.rejects(o2.adsizOlay("geri_bildirim", {}), /gonderilemedi/);
  const ret = sahteFetch(500);
  await assert.rejects((await olcumBaslat(ayar({ fetch: ret.f }))).hemenOlay("geri_bildirim", {}), /gonderilemedi/);
});

test("hata: $exception biçimi, yığın çözülür, aynı ileti bir kez, oturumda en çok 20", async () => {
  const { f, istekler } = sahteFetch(200);
  const o = await olcumBaslat(ayar({ fetch: f }));
  const e = new TypeError("x is undefined");
  e.stack = "TypeError: x is undefined\n    at coz (https://halkakelime.com/assets/main-ab.js:1:2345)\n    at https://halkakelime.com/assets/main-ab.js:3:10";
  o.hata(e, { ekran: "oyun" });
  o.hata(e);
  await o.gonder();
  const p = istekler[0]!.govde.batch[0]!;
  assert.equal(p.event, "$exception");
  assert.equal(p.properties.ekran, "oyun");
  const [x] = p.properties.$exception_list as { type: string; value: string; mechanism: { handled: boolean }; stacktrace: { frames: { function: string; lineno: number; colno: number }[] } }[];
  assert.equal(x!.type, "TypeError");
  assert.equal(x!.mechanism.handled, false);
  assert.deepEqual(x!.stacktrace.frames.map((c) => [c.function, c.lineno, c.colno]), [["?", 3, 10], ["coz", 1, 2345]]);
  assert.equal(istekler[0]!.govde.batch.length, 1);
  for (let i = 0; i < 30; i++) o.hata(`h${i}`);
  assert.equal(o.kuyruk.length, 19);
  await o.ayarla(false);
  o.hata(new Error("kapali"));
  assert.equal(o.kuyruk.length, 0);
});

test("yiginCoz: Firefox/Safari biçimi", async () => {
  const { yiginCoz } = await import("./index.ts");
  assert.deepEqual(yiginCoz("coz@https://a.com/m.js:4:5\n@https://a.com/m.js:9:1").map((c) => [c.function, c.lineno]), [["?", 9], ["coz", 4]]);
});

test("hata: ileti ve çerçevelerden e-posta, jeton, adres sorgusu ayıklanır", async () => {
  const { ayikla, yiginCoz } = await import("./index.ts");
  assert.equal(
    ayikla("ali@x.com icin https://a.com/cb?t=kod#access_token=eyJhbGciOiJIUzI1NiJ9.abcdefghijklmnop hata"),
    "<eposta> icin https://a.com/cb hata",
  );
  assert.equal(ayikla("jeton eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.sig_abcdefghij bitti"), "jeton <jeton> bitti");
  assert.equal(yiginCoz("at f (https://a.com/m.js?v=1#x:1:2)")[0]?.filename, "https://a.com/m.js");
});
