import { test, mock } from "node:test";
import assert from "node:assert/strict";
import { siralamaBaslat } from "./index.ts";
import { bellekDepo } from "../kayit/index.ts";

test("nabizBaslat: dokundu() son aralıkta başka istek gittiyse nabzı atlar; durdurunca durdur nabzı gider", () => {
  mock.timers.enable({ apis: ["setInterval", "Date"] });
  try {
    const giden: boolean[] = [];
    const sb = { schema: () => ({ rpc: async (_: string, a: { p_durdur: boolean }) => { giden.push(a.p_durdur); return { data: 0, error: null }; } }) };
    const s = siralamaBaslat({ supabase: sb as never, oyunId: "deneme", depo: bellekDepo() });
    const dur = s.nabizBaslat("k", 20_000);
    assert.deepEqual(giden, [false], "hemen bir nabız");
    mock.timers.tick(15_000);
    dur.dokundu(); // kontrol gitti
    mock.timers.tick(5_000); // 20. sn: son dokunuş 5 sn önce → atla
    assert.deepEqual(giden, [false]);
    mock.timers.tick(20_000); // 40. sn: dokunuş 25 sn önce → gönder
    assert.deepEqual(giden, [false, false]);
    dur();
    assert.deepEqual(giden, [false, false, true], "durdur nabzı");
  } finally {
    mock.timers.reset();
  }
});
