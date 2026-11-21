import { test } from "node:test";
import assert from "node:assert/strict";
import { bellekDepo, hesapDegistir, sahipDenetle, sahipOku } from "./index.ts";

const anahtarlar = ["o:seviye", "o:defter"];
const ayar = (d: ReturnType<typeof bellekDepo>) => ({ depo: d, oyun: "o", anahtarlar });

test("kural öncesi kurulum: sahip yazılır, kayıtlar kalır", async () => {
  const d = bellekDepo({ "o:seviye": "A1" });
  assert.equal(await sahipDenetle({ ...ayar(d), kimlik: "A" }), false);
  assert.equal(d.veri.get("o:seviye"), "A1");
  assert.equal(await sahipOku(d, "o"), "A");
});

test("A çıkar, B girer: A'nınki yedeğe, B boş başlar; A dönünce her şey geri gelir", async () => {
  const d = bellekDepo({ "o:sahip": "A", "o:seviye": "A1", "o:seviye:yedek": "A0", "o:defter": "Ad", "baska": "x" });
  await hesapDegistir({ ...ayar(d), eski: "A", yeni: "" }); // çıkış: misafir
  assert.equal(d.veri.get("o:seviye"), undefined);
  assert.equal(d.veri.get("o:seviye:yedek"), undefined);
  assert.equal(d.veri.get("baska"), "x");
  assert.equal(await sahipDenetle({ ...ayar(d), kimlik: "B" }), true); // misafir boş, B girer
  d.veri.set("o:seviye", "B1");
  assert.equal(await sahipDenetle({ ...ayar(d), kimlik: "A" }), true);
  assert.equal(d.veri.get("o:seviye"), "A1");
  assert.equal(d.veri.get("o:seviye:yedek"), "A0");
  assert.equal(d.veri.get("o:defter"), "Ad");
  assert.equal(JSON.parse(d.veri.get("o:hesap:B")!)["o:seviye"], "B1");
  assert.equal(d.veri.get("o:hesap:A"), undefined);
});

test("misafir ilerlemesi giren hesaba katılır; çakışmada birlestir karar verir", async () => {
  const d = bellekDepo({ "o:sahip": "", "o:seviye": "misafir", "o:hesap:A": JSON.stringify({ "o:seviye": "A1", "o:defter": "Ad" }) });
  await sahipDenetle({ ...ayar(d), kimlik: "A", birlestir: (c, y) => `${c}+${y}` });
  assert.equal(d.veri.get("o:seviye"), "misafir+A1");
  assert.equal(d.veri.get("o:defter"), "Ad");
});

test("hesap silme: yedek tutulmaz", async () => {
  const d = bellekDepo({ "o:sahip": "A", "o:seviye": "A1", "o:hesap:A": "{}" });
  await hesapDegistir({ ...ayar(d), eski: "A", yeni: "", yedekle: false });
  assert.equal(d.veri.get("o:seviye"), undefined);
  assert.equal(d.veri.get("o:hesap:A"), undefined);
});

test("yarıda kalan geri yükleme açılışta tamamlanır; yedeğe yazım eski yedekle birleşir", async () => {
  const d = bellekDepo({ "o:sahip": "A", "o:hesap:A": JSON.stringify({ "o:defter": "Ad" }), "o:seviye": "A1" });
  assert.equal(await sahipDenetle({ ...ayar(d), kimlik: "A" }), true);
  assert.equal(d.veri.get("o:defter"), "Ad");
  d.veri.set("o:hesap:A", JSON.stringify({ "o:defter": "eski" }));
  d.veri.delete("o:defter");
  await hesapDegistir({ ...ayar(d), eski: "A", yeni: "" });
  assert.deepEqual(JSON.parse(d.veri.get("o:hesap:A")!), { "o:defter": "eski", "o:seviye": "A1" });
});
