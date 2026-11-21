// Halka'nın ortak kaydı: ayarlar ortak paketlerde geçerli, "bu oyundan sil" hk_ tablolarını temizler.
import { after, test } from "node:test";
import assert from "node:assert/strict";
import { bellekDepo } from "../../src/kayit/index.ts";
import { hesapBaslat } from "../../src/hesap/index.ts";
import { istemci, kaliciKullanici, sql, oyunSil } from "./yardimci.ts";

after(() => sql.end());

test("Halka ad kuralı (ortak: 3–20) ve ilk bağlama ödülü", async () => {
  const k = await kaliciKullanici();
  const c = istemci();
  const h = hesapBaslat({ supabase: c, oyunId: "halka", depo: bellekDepo() });
  await h.disGiris(() => c.auth.signInWithPassword({ email: k.eposta, password: k.parola }));
  assert.equal((await h.adDegistir("x".repeat(21))).durum, "bicim"); // 20'den uzun
  assert.equal((await h.adDegistir("Ay")).durum, "bicim"); // ortak kural: en az 3
  assert.equal(await h.baglamaOdulu(), "desen-porselen");
});

test("bu oyundan sil: Halka hakkı temizlenir, hesap ve öbür oyunlar kalır (hk_entitlements 6700'de kaldırıldı)", async () => {
  const k = await kaliciKullanici();
  await sql`insert into ortak.haklar (oyun_id, kullanici_id, hak, durum, kaynak) values ('halka', ${k.id}, 'paket_tam', 'aktif', 'elle')`;
  await sql`insert into ortak.oyuncular (oyun_id, kullanici_id) values ('deneme', ${k.id})`;
  const c = istemci();
  const h = hesapBaslat({ supabase: c, oyunId: "halka", depo: bellekDepo() });
  await h.disGiris(() => c.auth.signInWithPassword({ email: k.eposta, password: k.parola }));
  await h.ben();
  await oyunSil(h.supabase, "halka");
  const [r] = await sql`select
    (select count(*) from ortak.haklar where kullanici_id = ${k.id} and oyun_id = 'halka')::int as n,
    (select count(*) from ortak.oyuncular where kullanici_id = ${k.id} and oyun_id = 'deneme')::int as deneme,
    (select count(*) from auth.users where id = ${k.id})::int as hesap`;
  assert.deepEqual({ ...r }, { n: 0, deneme: 1, hesap: 1 });
});

test("HK-17: eski hk_ nesneleri yok; Web Push kaldırıldı (hk_push ve hk_push_* yok)", async () => {
  const [r] = await sql`select to_regclass('public.hk_profiles') as p, to_regclass('public.hk_daily_scores') as s, to_regclass('public.hk_push') as push`;
  assert.deepEqual([r!.p, r!.s, r!.push], [null, null, null]);
  const [f] = await sql`select count(*)::int as n from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                        where n.nspname = 'public' and p.proname like 'hk_push%'`;
  assert.equal(f!.n, 0);
});

test("duraklatılmış denemede ipucu yok: son nabız 45 sn'den eskiyse duraklatildi; taze nabızda ve nabızsızda ipucu gelir", async () => {
  const k = await kaliciKullanici();
  const anahtar = `hk-durak-${crypto.randomUUID()}`;
  const ipucu = (t: typeof sql) => t`select halka.ipucu_ver(${anahtar}, '[[1],[2],[3]]'::jsonb, '{a,b,c}', '{"rot":[0,1,2],"flip":[false,false,false]}'::jsonb, '{"a":"x"}'::jsonb, '{0,1,2}', '{}'::jsonb, 'anlam', 0, null, null, null, null) as v`;
  // anlam ipucu: durumsuz kilit 20261120005600'de kaldırıldı (durum_gerekli)
  const kullaniciOlarak = (f: (t: typeof sql) => Promise<unknown>) => sql.begin(async (t) => {
    await t`select set_config('request.jwt.claims', ${JSON.stringify({ sub: k.id, role: "authenticated" })}, true)`;
    return f(t as unknown as typeof sql);
  });
  // nabızsız deneme (eski istemci): ipucu gelir
  assert.ok(((await kullaniciOlarak(ipucu)) as { v: unknown }[])[0]!.v);
  // taze nabız: ipucu gelir
  await sql`update ortak.denemeler set son_nabiz = now() where kullanici_id = ${k.id} and anahtar = ${anahtar}`;
  assert.ok(((await kullaniciOlarak(ipucu)) as { v: unknown }[])[0]!.v);
  // 35 sn önce son nabız (nabız 30 sn, 6300): duraklatılmış sayılmaz (hak bittiği için yanıt boş olabilir, ret yok)
  await sql`update ortak.denemeler set son_nabiz = now() - interval '35 seconds' where kullanici_id = ${k.id} and anahtar = ${anahtar}`;
  await kullaniciOlarak(ipucu);
  // 60 sn önce son nabız: duraklatıldı, ipucu yazılmaz
  await sql`update ortak.denemeler set son_nabiz = now() - interval '60 seconds' where kullanici_id = ${k.id} and anahtar = ${anahtar}`;
  const once = (await sql`select durum from ortak.denemeler where kullanici_id = ${k.id} and anahtar = ${anahtar}`)[0]!.durum;
  await assert.rejects(kullaniciOlarak(ipucu), /duraklatildi/);
  assert.deepEqual((await sql`select durum from ortak.denemeler where kullanici_id = ${k.id} and anahtar = ${anahtar}`)[0]!.durum, once);
  await sql`delete from ortak.denemeler where kullanici_id = ${k.id}`;
});

test("durdur nabzı gelmiş Halka denemesinde ipucu yok (taze olsa bile)", async () => {
  const k = await kaliciKullanici();
  const anahtar = `hk-durdu-${crypto.randomUUID()}`;
  await sql`insert into ortak.denemeler (oyun_id, kullanici_id, anahtar, son_nabiz, durdu) values ('halka', ${k.id}, ${anahtar}, now(), true)`;
  await assert.rejects(sql.begin(async (t) => {
    await t`select set_config('request.jwt.claims', ${JSON.stringify({ sub: k.id, role: "authenticated" })}, true)`;
    return t`select halka.ipucu_ver(${anahtar}, '[[1],[2],[3]]'::jsonb, '{a,b,c}', '{"rot":[0,1,2],"flip":[false,false,false]}'::jsonb, '{}'::jsonb, '{0,1,2}', '{}'::jsonb, 'kilit', 0, null, null, null, null)`;
  }), /duraklatildi/);
  await sql`delete from ortak.denemeler where kullanici_id = ${k.id}`;
});

test("anlam ipucu da 2 hakla sınırlı: üçüncü istek null döner ve sayılmaz; günlük eşitlik ikincil", async () => {
  const k = await kaliciKullanici();
  const anahtar = `hk-anlam-${crypto.randomUUID()}`;
  const anlam = () => sql.begin(async (t) => {
    await t`select set_config('request.jwt.claims', ${JSON.stringify({ sub: k.id, role: "authenticated" })}, true)`;
    return t`select halka.ipucu_ver(${anahtar}, '[[1],[2],[3]]'::jsonb, '{a,b,c}', null, '{"a":"bir","b":"iki","c":"üç"}'::jsonb, null, '{}'::jsonb, 'anlam', 0, null, null, null, null) as v`;
  }) as Promise<{ v: unknown }[]>;
  assert.ok((await anlam())[0]!.v);
  assert.ok((await anlam())[0]!.v);
  assert.equal((await anlam())[0]!.v, null);
  const [d] = await sql`select durum from ortak.denemeler where kullanici_id = ${k.id} and anahtar = ${anahtar}`;
  assert.deepEqual(d!.durum.ipuclari, ["anlam", "anlam"]);
  const [o] = await sql`select ayarlar #>> '{siralama,esitlik}' as e from ortak.oyunlar where id = 'halka'`;
  assert.equal(o!.e, "ikincil");
  await sql`delete from ortak.denemeler where kullanici_id = ${k.id}`;
});

test("anlam ipucu oyuncunun çerçevesinde: kaymış yerleşimde o dilimde kurulacak kelimenin anlamı, durumsuz istekte asıl çözüm", async () => {
  const k = await kaliciKullanici();
  const iste = (anahtar: string, rot: string | null, flip: string | null) => sql.begin(async (t) => {
    await t`select set_config('request.jwt.claims', ${JSON.stringify({ sub: k.id, role: "authenticated" })}, true)`;
    return t`select halka.ipucu_ver(${anahtar}, '[["a","b","c"],["x","y","z"],["p","q","r"]]'::jsonb, '{axp,byq,czr}',
      '{"rot":[0,0,0],"flip":[false,false,false]}'::jsonb, '{"axp":"A","byq":"B","czr":"C"}'::jsonb, null, '{}'::jsonb,
      'anlam', 0, ${rot}::int[], ${flip}::bool[], null, null) as v`;
  }) as Promise<{ v: { anlam: string } | null }[]>;
  // [1,1,0]: en yakın çerçeve bütün halkalar +1, dilim 0'da "byq" kurulur
  assert.deepEqual((await iste(`hk-cer-1-${crypto.randomUUID()}`, "{1,1,0}", "{f,f,f}"))[0]!.v, { anlam: "B" });
  assert.deepEqual((await iste(`hk-cer-2-${crypto.randomUUID()}`, null, null))[0]!.v, { anlam: "A" });
  await sql`delete from ortak.denemeler where kullanici_id = ${k.id}`;
});

test("HK-22: gelecek günün bulmaca dosyası ve takvim satırı verilmez; turnuva başlayınca; yükleme yalnız servis rolü", async () => {
  const gun = (d: number) => new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Istanbul" }).format(new Date(Date.now() + d * 864e5));
  const [dun, yarin] = [gun(-400), gun(400)]; // gerçek bulmacalarla çakışmasın
  const tk = (g: string) => `usta-${g}`;
  for (const t of [dun, yarin])
    await sql`insert into halka.gunluk_bulmacalar (tarih, halkalar, cevaplar) values (${t}, '[["A"]]', '{A}') on conflict do nothing`;
  for (const t of [dun, yarin])
    await sql`insert into halka.turnuva_bulmacalar (kimlik, basla, bitir, halkalar, cevaplar) values (${tk(t)}, ${t}, ${t}, '[["A"]]', '{A}') on conflict do nothing`;
  try {
    const n = (await sql`select public.halka_dosya_yukle(${sql.json([
      { tarih: dun, dosya: { k: "dun" }, dizin: { date: dun } }, { tarih: yarin, dosya: { k: "yarin" }, dizin: { date: yarin } }])},
      ${sql.json([{ kimlik: tk(dun), dosya: { k: "td" } }, { kimlik: tk(yarin), dosya: { k: "ty" } }])}) as n`)[0]!.n;
    assert.equal(n, 4);
    const c = istemci(); // oturumsuz (anon) okur
    assert.deepEqual((await c.rpc("halka_gunluk_dosya", { p_tarih: dun })).data, { k: "dun" });
    assert.equal((await c.rpc("halka_gunluk_dosya", { p_tarih: yarin })).data, null);
    const dizin = (await c.rpc("halka_gunluk_dizin")).data as { date: string }[];
    assert.ok(dizin.some((x) => x.date === dun) && !dizin.some((x) => x.date === yarin));
    assert.deepEqual((await c.rpc("halka_turnuva_dosya", { p_kimlik: tk(dun) })).data, { k: "td" });
    assert.equal((await c.rpc("halka_turnuva_dosya", { p_kimlik: tk(yarin) })).data, null);
    assert.ok((await c.rpc("halka_dosya_yukle", { p_gunler: [], p_turnuvalar: [] })).error);
  } finally {
    // açılmış bulmaca koruması (6800): test temizliği bilinçli düzeltme olarak
    await sql.begin(async (t) => {
      await t`set local halka.duzeltme = 'evet'`;
      await t`delete from halka.gunluk_bulmacalar where tarih in (${dun}, ${yarin})`;
      await t`delete from halka.turnuva_bulmacalar where kimlik in (${tk(dun)}, ${tk(yarin)})`;
    });
  }
});
