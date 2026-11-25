// Göç 8480 (Kayan Yük): oyun satırı; sıralama ve lig yok; önizlemede testçi olmayana onizleme bayrağı.
import { after, test } from "node:test";
import assert from "node:assert/strict";
import { istemci, sql } from "./yardimci.ts";

after(async () => { await sql.end(); });

test("8480 kayan: satır var, yayin onizleme, lig yok; misafire oyun_bayraklari onizleme döner", async () => {
  const [o] = await sql`select ad, ayarlar from ortak.oyunlar where id = 'kayan'`;
  assert.ok(o, "satır var");
  assert.equal(o!.ad, "Kayan Yük");
  assert.equal(o!.ayarlar.yayin, "onizleme");
  assert.equal(o!.ayarlar.lig, undefined);
  const { data, error } = await istemci().schema("ortak").rpc("oyun_bayraklari", { p_oyun: "kayan" });
  assert.equal(error, null);
  assert.equal(data.onizleme, true);
});
