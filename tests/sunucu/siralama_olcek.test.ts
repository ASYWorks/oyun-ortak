// Göç 20261120006100: indeksli sıralama (siralama, kullanici_sirasi, oyuncu_sirasi) eski sira_listesi ile birebir aynı mı.
// Dört ayar (yön artan/azalan × eşitlik ikincil/ortak), bol eşitlik ve boş ikincil içeren rastgele veri; tepe, orta, dip ve
// skoru olmayan oyuncu gözünden tablo. Ayrıca oyunun yönü değişince sira_degeri yeniden hesaplanır.
import { after, test } from "node:test";
import assert from "node:assert/strict";
import { sql } from "./yardimci.ts";

after(() => sql.end());

const N = 300, DONEM = "2099-01-01";
const AYARLAR = [
  { id: "olc-azalan-ik", yon: "azalan", esitlik: "ikincil" },
  { id: "olc-azalan-or", yon: "azalan", esitlik: "ortak" },
  { id: "olc-artan-ik", yon: "artan", esitlik: "ikincil" },
  { id: "olc-artan-or", yon: "artan", esitlik: "ortak" },
];

type Ref = { kullanici_id: string; puan: string; ikincil: string | null; sira: string; sn: string };

for (const a of AYARLAR) {
  test(`indeksli sıralama eskisiyle aynı: ${a.id}`, async () => {
    await sql`insert into ortak.oyunlar (id, ad, ayarlar) values (${a.id}, ${a.id}, ${sql.json({ siralama: { yon: a.yon, esitlik: a.esitlik, dagilim_esigi: 50 } })})
              on conflict (id) do update set ayarlar = excluded.ayarlar`;
    await sql`delete from ortak.skorlar where oyun_id = ${a.id}`;
    const idler = (await sql`insert into auth.users (id, aud, role, email)
      select gen_random_uuid(), 'authenticated', 'authenticated', 'olc' || g || '-' || ${a.id} || '-' || floor(random() * 1e9) || '@test.local'
      from generate_series(1, ${N}) g returning id`).map((r) => r.id as string);
    // puan 0..20 (çok eşitlik), ikincil 0..5 ya da boş
    await sql`insert into ortak.skorlar (oyun_id, kullanici_id, tur, donem, puan, ikincil, run_id)
      select ${a.id}, u, 'gunluk', ${DONEM}, floor(random() * 21), case when random() < 0.2 then null else floor(random() * 6) end, gen_random_uuid()
      from unnest(${idler}::uuid[]) u`;
    const ref = (await sql`select kullanici_id, puan::text, ikincil::text, sira::text, sn::text
      from ortak.sira_listesi(${a.id}, 'gunluk', ${DONEM})`) as unknown as Ref[];
    const refMap = new Map(ref.map((r) => [r.kullanici_id, r]));

    // her oyuncunun sırası
    const yeni = await sql`select u as kullanici_id, s.sira, s.sn from unnest(${idler}::uuid[]) u, lateral ortak.oyuncu_sirasi(${a.id}, 'gunluk', ${DONEM}, u) s`;
    assert.equal(yeni.length, N);
    for (const y of yeni) {
      const r = refMap.get(y.kullanici_id)!;
      assert.deepEqual([y.sira, y.sn], [Number(r.sira), Number(r.sn)], `oyuncu ${r.puan}/${r.ikincil}`);
    }
    const ks = (await sql`select ortak.kullanici_sirasi(${a.id}, 'gunluk', ${DONEM}, ${idler[7]!}) as v`)[0]!.v;
    assert.deepEqual(ks, { sira: Number(refMap.get(idler[7]!)!.sira), toplam: N, ust_yuzde: Math.ceil((100 * Number(refMap.get(idler[7]!)!.sira)) / N) });

    // tablo: tepe, orta, dip ve skorsuz oyuncu gözünden
    const sirali = [...ref].sort((x, y) => Number(x.sn) - Number(y.sn));
    const bakanlar = [sirali[0]!.kullanici_id, sirali[150]!.kullanici_id, sirali[N - 1]!.kullanici_id, null];
    for (const [ilk, cevre] of [[10, 3], [100, 10], [1, 0]] as const)
      for (const ben of bakanlar) {
        const t = await sql.begin(async (tx) => {
          await tx`select set_config('request.jwt.claims', ${JSON.stringify(ben ? { sub: ben, role: "authenticated" } : { role: "anon" })}, true)`;
          return (await tx`select ortak.siralama(${a.id}, 'gunluk', ${DONEM}, ${ilk}, ${cevre}) as v`)[0]!.v;
        });
        const b = ben ? refMap.get(ben)! : null;
        const beklenen = sirali.filter((r) => Number(r.sn) <= ilk || (b && Math.abs(Number(r.sn) - Number(b.sn)) <= cevre))
          .map((r) => ({ sira: Number(r.sira), puan: Number(r.puan), ikincil: r.ikincil === null ? null : Number(r.ikincil), ben: r.kullanici_id === ben }));
        assert.equal(t.toplam, N);
        assert.deepEqual(t.ben?.sira ?? null, b ? Number(b.sira) : null);
        assert.deepEqual(t.satirlar.map((s: { sira: number; puan: number; ikincil: number | null; ben: boolean }) =>
          ({ sira: s.sira, puan: Number(s.puan), ikincil: s.ikincil === null ? null : Number(s.ikincil), ben: s.ben })), beklenen,
          `ilk ${ilk} çevre ${cevre}, bakan ${b ? b.sn : "yok"}`);
      }
    await sql`delete from ortak.hiz_sinirlari where anahtar like 'siralama:%'`;
    await sql`delete from auth.users where id = any(${idler}::uuid[])`;
  });
}

test("oyunun yönü değişince sira_degeri yeniden hesaplanır", async () => {
  const id = "olc-yon";
  await sql`insert into ortak.oyunlar (id, ad, ayarlar) values (${id}, ${id}, ${sql.json({ siralama: { yon: "azalan" } })}) on conflict (id) do update set ayarlar = excluded.ayarlar`;
  const [{ id: u }] = await sql`insert into auth.users (id, aud, role, email) values (gen_random_uuid(), 'authenticated', 'authenticated', ${`yon${Date.now()}@test.local`}) returning id`;
  await sql`insert into ortak.skorlar (oyun_id, kullanici_id, tur, donem, puan, run_id) values (${id}, ${u}, 'gunluk', ${DONEM}, 7, gen_random_uuid())`;
  assert.equal(Number((await sql`select sira_degeri from ortak.skorlar where oyun_id = ${id}`)[0]!.sira_degeri), 7);
  await sql`update ortak.oyunlar set ayarlar = ${sql.json({ siralama: { yon: "artan" } })} where id = ${id}`;
  assert.equal(Number((await sql`select sira_degeri from ortak.skorlar where oyun_id = ${id}`)[0]!.sira_degeri), -7);
  await sql`delete from auth.users where id = ${u}`;
  await sql`delete from ortak.oyunlar where id = ${id}`;
});
