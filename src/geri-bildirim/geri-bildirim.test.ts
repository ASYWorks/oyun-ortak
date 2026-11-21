import { test } from "node:test";
import assert from "node:assert/strict";
import { bellekDepo } from "../kayit/index.ts";
import { geriBildirimBaslat, type Anket } from "./index.ts";

const anketler: Anket[] = [
  {
    id: "bes",
    kosul: { sayac: { ad: "cozum", esik: 5 } },
    sorular: [
      { id: "kural", tur: "secim", metin: "Kuralı ne zaman anladın?", secenekler: ["hemen", "birkaç denemede", "anlamadım"] },
      { id: "rahat", tur: "olcek", metin: "Halka seçmek rahat mı?", en_az: 1, en_cok: 5, serbestMetin: true },
    ],
  },
  { id: "yedi", kosul: { gun: 7 }, sorular: [{ id: "yarin", tur: "metin", metin: "Yarın yine açar mısın?" }] },
];

test("koşullar, tek gösterim, cevap ölçüme gider, yalnız kapalı testte", async () => {
  let saat = new Date("2026-11-12T10:00:00Z");
  const olaylar: { ad: string; o: unknown }[] = [];
  const depo = bellekDepo();
  const olcum = { olay: (ad: string, o?: unknown) => void olaylar.push({ ad, o }), adsizOlay: async (ad: string, o?: unknown) => void olaylar.push({ ad, o, adsiz: true }), acik: () => true };
  const g = await geriBildirimBaslat({ depo, olcum, anketler, etkin: true, simdi: () => saat });
  assert.equal(g.siradaki(), null);
  await g.say("cozum", 5);
  assert.equal(g.siradaki()?.id, "bes");
  // ölçek aralık dışı (9) atılır; serbest metin 200 karakterde kesilir
  await g.cevapla("bes", { kural: { secim: "hemen" }, rahat: { olcek: 9, metin: "x".repeat(300) } });
  assert.deepEqual(olaylar[0], {
    ad: "geri_bildirim",
    o: { anket: "bes", gun: 0, kural_secim: "hemen", rahat_metin: "x".repeat(200) },
  });
  assert.equal(g.siradaki(), null);

  saat = new Date("2026-11-19T10:00:00Z");
  const g2 = await geriBildirimBaslat({ depo, olcum, anketler, etkin: true, simdi: () => saat });
  assert.equal(g2.siradaki()?.id, "yedi"); // ilk açılış günü depoda kaldı

  const kapali = await geriBildirimBaslat({ depo: bellekDepo(), olcum, anketler, etkin: false });
  await kapali.say("cozum", 10);
  assert.equal(kapali.siradaki(), null);
});

test("kalıcı geri bildirim formu: ölçüm açıksa olay, kapalıysa adsız; metin 200'de kesilir, boş reddedilir", async () => {
  const { geriBildirimGonder } = await import("./index.ts");
  const giden: { ad: string; o: Record<string, unknown>; adsiz?: boolean }[] = [];
  let acik = true;
  const olcum = {
    hemenOlay: async (ad: string, o?: unknown) => void giden.push({ ad, o: o as Record<string, unknown> }),
    adsizOlay: async (ad: string, o?: unknown) => void giden.push({ ad, o: o as Record<string, unknown>, adsiz: true }),
    acik: () => acik,
  };
  await geriBildirimGonder(olcum, "oneri", "a".repeat(300));
  assert.equal((giden[0]!.o.metin as string).length, 200);
  assert.equal(giden[0]!.adsiz, undefined);
  acik = false;
  await geriBildirimGonder(olcum, "hata", "çöktü", { ekran: "ayarlar" });
  assert.equal(giden[1]!.adsiz, true);
  await assert.rejects(geriBildirimGonder(olcum, "diger", "   "), /metin_bos/);
});
