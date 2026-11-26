// KY-3: saklı bayraklar (Kapı tests/bayrak.test.ts'ten). Hesaba göre ayrılır; eski sahipsiz ya da başka hesabın testçi kaydı
// yetki vermez; temiz açılış önizleme kilidiyle başlar; geç ya da başka hesaba ait yanıt uygulanmaz.
import { test } from "node:test";
import assert from "node:assert/strict";
import { bayrakDeposu, kimlikUyar, CEVRIMICI_OZELLIKLER, type BayrakDepo } from "./index.ts";

const depo = (ilk: Record<string, string> = {}) => {
  const m = new Map(Object.entries(ilk));
  return { m, d: { al: (k) => m.get(k) ?? null, yaz: (k, v) => { m.set(k, v); }, sil: (k) => { m.delete(k); } } as BayrakDepo };
};
const TESTCI = { onizleme: true, testci: true, kapali: [] as string[] };
const HALK = { onizleme: true, kapali: ["gunluk", "lig", "etkinlik", "siralama", "duello"] };
const kur = (d: BayrakDepo, eski?: string) => bayrakDeposu(d, "o", { eskiAnahtar: eski });
/** Uygulamadaki gibi: güncel kaynaklar bellekteki oturum ve cihazdaki gerçek oturum; burada ikisi de simdi. */
const kaydet = (d: BayrakDepo, istek: string, simdi: string, b: unknown) => kur(d).cevapKaydet(istek, [simdi, simdi], b);

test("temiz açılış: önizleme varsayılır, bütün çevrimiçi özellikler kapalı", () => {
  const b = kur(depo().d).ilkBayraklar("");
  assert.deepEqual(b, { onizleme: true, kapali: CEVRIMICI_OZELLIKLER });
  assert.equal(b.testci, undefined);
});

test("oyunun kendi varsayılan kapalı listesi verilebilir", () => {
  assert.deepEqual(bayrakDeposu(depo().d, "o", { varsayilanKapali: ["gunluk"] }).ilkBayraklar(""), { onizleme: true, kapali: ["gunluk"] });
});

test("eski sahipsiz kayıt (testçi olabilir) okunmaz ve silinir", () => {
  const { m, d } = depo({ "o:bayraklar": JSON.stringify(TESTCI) });
  const b = kur(d, "o:bayraklar");
  assert.deepEqual(b.ilkBayraklar(""), b.bilinmeyen());
  assert.deepEqual(b.ilkBayraklar("b"), b.bilinmeyen());
  assert.equal(m.has("o:bayraklar"), false);
});

test("geçersiz ya da bozuk saklı değer: bilinmeyen duruma düşer", () => {
  for (const v of ["{bozuk", '"metin"', "[1,2]", JSON.stringify({ kapali: "gunluk" }), JSON.stringify({ kapali: [1] })]) {
    const b = kur(depo({ "o:bayraklar:genel": v }).d);
    assert.deepEqual(b.ilkBayraklar(""), b.bilinmeyen(), v);
  }
  const b = kur(depo({ "o:bayraklar:hesap": JSON.stringify({ sahip: "a", b: { kapali: "x", testci: true } }) }).d);
  assert.deepEqual(b.ilkBayraklar("a"), b.bilinmeyen());
});

test("A testçisinin kaydı: B hesabında ve misafirde testçi yetkisi vermez; aynı A çevrimdışı da testçi kalır", () => {
  const { d } = depo();
  kaydet(d, "a", "a", TESTCI);
  const b = kur(d);
  assert.equal(b.ilkBayraklar("b").testci, undefined, "B hesabı");
  assert.equal(b.ilkBayraklar("").testci, undefined, "misafir");
  assert.deepEqual(b.ilkBayraklar("b"), b.bilinmeyen(), "testçinin boş kapali listesi halka açık kayda yazılmaz");
  assert.deepEqual(b.ilkBayraklar("a"), TESTCI, "doğru sahip");
});

test("normal oyuncunun yanıtı halka açık kayda da yazılır; sonraki misafir onu görür, testçi alanı yok", () => {
  const { d } = depo();
  kaydet(d, "b", "b", HALK);
  const b = kur(d);
  assert.deepEqual(b.ilkBayraklar(""), HALK);
  assert.deepEqual(b.ilkBayraklar("c"), HALK);
  assert.deepEqual(b.ilkBayraklar("b"), HALK);
});

test("misafir yanıtı testçi yetkisi taşıyamaz; doğrulanmış yayın durumu normal davranır", () => {
  const { m, d } = depo();
  assert.equal(kaydet(d, "", "", { ...TESTCI }), null, "biçim dışı: uygulanmaz");
  assert.equal(m.size, 0);
  assert.deepEqual(kaydet(d, "", "", { kapali: [], yayin_tarihi: "2027-01-15" }), { kapali: [], yayin_tarihi: "2027-01-15" });
  assert.deepEqual(kur(d).ilkBayraklar(""), { kapali: [], yayin_tarihi: "2027-01-15" });
});

test("geç dönen ya da başka hesaba ait yanıt uygulanmaz ve saklanmaz (iki kaynak da aynı kimliği göstermeli)", () => {
  const { m, d } = depo();
  const b = kur(d);
  assert.equal(kaydet(d, "a", "b", TESTCI), null);
  assert.equal(kaydet(d, "a", "", TESTCI), null);
  assert.equal(b.cevapKaydet("a", ["a", "b"], TESTCI), null, "bellek A, cihaz B");
  assert.equal(b.cevapKaydet("", ["", "b"], HALK), null, "misafir isteği, cihazda B girmiş");
  assert.equal(m.size, 0);
  assert.deepEqual(b.cevapKaydet("a", ["a", "a"], TESTCI), TESTCI);
  assert.equal(kimlikUyar("a", ["a", "a"]), true);
  assert.equal(kimlikUyar("a", ["a", null]), false);
});

test("iki oyun aynı depoda birbirinin kaydını görmez", () => {
  const { d } = depo();
  bayrakDeposu(d, "kapi").cevapKaydet("a", ["a", "a"], TESTCI);
  assert.equal(bayrakDeposu(d, "kayan").ilkBayraklar("a").testci, undefined);
});

test("KY-7: asgari_surum saklanır ve geri okunur (halka açık kayıtta da)", () => {
  const { d } = depo();
  const b = { kapali: [], asgari_surum: "1.4.0", duyuru: "x" };
  assert.deepEqual(kaydet(d, "", "", b), b);
  assert.equal(kur(d).ilkBayraklar("").asgari_surum, "1.4.0");
  assert.equal(kur(d).ilkBayraklar("a").asgari_surum, "1.4.0");
});
