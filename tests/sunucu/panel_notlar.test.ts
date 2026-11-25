// Göç 8400: panel notları (kurucu 23 Kasım). Kurucu test sırasında aldığı notları panelden oyun oyun girer; oyun-ortak
// oturumu "gönder" denince yeni notları ilgili oyun oturumuna iletir. Panel yalnız panel anahtarıyla ekler, listeler ve
// henüz gönderilmemiş notu siler; durum (gonderildi/yapildi) yalnız servis rolüyle değişir. Tablo istemciye kapalı.
import { after, test } from "node:test";
import assert from "node:assert/strict";
import { istemci, sql } from "./yardimci.ts";

after(async () => {
  await sql`delete from ortak.panel_notlar where metin like 'test-%'`;
  await sql`delete from ortak.panel_ayar`;
  await sql.end();
});

test("8400 panel notları: anahtarla ekle, listele, yeni notu sil; durum servis rolüyle; tablo kapalı", async () => {
  await sql`delete from ortak.panel_ayar`;
  await sql`insert into ortak.panel_ayar (anahtar_ozet) values (extensions.digest('test-anahtar', 'sha256'))`;
  const anon = istemci().schema("ortak");

  assert.equal((await anon.rpc("panel_not_ekle", { p_anahtar: "yanlis", p_oyun: "halka-kelime", p_metin: "test-x" })).data, null, "yanlış anahtar eklemez");
  assert.equal((await anon.rpc("panel_notlar", { p_anahtar: "yanlis" })).data, null, "yanlış anahtar okuyamaz");

  const { data: id, error } = await anon.rpc("panel_not_ekle", { p_anahtar: "test-anahtar", p_oyun: "halka-kelime", p_metin: "test-ipucu düğmesi küçük" });
  assert.ifError(error);
  assert.equal(typeof id, "number");
  const { data: id2 } = await anon.rpc("panel_not_ekle", { p_anahtar: "test-anahtar", p_oyun: "koz-hesabi", p_metin: "test-ikinci" });

  assert.ok((await anon.rpc("panel_not_ekle", { p_anahtar: "test-anahtar", p_oyun: "halka-kelime", p_metin: "   " })).error, "boş not olmaz");
  assert.ok((await anon.rpc("panel_not_ekle", { p_anahtar: "test-anahtar", p_oyun: "Halka Kelime!", p_metin: "test-y" })).error, "oyun kimliği klasör adı biçiminde");

  const liste = (await anon.rpc("panel_notlar", { p_anahtar: "test-anahtar" })).data as { id: number; oyun: string; metin: string; durum: string }[];
  const benim = liste.filter((n) => n.metin.startsWith("test-"));
  assert.equal(benim.length, 2);
  assert.equal(benim.find((n) => n.id === id)!.durum, "yeni");

  // Gönderilmiş not panelden silinemez; durumu yalnız servis rolü değiştirir.
  await sql`update ortak.panel_notlar set durum = 'gonderildi', gonderildi = now() where id = ${id2}`;
  assert.equal((await anon.rpc("panel_not_sil", { p_anahtar: "test-anahtar", p_id: id2 })).data, false, "gönderilmiş not silinmez");
  assert.equal((await anon.rpc("panel_not_sil", { p_anahtar: "yanlis", p_id: id })).data, null, "yanlış anahtar silemez");
  assert.equal((await anon.rpc("panel_not_sil", { p_anahtar: "test-anahtar", p_id: id })).data, true);
  assert.equal((await sql`select count(*)::int as n from ortak.panel_notlar where id = ${id}`)[0]!.n, 0);

  assert.ok((await anon.from("panel_notlar").select("*").limit(1)).error, "tablo istemciye kapalı");
});
