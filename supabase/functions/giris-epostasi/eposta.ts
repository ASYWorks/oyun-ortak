/**
 * giris-epostasi: Supabase Auth "Send Email Hook". Giriş kodu e-postasını oyuncunun diline göre gönderir:
 * Türkçe → giris@asyworks.com, İngilizce → login@asyworks.com. Sağlayıcı Brevo (BREVO_API_KEY, kurucu 17 Kasım: ücretsiz,
 * günde 300); anahtar yoksa Resend (RESEND_API_KEY). Geri dönmek için BREVO_API_KEY gizlisini silmek yeter.
 * Dil, oyunun kod isterken verdiği `emailRedirectTo` adresindeki `dil` parametresinden gelir
 * (`https://asyworks.com/?dil=en`; hesap paketi `epostaKoduGonder(eposta, dil)`), yoksa kullanıcı verisindeki `dil`'den;
 * ikisi de yoksa Türkçe. Bu dosya Deno'ya özgü bir şey kullanmaz: Node testleri doğrudan içe aktarır.
 */

export type Dil = "tr" | "en";

export interface KancaVerisi {
  user?: { email?: string; user_metadata?: Record<string, unknown> };
  email_data?: { token?: string; redirect_to?: string; email_action_type?: string };
}

export interface Eposta {
  from: string;
  to: string[];
  reply_to: string;
  subject: string;
  html: string;
  text: string;
}

/**
 * Kod içeren e-posta türleri (Supabase Auth adlarıyla): yeni kullanıcı "signup", kayıtlı kullanıcı "magiclink"
 * (alt çizgisiz; denetim kaydında "user_recovery_requested" görünür), yeni sürümlerde "email". Parola ve e-posta
 * değiştirme kullanılmadığı için "recovery", "email_change", "invite" reddedilir.
 */
const KODLU = new Set(["signup", "magiclink", "email", "reauthentication"]);

export function dilSec(v: KancaVerisi): Dil {
  try {
    const d = new URL(v.email_data?.redirect_to ?? "").searchParams.get("dil");
    if (d === "en" || d === "tr") return d;
  } catch { /* adres yok ya da geçersiz */ }
  return v.user?.user_metadata?.dil === "en" ? "en" : "tr";
}

const METIN = {
  tr: {
    from: "ASYWorks <giris@asyworks.com>",
    reply_to: "destek@asyworks.com",
    subject: "ASYWorks giriş kodunuz",
    baslik: "Giriş kodunuz:",
    aciklama: "Kodu oyundaki giriş ekranına yazın. Kod bir saat geçerlidir ve bir kez kullanılır.",
    yoksay: "Bu isteği siz yapmadıysanız bu e-postayı yok sayın.",
    alt: [["https://asyworks.com", "asyworks.com"], ["https://asyworks.com/gizlilik/", "Gizlilik"], ["https://asyworks.com/hesap-sil/", "Hesap silme"]],
  },
  en: {
    from: "ASYWorks <login@asyworks.com>",
    reply_to: "support@asyworks.com",
    subject: "Your ASYWorks sign-in code",
    baslik: "Your sign-in code:",
    aciklama: "Type the code into the game's sign-in screen. It is valid for one hour and can be used once.",
    yoksay: "If you didn't ask for this code, ignore this email.",
    alt: [["https://asyworks.com/en/", "asyworks.com"], ["https://asyworks.com/gizlilik/#en", "Privacy"], ["https://asyworks.com/hesap-sil/#en", "Delete account"]],
  },
} as const;

export function epostaHazirla(v: KancaVerisi): Eposta {
  const kime = v.user?.email;
  const kod = v.email_data?.token;
  const tur = v.email_data?.email_action_type ?? "";
  if (!kime || !kod) throw new Error("eksik_veri");
  if (!KODLU.has(tur)) throw new Error(`desteklenmeyen_tur:${tur}`);
  if (!/^\d{4,10}$/.test(kod)) throw new Error("gecersiz_kod");
  const dil = dilSec(v);
  const m = METIN[dil];
  // Bağlantılar boşlukla ayrılır; ayraç olarak orta nokta kullanılmaz (ARAYUZ_KURALLARI §5).
  const alt = m.alt.map(([u, a]) => `<a href="${u}" style="color:#17283b;margin-right:16px">${a}</a>`).join("");
  const html = `<!doctype html>
<html lang="${dil}">
<body style="margin:0;padding:24px;background:#f5f1e8;font-family:-apple-system,Segoe UI,Roboto,Arial,sans-serif;color:#17283b">
  <div style="max-width:420px;margin:0 auto;background:#ffffff;border-radius:14px;overflow:hidden">
    <div style="background:#17283b;padding:18px 28px;border-bottom:4px solid #f2b544">
      <span style="color:#f5f1e8;font-size:20px;font-weight:800;letter-spacing:.02em">ASYWorks</span>
    </div>
    <div style="padding:28px">
      <p style="margin:0 0 16px;font-size:16px">${m.baslik}</p>
      <p style="margin:0 0 20px;font-size:34px;font-weight:700;letter-spacing:8px">${kod}</p>
      <p style="margin:0 0 8px;font-size:14px;color:#55606d">${m.aciklama}</p>
      <p style="margin:0;font-size:13px;color:#7a8490">${m.yoksay}</p>
      <hr style="border:none;border-top:1px solid #e4ddcd;margin:20px 0">
      <p style="margin:0;font-size:12px;color:#7a8490">${alt}</p>
    </div>
  </div>
</body>
</html>`;
  const text = `${m.baslik} ${kod}\n\n${m.aciklama}\n${m.yoksay}\n\n${m.alt.map(([u]) => u).join("\n")}\n`;
  return { from: m.from, to: [kime], reply_to: m.reply_to, subject: m.subject, html, text };
}

const b64 = (b: ArrayBuffer | Uint8Array) => btoa(String.fromCharCode(...new Uint8Array(b)));

/**
 * Standard Webhooks imzası (Supabase kancaları): HMAC-SHA256(`${id}.${zaman}.${govde}`), anahtar `v1,whsec_<base64>`.
 * Başlıkta boşlukla ayrılmış birden çok `v1,<imza>` olabilir. Zaman ±5 dakika dışındaysa reddedilir (tekrar oynatma).
 */
export async function imzaDogru(sir: string, id: string, zaman: string, govde: string, imza: string, simdi = Date.now()): Promise<boolean> {
  const t = Number(zaman);
  if (!id || !Number.isFinite(t) || Math.abs(simdi / 1000 - t) > 300) return false;
  const ham = Uint8Array.from(atob(sir.replace(/^v1,/, "").replace(/^whsec_/, "")), (c) => c.charCodeAt(0));
  const anahtar = await crypto.subtle.importKey("raw", ham, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const beklenen = b64(await crypto.subtle.sign("HMAC", anahtar, new TextEncoder().encode(`${id}.${zaman}.${govde}`)));
  return imza.split(" ").some((p) => {
    const s = p.split(",")[1] ?? "";
    if (s.length !== beklenen.length) return false;
    let fark = 0;
    for (let i = 0; i < s.length; i++) fark |= s.charCodeAt(i) ^ beklenen.charCodeAt(i);
    return fark === 0;
  });
}

const yanit = (durum: number, mesaj?: string) =>
  new Response(JSON.stringify(mesaj ? { error: { http_code: durum, message: mesaj } } : {}), {
    status: durum,
    headers: { "Content-Type": "application/json" },
  });

/** Sağlayıcının istek adresi, başlıkları ve gövdesi. Brevo öncelikli; yoksa Resend. */
export function saglayiciIstegi(e: Eposta, ortam: (ad: string) => string | undefined): { ad: string; url: string; init: RequestInit } | null {
  const brevo = ortam("BREVO_API_KEY");
  if (brevo) {
    const [, ad = "ASYWorks", adres = ""] = /^(.*?)\s*<(.+)>$/.exec(e.from) ?? [];
    return {
      ad: "Brevo",
      url: "https://api.brevo.com/v3/smtp/email",
      init: {
        method: "POST",
        headers: { "api-key": brevo, "Content-Type": "application/json", accept: "application/json" },
        body: JSON.stringify({
          sender: { name: ad, email: adres },
          to: e.to.map((email) => ({ email })),
          replyTo: { email: e.reply_to },
          subject: e.subject,
          htmlContent: e.html,
          textContent: e.text,
        }),
      },
    };
  }
  const resend = ortam("RESEND_API_KEY");
  if (resend) {
    return {
      ad: "Resend",
      url: "https://api.resend.com/emails",
      init: { method: "POST", headers: { Authorization: `Bearer ${resend}`, "Content-Type": "application/json" }, body: JSON.stringify(e) },
    };
  }
  return null;
}

/** Kanca isteğini işler. `ortam` gizlileri verir, `gonder` sağlayıcıya istek atar (testte sahtesi verilir). */
export async function isle(req: Request, ortam: (ad: string) => string | undefined, gonder: typeof fetch = fetch): Promise<Response> {
  if (req.method !== "POST") return yanit(405, "yontem");
  const sir = ortam("SEND_EMAIL_HOOK_SECRET");
  if (!sir || !(ortam("BREVO_API_KEY") || ortam("RESEND_API_KEY"))) {
    console.error("[giris-epostasi] SEND_EMAIL_HOOK_SECRET ya da sağlayıcı anahtarı (BREVO_API_KEY / RESEND_API_KEY) tanımlı değil");
    return yanit(500, "ayar");
  }
  const govde = await req.text();
  const h = (ad: string) => req.headers.get(ad) ?? "";
  if (!(await imzaDogru(sir, h("webhook-id"), h("webhook-timestamp"), govde, h("webhook-signature")))) return yanit(401, "imza");
  let e: Eposta;
  try {
    e = epostaHazirla(JSON.parse(govde) as KancaVerisi);
  } catch (hata) {
    return yanit(400, String((hata as Error).message ?? hata));
  }
  const s = saglayiciIstegi(e, ortam)!;
  const r = await gonder(s.url, { ...s.init, signal: AbortSignal.timeout(4000) }) // kanca 5 sn içinde dönmeli
    .catch((hata) => ({ ok: false, status: 0, text: async () => String(hata) }) as Response);
  if (!r.ok) {
    console.error(`[giris-epostasi] ${s.ad} ${r.status}: ${(await r.text()).slice(0, 300)}`);
    return yanit(502, "gonderilemedi");
  }
  return yanit(200);
}
