import { test } from "node:test";
import assert from "node:assert/strict";
import { siralamaBaslat } from "./index.ts";
import { bellekDepo } from "../kayit/index.ts";

// Sahte Supabase: oturumdaki kullanıcı değiştirilebilir, ağ açılıp kapanabilir; giden gönderimler kaydedilir.
function sahte() {
  const s = { kullanici: "A" as string | null, ag: true, giden: [] as { kim: string | null; govde: unknown }[] };
  const sb = {
    auth: {
      getSession: async () => ({ data: { session: s.kullanici ? { user: { id: s.kullanici } } : null } }),
      signInAnonymously: async () => ({ error: null }),
    },
    functions: {
      invoke: async (_fn: string, o: { body: unknown }) => {
        if (!s.ag) return { data: null, error: { context: undefined } };
        s.giden.push({ kim: s.kullanici, govde: o.body });
        return { data: { ok: true }, error: null };
      },
    },
  };
  return { s, sb };
}

test("O15: A'nın kuyruktaki gönderimi B'nin oturumuyla gitmez, A dönünce gider", async () => {
  const { s, sb } = sahte();
  const depo = bellekDepo();
  const sir = siralamaBaslat({ supabase: sb as never, oyunId: "o", depo });
  s.ag = false;
  assert.equal((await sir.gonder({ x: 1 })).bekliyor, true);
  s.ag = true;
  s.kullanici = "B";
  await sir.bosalt();
  assert.equal(s.giden.length, 0);
  assert.equal(await sir.bekleyenSayisi(), 1);
  await sir.gonder({ x: 2 });
  assert.deepEqual(s.giden.map((g) => g.kim), ["B"]);
  s.kullanici = "A";
  await sir.bosalt();
  assert.deepEqual(s.giden.map((g) => g.kim), ["B", "A"]);
  assert.equal(await sir.bekleyenSayisi(), 0);
});

test("GC-1: kuyruktaki önceki gönderimin sonucu da işlenir; süren boşaltmaya denk gelen gönderim de gider", async () => {
  const { s, sb } = sahte();
  const gelen: unknown[] = [];
  const sir = siralamaBaslat({ supabase: sb as never, oyunId: "o", depo: bellekDepo(), sonuc: (r) => gelen.push((r.veri as { ok?: boolean })?.ok ?? r.durum) });
  s.ag = false;
  await sir.gonder({ x: 1 });
  s.ag = true;
  const r = await sir.gonder({ x: 2 });
  assert.equal(r.bekliyor, false);
  assert.deepEqual(gelen, [0, true, true]); // ağsız deneme, sonra iki gönderim
  // süren boşaltma sırasında gelen gönderim
  const bos = sir.bosalt();
  const r2 = await sir.gonder({ x: 3 });
  await bos;
  assert.equal(r2.bekliyor, false);
  assert.equal(await sir.bekleyenSayisi(), 0);
});
