import { test } from "node:test";
import assert from "node:assert/strict";
import { hesapBaslat } from "./index.ts";
import { siralamaBaslat } from "../siralama/index.ts";
import { bellekDepo } from "../kayit/index.ts";

test("OL-9: captcha sağlayıcısı verilirse anonim giriş ve e-posta koduna jeton eklenir; kimlik jetonuyla girişe eklenmez (19 Kasım); verilmezse eklenmez", async () => {
  const giden: Record<string, unknown> = {};
  let n = 0;
  const sb = {
    auth: {
      getSession: async () => ({ data: { session: null } }),
      signInAnonymously: async (o?: { options?: unknown }) => ((giden.anonim = o?.options), { data: { user: { id: "u" } }, error: null }),
      signInWithOtp: async (o: { options: unknown }) => ((giden.otp = o.options), { error: null }),
      signInWithIdToken: async (o: { options?: unknown }) => ((giden.id = o.options), { error: null }),
    },
    functions: { invoke: async () => ({ data: {}, error: null }) },
  };
  const captcha = async () => `j${++n}`;
  const h = hesapBaslat({ supabase: sb as never, oyunId: "o", depo: bellekDepo(), captcha });
  await h.anonimGir();
  await h.epostaKoduGonder("a@b.c", "tr");
  await h.idTokenIleGir("google", "t");
  assert.deepEqual(giden.anonim, { captchaToken: "j1" });
  assert.equal((giden.otp as { captchaToken?: string }).captchaToken, "j2");
  assert.equal(giden.id, undefined, "kimlik jetonuyla giriş captcha beklemez (Supabase denetlemiyor)");
  await siralamaBaslat({ supabase: sb as never, oyunId: "o", depo: bellekDepo(), captcha }).gonder({ x: 1 });
  assert.deepEqual(giden.anonim, { captchaToken: "j3" });

  await hesapBaslat({ supabase: sb as never, oyunId: "o", depo: bellekDepo() }).epostaKoduGonder("a@b.c");
  assert.equal((giden.otp as { captchaToken?: string }).captchaToken, undefined);
});
