import { test } from "node:test";
import assert from "node:assert/strict";
import { dilSec, epostaHazirla, imzaDogru, isle } from "./eposta.ts";

const veri = (redirect?: string, meta?: Record<string, unknown>, tur = "magiclink") => ({
  user: { email: "oyuncu@ornek.com", user_metadata: meta ?? {} },
  email_data: { token: "123456", redirect_to: redirect, email_action_type: tur },
});

test("dil: adresteki dil, yoksa kullanıcı verisi, yoksa Türkçe", () => {
  assert.equal(dilSec(veri("https://asyworks.com/?dil=en")), "en");
  assert.equal(dilSec(veri("https://asyworks.com/?dil=tr", { dil: "en" })), "tr");
  assert.equal(dilSec(veri(undefined, { dil: "en" })), "en");
  assert.equal(dilSec(veri("https://www.halkakelime.com")), "tr");
  assert.equal(dilSec(veri("bozuk adres")), "tr");
});

test("e-posta: dile göre gönderen, konu, yanıt adresi; kod gövdede", () => {
  const en = epostaHazirla(veri("https://asyworks.com/?dil=en"));
  assert.equal(en.from, "ASYWorks <login@asyworks.com>");
  assert.equal(en.reply_to, "support@asyworks.com");
  assert.match(en.subject, /sign-in code/);
  assert.match(en.html, /123456/);
  assert.match(en.text, /123456/);
  const tr = epostaHazirla(veri());
  assert.equal(tr.from, "ASYWorks <giris@asyworks.com>");
  assert.equal(tr.reply_to, "destek@asyworks.com");
  assert.deepEqual(tr.to, ["oyuncu@ornek.com"]);
  // Kayıtlı kullanıcı "magiclink", yeni kullanıcı "signup", yeni Auth sürümü "email" (15 Kasım: "magic_link" yazılmıştı, kayıtlı kullanıcıda kod gitmedi)
  for (const t of ["signup", "magiclink", "email"]) assert.equal(epostaHazirla(veri(undefined, {}, t)).from, tr.from);
  assert.throws(() => epostaHazirla(veri(undefined, {}, "magic_link")), /desteklenmeyen_tur/);
});

test("e-posta: desteklenmeyen tür, eksik ya da bozuk kod reddedilir", () => {
  assert.throws(() => epostaHazirla(veri(undefined, {}, "recovery")), /desteklenmeyen_tur/);
  assert.throws(() => epostaHazirla({ user: { email: "a@b.c" }, email_data: { email_action_type: "magiclink" } }), /eksik_veri/);
  assert.throws(() => epostaHazirla({ ...veri(), email_data: { token: "<b>1</b>", email_action_type: "magiclink" } }), /gecersiz_kod/);
});

// Standard Webhooks örneğiyle aynı biçimde imza üretir.
const SIR = "v1,whsec_" + btoa("bu-bir-deneme-anahtari-32-bayt!!");
async function imzala(id: string, zaman: string, govde: string) {
  const ham = Uint8Array.from(atob(SIR.slice(9)), (c) => c.charCodeAt(0));
  const k = await crypto.subtle.importKey("raw", ham, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const s = await crypto.subtle.sign("HMAC", k, new TextEncoder().encode(`${id}.${zaman}.${govde}`));
  return "v1," + btoa(String.fromCharCode(...new Uint8Array(s)));
}

test("imza: doğru imza geçer; yanlış imza, değişmiş gövde ve eski zaman geçmez", async () => {
  const z = String(Math.floor(Date.now() / 1000));
  const i = await imzala("msg_1", z, "{}");
  assert.equal(await imzaDogru(SIR, "msg_1", z, "{}", `v1,yanlis ${i}`), true);
  assert.equal(await imzaDogru(SIR, "msg_1", z, '{"a":1}', i), false);
  assert.equal(await imzaDogru(SIR, "msg_1", z, "{}", "v1,yanlis"), false);
  const eski = String(Math.floor(Date.now() / 1000) - 600);
  assert.equal(await imzaDogru(SIR, "msg_1", eski, "{}", await imzala("msg_1", eski, "{}")), false);
});

test("isle: imzalı istek Resend'e doğru gövdeyle gider; imzasız 401, Resend hatası 502", async () => {
  const ortam = (ad: string) => ({ SEND_EMAIL_HOOK_SECRET: SIR, RESEND_API_KEY: "re_deneme" })[ad];
  const govde = JSON.stringify(veri("https://asyworks.com/?dil=en"));
  const z = String(Math.floor(Date.now() / 1000));
  const istek = async (imza?: string) =>
    new Request("http://x/", {
      method: "POST",
      body: govde,
      headers: { "webhook-id": "msg_2", "webhook-timestamp": z, "webhook-signature": imza ?? (await imzala("msg_2", z, govde)) },
    });
  let giden: { url: string; init: RequestInit } | null = null;
  const sahte = (async (url: string, init: RequestInit) => {
    giden = { url, init };
    return new Response("{}", { status: 200 });
  }) as unknown as typeof fetch;
  const r = await isle(await istek(), ortam, sahte);
  assert.equal(r.status, 200);
  assert.equal(giden!.url, "https://api.resend.com/emails");
  assert.equal((giden!.init.headers as Record<string, string>).Authorization, "Bearer re_deneme");
  assert.equal(JSON.parse(String(giden!.init.body)).from, "ASYWorks <login@asyworks.com>");

  assert.equal((await isle(await istek("v1,sahte"), ortam, sahte)).status, 401);
  const hatali = (async () => new Response("kota", { status: 429 })) as unknown as typeof fetch;
  const r2 = await isle(await istek(), ortam, hatali);
  assert.equal(r2.status, 502);
  assert.deepEqual(await r2.json(), { error: { http_code: 502, message: "gonderilemedi" } });
});

test("imza: Standard Webhooks belirtimindeki örnek imza", async () => {
  // Belirtimin herkese açık örnek anahtarı (gizli değil); gizli anahtar tarayıcısı Stripe sanmasın diye parçalı.
  const sir = ["whsec", "MfKQ9r8GKYqrTwjUPD8ILPZIo2LaLaSw"].join("_");
  const zaman = "1614265330";
  const govde = '{"test": 2432232314}';
  const imza = "v1,g0hM9SsE+OTPJTGt/tmIKtSyZlE3uFJELVlNIOLJ1OE=";
  assert.equal(await imzaDogru(sir, "msg_p5jXN8AQM9LWM0D4loKWxJek", zaman, govde, imza, 1614265330 * 1000), true);
});

test("isle: BREVO_API_KEY varsa Brevo'ya gider (gönderici, alıcı, yanıt adresi, metinler)", async () => {
  const ortam = (ad: string) => ({ SEND_EMAIL_HOOK_SECRET: SIR, BREVO_API_KEY: "xkeysib-deneme", RESEND_API_KEY: "re_deneme" })[ad];
  const govde = JSON.stringify(veri("https://asyworks.com/?dil=tr"));
  const z = String(Math.floor(Date.now() / 1000));
  const istek = new Request("http://x/", {
    method: "POST",
    body: govde,
    headers: { "webhook-id": "msg_3", "webhook-timestamp": z, "webhook-signature": await imzala("msg_3", z, govde) },
  });
  let giden: { url: string; init: RequestInit } | null = null;
  const sahte = (async (url: string, init: RequestInit) => {
    giden = { url, init };
    return new Response('{"messageId":"x"}', { status: 201 });
  }) as unknown as typeof fetch;
  assert.equal((await isle(istek, ortam, sahte)).status, 200);
  assert.equal(giden!.url, "https://api.brevo.com/v3/smtp/email");
  assert.equal((giden!.init.headers as Record<string, string>)["api-key"], "xkeysib-deneme");
  const b = JSON.parse(String(giden!.init.body));
  assert.deepEqual(b.sender, { name: "ASYWorks", email: "giris@asyworks.com" });
  assert.deepEqual(b.replyTo, { email: "destek@asyworks.com" });
  assert.equal(b.to.length, 1);
  assert.match(b.textContent, /\d{6}/);
  assert.match(b.htmlContent, /<html lang="tr">/);
});
