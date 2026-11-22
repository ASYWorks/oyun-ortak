// Beat Greedy (sezgi) şemasının ortak projedeki davranışı. Oyunun kendi kural testleri sezgi deposunda
// (tools/servertest); burada yalnız şemanın erişilebilirliği, zamanlanmış işler ve ortak silme yolu denetlenir.
import { after, test } from "node:test";
import assert from "node:assert/strict";
import { bellekDepo } from "../../src/kayit/index.ts";
import { hesapBaslat } from "../../src/hesap/index.ts";
import { istemci, kaliciGir, kaliciKullanici, yonetici, sql, oyunSil, adVer } from "./yardimci.ts";

after(() => sql.end());

/** Açılmış gün koruması (göç 7100): test bulmacasını silmek bilinçli düzeltme ister. */
const bulmacaSil = (q: (tx: typeof sql) => Promise<unknown>) =>
  sql.begin(async (tx) => { await tx`set local sezgi.duzeltme = 'evet'`; await q(tx as unknown as typeof sql); });

const oyuncu = async () => {
  const c = istemci();
  const h = hesapBaslat({ supabase: c, oyunId: "sezgi", depo: bellekDepo() });
  const id = await kaliciGir(h); // Beat Greedy profili kalıcı hesap ister
  return { c, h, id, sezgi: () => c.schema("sezgi") };
};

test("sezgi şeması API'de: profil kendi satırını yazar, başkası okuyabilir, başkasının adına yazamaz", async () => {
  const a = await oyuncu();
  const ad = `bg_${Math.floor(Math.random() * 1e8)}`;
  assert.equal((await a.sezgi().from("profiles").insert({ id: a.id, username: ad })).error, null);
  const b = await oyuncu();
  const { data } = await b.sezgi().from("profiles").select("username").eq("id", a.id);
  assert.deepEqual(data, [{ username: ad }]);
  assert.ok((await b.sezgi().from("profiles").insert({ id: a.id, username: "baska_ad" })).error);
  assert.ok((await b.sezgi().from("profiles").insert({ id: b.id, username: "sik" })).error, "küfür süzgeci");
  // ortak ad kuralı: Türkçe harf ve nokta geçer, tire geçmez
  assert.ok((await b.sezgi().from("profiles").insert({ id: b.id, username: "kara-kedi" })).error, "tire");
  const tr = `Ayşe.k${Math.floor(Math.random() * 1e6)}`;
  assert.equal((await b.sezgi().from("profiles").insert({ id: b.id, username: tr })).error, null);
  // misafir (anonim) profil yazamaz
  const m = istemci();
  const mid = await hesapBaslat({ supabase: m, oyunId: "sezgi", depo: bellekDepo() }).anonimGir();
  assert.match((await m.schema("sezgi").from("profiles").insert({ id: mid, username: `misafir_${Math.floor(Math.random() * 1e6)}` })).error?.message ?? "", /kalici_hesap_gerekli/);
});

test("zamanlanmış işlerin çağırdığı fonksiyonlar sezgi şemasında çalışır", async () => {
  for (const f of ["expire_attempts", "refresh_boards", "update_beaten_targets", "purge_attempt_details"])
    await sql.unsafe(`select sezgi.${f}()`);
  const isler = await sql`select jobname, command from cron.job where jobname like 'sezgi-%' order by 1`;
  assert.equal(isler.length, 6); // sezgi'nin 5 işi + silinen_oyuncular temizliği
  for (const j of isler) assert.doesNotMatch(j.command, /public\./, j.jobname);
});

test("BG-1: kullanıcı adı ortak kurallarla denetlenip ortak kayda yansır (süzgeç, 30 gün, benzersizlik)", async () => {
  const a = await oyuncu();
  const ad = `bg_ad${Math.floor(Math.random() * 1e8)}`;
  assert.equal((await a.sezgi().from("profiles").insert({ id: a.id, username: ad })).error, null);
  const oku = async (id: string) => (await sql`select ad from ortak.oyuncular where oyun_id = 'sezgi' and kullanici_id = ${id}`)[0]?.ad;
  assert.equal(await oku(a.id), ad);
  // 30 gün dolmadan değiştirilemez
  const yeni = `${ad}x`;
  assert.match((await a.sezgi().from("profiles").update({ username: yeni }).eq("id", a.id)).error?.message ?? "", /ad_bekle/);
  await sql`update ortak.oyuncular set ad_degisti = now() - interval '31 days' where oyun_id = 'sezgi' and kullanici_id = ${a.id}`;
  assert.equal((await a.sezgi().from("profiles").update({ username: yeni }).eq("id", a.id)).error, null);
  assert.equal(await oku(a.id), yeni);
  // "bgad…x" ile "bg_ad…x" ortakta aynı anahtar: ikinci kayıt reddedilir
  const b = await oyuncu();
  assert.match((await b.sezgi().from("profiles").insert({ id: b.id, username: yeni.replace("_", "") })).error?.message ?? "", /ad_alinmis/);
  // sezgi'nin kendi süzgecinden geçen ama ortak süzgece takılan ad
  assert.match((await b.sezgi().from("profiles").insert({ id: b.id, username: "Sik42" })).error?.message ?? "", /ad_uygunsuz/);
});

test("BG-1: şikâyetle sıfırlanan ad Beat Greedy profilinde de değişir ve yeniden alınamaz", async () => {
  const hedef = await oyuncu();
  const ad = `kotu_bg${Math.floor(Math.random() * 1e6)}`;
  await hedef.sezgi().from("profiles").insert({ id: hedef.id, username: ad });
  for (let i = 0; i < 3; i++) {
    const [{ id }] = await sql`insert into auth.users (id, aud, role, is_anonymous, email) values (gen_random_uuid(), 'authenticated', 'authenticated', false, ${`s${crypto.randomUUID()}@test.local`}) returning id`;
    await sql`insert into ortak.oyuncular (oyun_id, kullanici_id, olusturma) values ('sezgi', ${id}, now() - interval '3 days')`;
    // Kimlik ve çağrı aynı işlemde (havuzdaki başka bağlantıya düşmesin)
    await sql.begin(async (t) => {
      await t`select set_config('request.jwt.claims', ${JSON.stringify({ sub: id, role: "authenticated", is_anonymous: false })}, true)`;
      await t`select ortak.sikayet_et('sezgi', ${ad}, 'ad')`;
    });
  }
  const [p] = await sql`select username::text as u from sezgi.profiles where id = ${hedef.id}`;
  assert.match(p!.u, /^oyuncu_[0-9a-f]{10}$/);
  assert.equal((await sql`select ad from ortak.oyuncular where oyun_id = 'sezgi' and kullanici_id = ${hedef.id}`)[0]!.ad, null);
  // aynı ad ne Beat Greedy'den ne ortak yoldan yeniden alınabilir; başka bir ad hemen alınabilir
  assert.match((await hedef.sezgi().from("profiles").update({ username: ad }).eq("id", hedef.id)).error?.message ?? "", /ad_uygunsuz/);
  assert.deepEqual(await hedef.h.adDegistir(ad), { durum: "uygunsuz" });
  assert.equal((await hedef.sezgi().from("profiles").update({ username: `temiz_${Math.floor(Math.random() * 1e6)}` }).eq("id", hedef.id)).error, null);
});

test("BG-1: gün toplamı birikir, hafta 7 gün toplanır; istemci yazamaz; kapanışta kademe atlayana sunucu ödülü", async () => {
  const c = await oyuncu();
  assert.match((await c.c.schema("ortak").rpc("gun_toplami_yaz", { p_oyun: "sezgi", p_kullanici: c.id, p_gun: "2026-11-16", p_toplam: 1 })).error?.message ?? "", /permission denied/);

  const [{ hafta }] = await sql`select (ortak.iso_hafta(ortak.bugun()) - 7)::text as hafta`;
  const gun = (n: number) => { const d = new Date(`${hafta}T00:00:00Z`); d.setUTCDate(d.getUTCDate() + n); return d.toISOString().slice(0, 10); };
  const kisiler: string[] = [];
  for (let i = 0; i < 10; i++) {
    const [{ id }] = await sql`insert into auth.users (id, aud, role, is_anonymous) values (gen_random_uuid(), 'authenticated', 'authenticated', false) returning id`;
    await adVer(id, "sezgi");
    kisiler.push(id);
    // Gün içinde artan toplam: son değer geçerli
    await sql`select ortak.gun_toplami_yaz('sezgi', ${id}, ${gun(0)}, 100)`;
    await sql`select ortak.gun_toplami_yaz('sezgi', ${id}, ${gun(0)}, ${1000 + i * 100})`;
    for (let g = 1; g < 7; g++) await sql`select ortak.gun_toplami_yaz('sezgi', ${id}, ${gun(g)}, 10)`;
  }
  const [{ puan }] = await sql`select puan::int from ortak.lig_uyeleri where oyun_id = 'sezgi' and kullanici_id = ${kisiler[0]}`;
  assert.equal(puan, 1000 + 6 * 10); // 7 günün hepsi
  await sql`select ortak.lig_kapat()`;
  const od = await sql`select kullanici_id, odul from ortak.oduller where oyun_id = 'sezgi' and kaynak = ${"lig:" + hafta} and kullanici_id in ${sql(kisiler)}`;
  assert.deepEqual(new Set(od.map((r) => r.kullanici_id)), new Set(kisiler.slice(8)));
  assert.ok(od.every((r) => r.odul === `sira:lig-1-${hafta}`));
});

test("BG-2: İlerleme tablosu yalnız ücretsiz bölümleri (seviye < 4000) sayar; tam sürüm üstünlük vermez", async () => {
  const oyun = `bg2_${Math.floor(Math.random() * 1e8)}`;
  const yap = async (seviyeler: number[]) => {
    const o = await oyuncu();
    await o.sezgi().from("profiles").insert({ id: o.id, username: `ilr_${Math.floor(Math.random() * 1e8)}` });
    for (const [i, level] of seviyeler.entries())
      await sql`insert into sezgi.level_verified (user_id, game, level, raw_stars, value, verified_at)
                values (${o.id}, ${oyun}, ${level}, 3, 1, now() - make_interval(secs => ${100 - i}))`;
    return o.id;
  };
  const ucretsiz = await yap([0, 1, 2001]);          // 9 ücretsiz yıldız
  const tam = await yap([0, 1, 4000, 5000, 7000]);  // 6 ücretsiz + 9 ücretli yıldız
  const satir = async (id: string, game: string) =>
    (await sql`select stars, master3, rank::int from sezgi.board_levels where user_id = ${id} and game = ${game}`)[0];
  assert.deepEqual(await satir(tam, oyun), { stars: 6, master3: 0, rank: 2 });
  assert.deepEqual(await satir(ucretsiz, oyun), { stars: 9, master3: 0, rank: 1 });
  assert.equal((await satir(tam, "all"))!.stars, 6);
  // Yalnız ücretli bölümde yıldızı olan oyuncu tabloda görünmez
  const yalnizTam = await yap([4001]);
  assert.equal(await satir(yalnizTam, oyun), undefined);
});

test("ortak silme yolu: bu oyundan sil sezgi profilini siler; lig kurucusu önce devretmeli", async () => {
  const a = await oyuncu();
  await a.h.ben(); // ortak.oyuncular('sezgi') satırı
  await a.sezgi().from("profiles").insert({ id: a.id, username: `sil_${Math.floor(Math.random() * 1e8)}` });
  await sql`insert into sezgi.leagues (name, owner_id) values ('Deneme Ligi', ${a.id})`;
  // Ad kilidi (AD-1) bu testin konusu değil: kilit bitmiş olsun
  await sql`update ortak.oyuncular set ad_degisti = now() - interval '31 days' where oyun_id = 'sezgi' and kullanici_id = ${a.id}`;
  // Başka oyunda da verisi var: sezgi silinince giriş kaydı kalır (aynı gün yeniden profil denetimi sınanabilsin)
  await sql`insert into ortak.oyuncular (oyun_id, kullanici_id) values ('halka', ${a.id})`;
  await assert.rejects(oyunSil(a.h.supabase, "sezgi"), /owns_leagues/);
  await sql`delete from sezgi.leagues where owner_id = ${a.id}`;
  await oyunSil(a.h.supabase, "sezgi");
  const [{ n }] = await sql`select count(*)::int as n from sezgi.profiles where id = ${a.id}`;
  assert.equal(n, 0);
  assert.equal((await sql`select count(*)::int as n from ortak.oyuncular where oyun_id = 'sezgi' and kullanici_id = ${a.id}`)[0]!.n, 0);
  // Aynı gün profil yeniden açılıp günün bulmacası tekrar oynanamaz
  const { error } = await a.sezgi().from("profiles").insert({ id: a.id, username: `geri_${Math.floor(Math.random() * 1e8)}` });
  assert.match(error?.message ?? "", /ayni_gun_yeniden_profil/);
  // Ertesi gün açılabilir
  await sql`update sezgi.silinen_oyuncular set silindi = now() - interval '1 day' where kullanici_id = ${a.id}`;
  assert.equal((await a.sezgi().from("profiles").insert({ id: a.id, username: `yarin_${Math.floor(Math.random() * 1e8)}` })).error, null);
  // İstek sınırı sayacı silme yolunda sıfırlanmaz
  await sql`insert into sezgi.rate_limits values (${a.id}, 'start_attempt', now(), 30)`;
  await sql`insert into ortak.oyuncular (oyun_id, kullanici_id) values ('halka', ${a.id}) on conflict do nothing`; // giriş kaydı kalsın
  await sql`delete from sezgi.leagues where owner_id = ${a.id}`;
  await oyunSil(a.h.supabase, "sezgi");
  const [{ r }] = await sql`select count(*)::int as r from sezgi.rate_limits where user_id = ${a.id}`;
  assert.equal(r, 1);
});

test("BG-4: Beat Greedy adı Türkçe katlanarak benzersiz (Ayse varken Ayşe, AYŞE, ayse alınamaz)", async () => {
  const n = Math.floor(Math.random() * 1e6);
  const a = await oyuncu();
  assert.equal((await a.sezgi().from("profiles").insert({ id: a.id, username: `Ayse${n}` })).error, null);
  for (const ad of [`Ayşe${n}`, `AYŞE${n}`, `ayse${n}`]) {
    const b = await oyuncu();
    const { error } = await b.sezgi().from("profiles").insert({ id: b.id, username: ad });
    assert.ok(error, ad);
    assert.match(error!.message, /ad_alinmis/, ad);
  }
});

test("BG-5: aynı kurulumdan ikinci hesabın denemesi Beat Greedy günlük tablolarında sayılmaz", async () => {
  const n = Math.floor(Math.random() * 1e8);
  const [a, b] = [await oyuncu(), await oyuncu()];
  for (const [o, ad] of [[a, `kur_a${n}`], [b, `kur_b${n}`]] as const)
    assert.equal((await o.sezgi().from("profiles").insert({ id: o.id, username: ad })).error, null);
  const gun = "2031-01-0" + (1 + (n % 9));
  const [{ id: pid }] = await sql`insert into sezgi.daily_puzzles (kind, game, day, engine_version, params, instance, target_value, target_proven, greedy_value)
    values ('daily', ${"kd" + n}, ${gun}::date, 1, '{}', '{}', 1, true, 1) returning id`;
  const deneme = async (u: string) =>
    (await sql`insert into sezgi.attempts (user_id, puzzle_id, status, submitted_at, duration_ms, value, score)
      values (${u}, ${pid}, 'submitted', now(), 30000, 1, 500) returning id`)[0]!.id;
  const cihaz = crypto.randomUUID();
  const [da, db] = [await deneme(a.id), await deneme(b.id)];
  assert.equal((await sql`select sezgi.kurulum_isaretle(${da}, ${cihaz}) as r`)[0]!.r, false);
  assert.equal((await sql`select sezgi.kurulum_isaretle(${db}, ${cihaz}) as r`)[0]!.r, true);
  const tablo = await sql`select user_id from sezgi.board_day where day = ${gun}::date`;
  assert.deepEqual(tablo.map((r) => r.user_id), [a.id]);
  assert.equal((await sql`select count(*)::int as n from sezgi.board_game_day where day = ${gun}::date`)[0]!.n, 1);
  await bulmacaSil((tx) => tx`delete from sezgi.daily_puzzles where id = ${pid}`);
});

test("BG-11: game_sign 16 oyun (büyük-iyi: canta, yilan, bostan, aniz, dedikodu, bayram)", async () => {
  const [{ r }] = await sql`select jsonb_object_agg(g, sezgi.game_sign(g)) as r from unnest(array['canta','yilan','bostan','aniz','dedikodu','bayram','kasa','yufka','harman','halat']) g`;
  assert.deepEqual(r, { canta: 1, yilan: 1, bostan: 1, aniz: 1, dedikodu: 1, bayram: 1, kasa: -1, yufka: -1, harman: -1, halat: -1 });
});

test("BG-12: misafir (anon) Beat Greedy tablolarını sütun adıyla okur, user_id'yi okuyamaz", async () => {
  const anon = istemci().schema("sezgi");
  for (const [t, s] of [["board_day", "day,username,total,rank"], ["board_game_day", "game,day,username,rank"], ["board_race", "day,game,username,rank"], ["board_levels", "game,username,stars,rank"]] as const) {
    const { error } = await anon.from(t).select(s).limit(1);
    assert.equal(error, null, t);
    const { error: e2 } = await anon.from(t).select("user_id").limit(1);
    assert.ok(e2, `${t}: user_id açık`);
  }
  assert.ok((await anon.from("league_board_day").select("username").limit(1)).error, "lig tablosu misafire kapalı");
});

test("PU-7: Yarış ipucu hakkı 3, dördüncüsü ipucu_hakki_bitti; yeni puan sütunları var", async () => {
  const n = Math.floor(Math.random() * 1e8);
  const a = await oyuncu();
  assert.equal((await a.sezgi().from("profiles").insert({ id: a.id, username: `ipucu${n}` })).error, null);
  const [{ id: pid }] = await sql`insert into sezgi.daily_puzzles (kind, game, day, engine_version, params, instance, target_value, target_proven, greedy_value)
    values ('race', ${"ip" + n}, (now() at time zone 'Europe/Istanbul')::date, 1, '{}', '{}', 1, true, 1) returning id`;
  const [{ id: aid }] = await sql`insert into sezgi.attempts (user_id, puzzle_id, status, puan, puan_surumu, ayrinti)
    values (${a.id}, ${pid}, 'started', 4.2, 1, '{"sure": 1}') returning id`;
  for (const beklenen of [1, 2, 3])
    assert.equal((await sql`select sezgi.count_hint(${aid}, ${a.id}) as h`)[0]!.h, beklenen);
  await assert.rejects(sql`select sezgi.count_hint(${aid}, ${a.id})`, /ipucu_hakki_bitti/);
  await sql`update sezgi.attempts set status = 'submitted' where id = ${aid}`;
  assert.equal((await sql`select sezgi.count_hint(${aid}, ${a.id}) as h`)[0]!.h, null, "kapanmış deneme: null (attempt_closed)");
  assert.equal((await sql`select ayarlar -> 'lig' ->> 'esitlik' as e from ortak.oyunlar where id = 'sezgi'`)[0]!.e, "ikincil");
  await bulmacaSil((tx) => tx`delete from sezgi.daily_puzzles where id = ${pid}`);
});

test("PU-8 + PU-7 b/e/f: puan ayarı Pazartesi kuralı; tablolar kapıdan önce eski, kapıdan sonra yeni puanla; seviye puanı; kalibrasyon", async () => {
  // ayar kuralları
  await assert.rejects(sql`insert into ortak.puan_ayar (oyun_id, surum, gecerli, ayar) values ('deneme', 1, '2030-01-08', '{}')`, /check/i, "Pazartesi değil");
  await assert.rejects(sql`insert into ortak.puan_ayar (oyun_id, surum, gecerli, ayar) values ('deneme', 1, '2020-01-06', '{}')`, /puan_ayar_gecmis/);
  await sql`insert into ortak.puan_ayar (oyun_id, surum, gecerli, ayar) values ('deneme', 1, '2030-01-07', '{"h": 1}')`;
  await assert.rejects(sql`insert into ortak.puan_ayar (oyun_id, surum, gecerli, ayar) values ('deneme', 2, '2029-12-31', '{}')`, /puan_ayar_sira/);
  assert.deepEqual((await sql`select surum, ayar from ortak.puan_ayari('deneme', '2030-01-09')`).map((r) => [r.surum, r.ayar]), [[1, { h: 1 }]]);
  assert.equal((await sql`select count(*)::int n from ortak.puan_ayari('deneme', '2030-01-06')`)[0]!.n, 0);
  await sql`delete from ortak.puan_ayar where oyun_id = 'deneme'`;

  // kapı: 2031-01-06 Pazartesi
  const n = Math.floor(Math.random() * 1e8);
  const [a, b] = [await oyuncu(), await oyuncu()];
  for (const [o, ad] of [[a, `pa${n}`], [b, `pb${n}`]] as const)
    assert.equal((await o.sezgi().from("profiles").insert({ id: o.id, username: ad })).error, null);
  await sql.begin(async (t) => {
    await t`set local ortak.puan_ayar_serbest = 'acik'`;
    await t`delete from ortak.puan_ayar where oyun_id = 'sezgi'`;
    await t`insert into ortak.puan_ayar (oyun_id, surum, gecerli, ayar) values ('sezgi', 1, '2031-01-06', '{"hedef_ms": {}}')`;
  });
  const bulmaca = async (gun: string) => (await sql`insert into sezgi.daily_puzzles (kind, game, day, engine_version, params, instance, target_value, target_proven, greedy_value)
    values ('daily', ${"pu" + n}, ${gun}::date, 1, '{}', '{}', 1, true, 1) returning id`)[0]!.id;
  const [eski, yeni] = [await bulmaca("2031-01-05"), await bulmaca("2031-01-06")];
  const deneme = (u: string, pid: unknown, score: number, ms: number, puan: number | null, lt: number | null) =>
    sql`insert into sezgi.attempts (user_id, puzzle_id, status, submitted_at, duration_ms, value, score, puan, puan_surumu, ayrinti)
      values (${u}, ${pid as number}, 'submitted', now(), ${ms}, 1, ${score}, ${puan}, ${puan === null ? null : 1}, ${puan === null ? null : sql.json({ lt })})`;
  await deneme(a.id, eski, 600, 30000, null, null); await deneme(b.id, eski, 500, 10000, null, null);
  await deneme(a.id, yeni, 600, 30000, 3, 0.4); await deneme(b.id, yeni, 500, 10000, 4, -0.2);
  const sira = async (gun: string) => (await sql`select user_id from sezgi.board_day where day = ${gun}::date order by rank`).map((r) => r.user_id);
  assert.deepEqual(await sira("2031-01-05"), [a.id, b.id], "kapıdan önce eski hesap (score)");
  assert.deepEqual(await sira("2031-01-06"), [b.id, a.id], "kapıdan sonra yeni puan");
  await sql`select sezgi.refresh_boards()`;
  const hafta = await sql`select user_id, puan::float from sezgi.board_week where week_start = '2031-01-06' order by rank`;
  assert.deepEqual(hafta.map((r) => [r.user_id, r.puan]), [[b.id, 4], [a.id, 3]]);
  const kal = await sql`select * from sezgi.kalibrasyon(now() - interval '1 hour', now() + interval '1 hour') where game = ${"pu" + n} and day = '2031-01-06'`;
  assert.equal(Number(kal[0]!.oyuncu), 2);

  // seviye puanı en iyisinde kalır, yıldız ayrı
  await sql`select sezgi.record_level(${a.id}, 'kasa', 1, 2, 5.0, 70)`;
  await sql`select sezgi.record_level(${a.id}, 'kasa', 1, 1, 6.0, 40)`;
  await sql`select sezgi.record_level(${a.id}, 'kasa', 1, 1, 6.0)`;
  const [lv] = await sql`select raw_stars, value, puan::float from sezgi.level_verified where user_id = ${a.id} and game = 'kasa' and level = 1`;
  assert.deepEqual([lv!.raw_stars, lv!.value, lv!.puan], [2, 5, 70]);
  assert.equal((await sql`select sezgi.record_level(${a.id}, 'kasa', 2, 1, 1.0, 101) as r`)[0]!.r.error, "bad_puan");
  assert.equal((await sql`select sezgi.record_level(${a.id}, 'kasa', 2, 1, 1.0, 55.5) as r`)[0]!.r.error, "bad_puan", "ondalık yok");
  // puan sürüm 3: kapı açıkken ilk kayıt kalıcı, geçmese de (daha iyisi yazılmaz); kapı kapalıyken en iyisi
  assert.equal((await sql`select sezgi.puan_v3('2026-11-22') as v`)[0]!.v, false);
  assert.equal((await sql`select sezgi.puan_v3('2026-11-23') as v`)[0]!.v, true);
  await sql`update sezgi.puan_surumleri set gecerli = '2026-11-09' where formul = 3`;
  try {
    await sql`select sezgi.record_level(${a.id}, 'kasa', 3, 0, 9.0, 30)`;
    await sql`select sezgi.record_level(${a.id}, 'kasa', 3, 3, 2.0, 95)`;
    const [v3] = await sql`select raw_stars, puan::float from sezgi.level_verified where user_id = ${a.id} and game = 'kasa' and level = 3`;
    assert.deepEqual([v3!.raw_stars, v3!.puan], [0, 30]);
  } finally {
    await sql`update sezgi.puan_surumleri set gecerli = '2026-11-23' where formul = 3`;
  }

  await bulmacaSil((tx) => tx`delete from sezgi.daily_puzzles where id in (${eski}, ${yeni})`);
  await sql.begin(async (t) => { await t`set local ortak.puan_ayar_serbest = 'acik'`; await t`delete from ortak.puan_ayar where oyun_id = 'sezgi'`; });
  await sql`select sezgi.refresh_boards()`;
});

test("PU-7 g: my_daily_stats kapıdan sonra puan ortalaması ve son 14 gün puanı; eski alanlar yerinde", async () => {
  const n = Math.floor(Math.random() * 1e8);
  const a = await oyuncu();
  assert.equal((await a.sezgi().from("profiles").insert({ id: a.id, username: `ist${n}` })).error, null);
  const bugun = (await sql`select sezgi.istanbul_today()::text as d`)[0]!.d as string;
  const pzt = (await sql`select date_trunc('week', ${bugun}::date)::date::text as d`)[0]!.d as string;
  await sql.begin(async (t) => {
    await t`set local ortak.puan_ayar_serbest = 'acik'`;
    await t`delete from ortak.puan_ayar where oyun_id = 'sezgi'`;
    await t`insert into ortak.puan_ayar (oyun_id, surum, gecerli, ayar) values ('sezgi', 1, ${pzt}::date, '{}')`;
  });
  const [{ id: pid }] = await sql`insert into sezgi.daily_puzzles (kind, game, day, engine_version, params, instance, target_value, target_proven, greedy_value)
    values ('daily', ${"is" + n}, ${bugun}::date, 1, '{}', '{}', 1, true, 1) returning id`;
  await sql`insert into sezgi.attempts (user_id, puzzle_id, status, submitted_at, duration_ms, value, score, puan, puan_surumu, ayrinti)
    values (${a.id}, ${pid}, 'submitted', now(), 20000, 1, 800, 4.5, 1, '{"lt": 0.1}')`;
  const [{ r }] = await sql.begin(async (t) => {
    await t`select set_config('request.jwt.claims', ${JSON.stringify({ sub: a.id, role: "authenticated" })}, true)`;
    return t`select sezgi.my_daily_stats() as r`;
  });
  assert.equal(Number(r.avg_puan), 4.5);
  assert.equal(r.avg_total, 800);
  assert.equal(r.recent_puan.length, 14);
  assert.equal(Number(r.recent_puan[13]), 4.5);
  assert.equal(Number(r.games["is" + n].avg_puan), 4.5);
  await bulmacaSil((tx) => tx`delete from sezgi.daily_puzzles where id = ${pid}`);
  await sql.begin(async (t) => { await t`set local ortak.puan_ayar_serbest = 'acik'`; await t`delete from ortak.puan_ayar where oyun_id = 'sezgi'`; });
});

test("SÜ-BG: nabızla aktif süre; duraklama sayılmaz; nabızsızda duvar saati; duraklatılmış Yarış'ta ipucu yok", async () => {
  const n = Math.floor(Math.random() * 1e8);
  const a = await oyuncu();
  assert.equal((await a.sezgi().from("profiles").insert({ id: a.id, username: `nb${n}` })).error, null);
  const bulmaca = async (kind: string) => (await sql`insert into sezgi.daily_puzzles (kind, game, day, engine_version, params, instance, target_value, target_proven, greedy_value)
    values (${kind}, ${"nb" + kind + n}, (now() at time zone 'Europe/Istanbul')::date, 1, '{}', '{}', 1, true, 1) returning id`)[0]!.id;
  const [pk, pr] = [await bulmaca("daily"), await bulmaca("race")];
  const deneme = async (pid: unknown, geri: number) => (await sql`insert into sezgi.attempts (user_id, puzzle_id, status, started_at)
    values (${a.id}, ${pid as number}, 'started', now() - ${geri + " seconds"}::interval) returning id`)[0]!.id;
  // Keşif: nabız, 5 dk duraklama, nabız, bitir
  const k = await deneme(pk, 600);
  const nabiz = async (id: unknown) => (await a.sezgi().rpc("nabiz", { p_attempt: id })).data;
  assert.equal((await nabiz(k)).aktif_ms, 0, "ilk nabız sayacı başlatır");
  await sql`update sezgi.attempts set son_nabiz = son_nabiz - interval '9 seconds' where id = ${k}`;
  assert.ok(Math.abs((await nabiz(k)).aktif_ms - 9000) < 600);
  await sql`update sezgi.attempts set son_nabiz = son_nabiz - interval '300 seconds' where id = ${k}`;
  const ak = (await nabiz(k)).aktif_ms;
  assert.ok(ak <= 24_600 && ak > 9000, `duraklama en çok 15 sn: ${ak}`);
  const [{ r }] = await sql`select sezgi.finish_attempt_tx(${k}, ${a.id}, 1, 500, null, null, 0, false, false, null) as r`;
  assert.ok(r.duration_ms >= ak && r.duration_ms < ak + 1500, `resmi süre aktif: ${r.duration_ms}`);
  // nabızsız deneme: duvar saati (600 sn)
  const pk2 = (await sql`insert into sezgi.daily_puzzles (kind, game, day, engine_version, params, instance, target_value, target_proven, greedy_value) values (${"daily"}, ${"nb2" + n}, (now() at time zone 'Europe/Istanbul')::date, 1, '{}', '{}', 1, true, 1) returning id`)[0]!.id;
  const k2 = await deneme(pk2, 600);
  const [{ r: r2 }] = await sql`select sezgi.finish_attempt_tx(${k2}, ${a.id}, 1, 500, null, null, 0, false, false, null) as r`;
  assert.ok(r2.duration_ms >= 599_000, `duvar saati: ${r2.duration_ms}`);
  // Yarış: taze nabızda ipucu sayılır, 20 sn önceki nabızda duraklatildi
  const y = await deneme(pr, 60);
  await nabiz(y);
  assert.equal((await sql`select sezgi.count_hint(${y}, ${a.id}) as h`)[0]!.h, 1);
  await sql`update sezgi.attempts set son_nabiz = now() - interval '20 seconds' where id = ${y}`;
  await assert.rejects(sql`select sezgi.count_hint(${y}, ${a.id})`, /duraklatildi/);
  assert.equal((await sql`select hints from sezgi.attempts where id = ${y}`)[0]!.hints, 1);
  // başkasının denemesine nabız yazılamaz
  const b = await oyuncu();
  assert.equal((await b.sezgi().rpc("nabiz", { p_attempt: y })).data.error, "attempt_closed");
  await bulmacaSil((tx) => tx`delete from sezgi.daily_puzzles where id in (${pk}, ${pr}, ${pk2})`);
});

test("SÜ-BG durdur: duraklatma cezasız; durmuşken teslim son aralığı sıfırlamaz; durmuş Yarış'ta ipucu yok", async () => {
  const n = Math.floor(Math.random() * 1e8);
  const a = await oyuncu();
  assert.equal((await a.sezgi().from("profiles").insert({ id: a.id, username: `nd${n}` })).error, null);
  const [{ id: pid }] = await sql`insert into sezgi.daily_puzzles (kind, game, day, engine_version, params, instance, target_value, target_proven, greedy_value)
    values ('race', ${"nd" + n}, (now() at time zone 'Europe/Istanbul')::date, 1, '{}', '{}', 1, true, 1) returning id`;
  const [{ id }] = await sql`insert into sezgi.attempts (user_id, puzzle_id, status, started_at) values (${a.id}, ${pid}, 'started', now() - interval '20 minutes') returning id`;
  const nabiz = async (durdur = false) => (await a.sezgi().rpc("nabiz", { p_attempt: id, p_durdur: durdur })).data;
  await nabiz();
  await sql`update sezgi.attempts set son_nabiz = son_nabiz - interval '20 seconds' where id = ${id}`;
  const d = await nabiz(true);
  assert.ok(d.durdu && Math.abs(d.aktif_ms - 20000) < 500, `durdur, 20 sn tam sayılır: ${JSON.stringify(d)}`);
  await assert.rejects(sql`select sezgi.count_hint(${id}, ${a.id})`, /duraklatildi/, "durmuşken ipucu yok");
  await sql`update sezgi.attempts set son_nabiz = son_nabiz - interval '10 minutes' where id = ${id}`;
  const dv = await nabiz();
  assert.equal(dv.aktif_ms, d.aktif_ms, "devam: duraklama eklenmez");
  assert.ok(Math.abs(dv.durak_ms - 600000) < 1000, `duraklama durak_ms'e: ${dv.durak_ms}`);
  await nabiz(true);
  // durmuşken teslim: son aralık yine sayılır (en çok 15 sn); durdur ile sıfırlanamaz
  await sql`update sezgi.attempts set son_nabiz = son_nabiz - interval '60 seconds' where id = ${id}`;
  const [{ r }] = await sql`select sezgi.finish_attempt_tx(${id}, ${a.id}, 1, 500, null, null, 0, false, false, true) as r`;
  assert.ok(Math.abs(r.duration_ms - d.aktif_ms - 60000) < 500, `durmuşken teslimde son aralık tam sayılır: ${r.duration_ms}`);
  assert.ok(r.flags.includes("nabiz_boslugu"), `10 dk duraklama > etkin süre: ${r.flags}`);
  await bulmacaSil((tx) => tx`delete from sezgi.daily_puzzles where id = ${pid}`);
});

test("AD-1: silinen Beat Greedy hesabının adı kilit sürerken başkasına geçmez, yeniden açan yeni adla kilidi atlatamaz", async () => {
  const k = await kaliciKullanici();
  const gir = async () => {
    const c = istemci();
    const h = hesapBaslat({ supabase: c, oyunId: "sezgi", depo: bellekDepo() });
    await h.disGiris(() => c.auth.signInWithPassword({ email: k.eposta, password: k.parola }));
    return { c, id: (await c.auth.getUser()).data.user!.id };
  };
  const a = await gir();
  const ad = `bgsil${Math.floor(Math.random() * 1e8)}`;
  assert.equal((await a.c.schema("sezgi").from("profiles").insert({ id: a.id, username: ad })).error, null);
  await oyunSil(a.c, "sezgi");

  const b = await oyuncu();
  assert.match((await b.sezgi().from("profiles").insert({ id: b.id, username: ad })).error?.message ?? "", /ad_alinmis/);

  await yonetici().auth.admin.createUser({ email: k.eposta, password: k.parola, email_confirm: true });
  const a2 = await gir();
  // saklı ad yalnız sahibine döner; başkasına null
  const sakli = (c: typeof a2.c) => c.schema("ortak").rpc("sakli_ad", { p_oyun: "sezgi" });
  const { data: sa } = await sakli(a2.c);
  assert.equal(sa?.ad, ad);
  assert.equal(sa?.kalan_gun, 30);
  assert.equal((await sakli(b.c)).data, null);
  assert.match((await a2.c.schema("sezgi").from("profiles").insert({ id: a2.id, username: `${ad}x` })).error?.message ?? "", /ad_bekle/);
  assert.equal((await a2.c.schema("sezgi").from("profiles").insert({ id: a2.id, username: ad })).error, null);
  assert.equal((await sakli(a2.c)).data, null); // ad geri geldi, artık saklı değil
});

test("7100: nabız boşluğu bayraklı deneme tablodan ve lig toplamından çıkar; ben sütunu; açılmış gün koruması", async () => {
  const n = Math.floor(Math.random() * 1e8);
  const [a, b] = [await oyuncu(), await oyuncu()];
  for (const [o, ad] of [[a, `nb_a${n}`], [b, `nb_b${n}`]] as const)
    assert.equal((await o.sezgi().from("profiles").insert({ id: o.id, username: ad })).error, null);
  const [{ id: pid }] = await sql`insert into sezgi.daily_puzzles (kind, game, day, engine_version, params, instance, target_value, target_proven, greedy_value)
    values ('daily', ${"nb7" + n}, (now() at time zone 'Europe/Istanbul')::date - 1, 1, '{}', '{}', 1, true, 1) returning id`;
  await sql`insert into sezgi.attempts (user_id, puzzle_id, status, submitted_at, duration_ms, value, score, flags)
    values (${a.id}, ${pid}, 'submitted', now(), 30000, 1, 500, '{}'), (${b.id}, ${pid}, 'submitted', now(), 30000, 1, 500, '{nabiz_boslugu}')`;
  const gun = (await sql`select day::text as d from sezgi.daily_puzzles where id = ${pid}`)[0]!.d;
  assert.deepEqual((await sql`select user_id from sezgi.board_day where day = ${gun}::date and user_id in (${a.id}, ${b.id})`).map((r) => r.user_id), [a.id], "bayraklı deneme günlük tabloda (lig toplamının kaynağı) yok");
  assert.equal((await sql`select count(*)::int as n from sezgi.board_game_day where game = ${"nb7" + n} and user_id = ${b.id}`)[0]!.n, 0, "oyun tablosunda da yok");
  // ben: oturumdaki oyuncunun satırı
  const { data: satir } = await a.sezgi().from("board_game_day").select("ben").eq("day", gun).eq("game", "nb7" + n);
  assert.deepEqual(satir, [{ ben: true }]);
  const { data: baskasi } = await b.sezgi().from("board_game_day").select("ben").eq("day", gun).eq("game", "nb7" + n);
  assert.deepEqual(baskasi, [{ ben: false }], "B, A'nın satırını görür ama ben=false");
  // Koruma: açılmış günde örnek değişmez, silinmez; hedef sütunları serbest; bilinçli düzeltmeyle değişir
  await assert.rejects(sql`update sezgi.daily_puzzles set instance = '{"x":1}' where id = ${pid}`, /acilmis_bulmaca_degisemez/);
  await assert.rejects(sql`delete from sezgi.daily_puzzles where id = ${pid}`, /acilmis_bulmaca_degisemez/);
  await sql`update sezgi.daily_puzzles set target_value = 2, target_beaten = true, target_updated_at = now() where id = ${pid}`;
  await sql.begin(async (tx) => { await tx`set local sezgi.duzeltme = 'evet'`; await tx`update sezgi.daily_puzzles set instance = '{"x":1}' where id = ${pid}`; });
  // Gelecek gün serbest
  const [{ id: ileri }] = await sql`insert into sezgi.daily_puzzles (kind, game, day, engine_version, params, instance, target_value, target_proven, greedy_value)
    values ('daily', ${"nb8" + n}, (now() at time zone 'Europe/Istanbul')::date + 30, 1, '{}', '{}', 1, true, 1) returning id`;
  await sql`update sezgi.daily_puzzles set instance = '{"y":1}' where id = ${ileri}`;
  await sql`delete from sezgi.daily_puzzles where id = ${ileri}`;
  await bulmacaSil((tx) => tx`delete from sezgi.daily_puzzles where id = ${pid}`);
});

test("7400: kapalı bölüm (yeni deneme ve lig ret, başlamış deneme sürer); board_*_v ben; lig üye kimliği", async () => {
  const n = Math.floor(Math.random() * 1e8);
  const [a, b] = [await oyuncu(), await oyuncu()];
  for (const [o, ad] of [[a, `kp_a${n}`], [b, `kp_b${n}`]] as const)
    assert.equal((await o.sezgi().from("profiles").insert({ id: o.id, username: ad })).error, null);
  const [{ id: pid }] = await sql`insert into sezgi.daily_puzzles (kind, game, day, engine_version, params, instance, target_value, target_proven, greedy_value)
    values ('daily', ${"kp" + n}, (now() at time zone 'Europe/Istanbul')::date, 1, '{}', '{}', 1, true, 1) returning id`;
  const bayrak = (kapali: string[]) => sql`update ortak.oyunlar set ayarlar = jsonb_set(coalesce(ayarlar, '{}'), '{bayraklar}', ${sql.json({ kapali })}) where id = 'sezgi'`;
  const onceki = (await sql`select ayarlar -> 'bayraklar' as b from ortak.oyunlar where id = 'sezgi'`)[0]!.b;
  try {
    const basla = async (u: string) => (await sql`select sezgi.start_attempt_tx(${u}, ${"kp" + n}, 1, 1, 'daily') as r`)[0]!.r;
    assert.ok((await basla(a.id)).attempt_id, "açıkken A başlar");
    await bayrak(["kesif", "lig"]);
    assert.equal((await basla(b.id)).error, "kapali", "kapalıyken yeni deneme yok");
    assert.ok((await basla(a.id)).attempt_id, "başlamış deneme sürer");
    assert.match((await a.sezgi().from("leagues").insert({ name: `kl${n}`, owner_id: a.id })).error?.message ?? "", /kapali/);
    await bayrak([]);
    // board_week_v / board_all_time_v: ben sütunu, user_id yok
    const { data: hafta, error } = await a.sezgi().from("board_week_v").select("*").limit(1);
    assert.equal(error, null);
    if (hafta?.length) assert.ok(!("user_id" in hafta[0]) && "ben" in hafta[0]);
    // lig üye kimliği: A lig kurar, B katılır; B, A'nın user_id'sini görmez; A, B'yi uye ile çıkarır
    const { data: lig } = await a.sezgi().from("leagues").insert({ name: `kl${n}`, owner_id: a.id }).select("id, invite_code").single();
    assert.ok(lig, "lig kuruldu");
    await bayrak(["lig"]);
    assert.match((await b.sezgi().rpc("join_league", { p_code: lig!.invite_code })).error?.message ?? "", /kapali/);
    await bayrak([]);
    assert.equal((await b.sezgi().rpc("join_league", { p_code: lig!.invite_code })).error, null);
    const { data: uyeler } = await b.sezgi().from("league_members_v").select("*").eq("league_id", lig!.id);
    assert.equal(uyeler!.length, 2);
    assert.ok(!JSON.stringify(uyeler).includes(a.id), "B, A'nın kimliğini görmez");
    assert.deepEqual(uyeler!.filter((u: { ben: boolean }) => u.ben).length, 1);
    const bUye = uyeler!.find((u: { ben: boolean }) => u.ben)!.uye;
    assert.match((await b.sezgi().rpc("remove_league_uye", { p_league: lig!.id, p_uye: bUye })).error?.message ?? "", /not_owner|owner_cannot_leave/);
    assert.equal((await a.sezgi().rpc("remove_league_uye", { p_league: lig!.id, p_uye: bUye })).error, null);
    assert.equal((await sql`select count(*)::int as n from sezgi.league_members where league_id = ${lig!.id}`)[0]!.n, 1);
  } finally {
    await sql`update ortak.oyunlar set ayarlar = jsonb_set(coalesce(ayarlar, '{}'), '{bayraklar}', ${sql.json(onceki ?? {})}) where id = 'sezgi'`;
    await bulmacaSil((tx) => tx`delete from sezgi.daily_puzzles where id = ${pid}`);
  }
});

test("8170: eski yollar kapalı (materyalize tablolar, görünümde user_id, league_members başkası, user_id'li lig işlevleri)", async () => {
  const n = Math.floor(Math.random() * 1e8);
  const [a, b] = [await oyuncu(), await oyuncu()];
  for (const [o, ad] of [[a, `ey_a${n}`], [b, `ey_b${n}`]] as const)
    assert.equal((await o.sezgi().from("profiles").insert({ id: o.id, username: ad })).error, null);
  const anon = istemci().schema("sezgi");
  for (const t of ["board_week", "board_all_time"]) {
    assert.ok((await anon.from(t).select("username").limit(1)).error, `${t}: misafire kapalı`);
    assert.ok((await a.sezgi().from(t).select("username").limit(1)).error, `${t}: girişliye kapalı`);
  }
  for (const t of ["board_game_day", "board_day", "board_race", "board_race_day", "board_levels",
                   "league_board_game_day", "league_board_day", "league_board_week", "league_board_all_time"]) {
    assert.equal((await a.sezgi().from(t).select("username,rank,ben").limit(1)).error, null, `${t}: ben okunur`);
    assert.ok((await a.sezgi().from(t).select("user_id").limit(1)).error, `${t}: user_id kapalı`);
  }
  // submit_attempt Edge Function service_role ile board_day'i user_id'yle süzer: açık kalmalı
  assert.equal((await yonetici().schema("sezgi").from("board_day").select("total").eq("user_id", a.id)).error, null);
  // board_levels ben: kendi satırı
  await sql`insert into sezgi.level_verified (user_id, game, level, raw_stars, value, verified_at) values (${a.id}, ${"ey" + n}, 0, 3, 1, now())`;
  assert.deepEqual((await a.sezgi().from("board_levels").select("ben").eq("game", "ey" + n)).data, [{ ben: true }]);
  // league_members: B yalnız kendi satırını görür; diğer üyeler league_members_v'de
  const { data: lig } = await a.sezgi().from("leagues").insert({ name: `ey${n}`, owner_id: a.id }).select("id, invite_code").single();
  assert.equal((await b.sezgi().rpc("join_league", { p_code: lig!.invite_code })).error, null);
  const { data: kendi } = await b.sezgi().from("league_members").select("user_id, role, leagues(name)").eq("league_id", lig!.id);
  assert.deepEqual(kendi, [{ user_id: b.id, role: "member", leagues: { name: `ey${n}` } }]);
  assert.equal((await b.sezgi().from("league_members_v").select("uye").eq("league_id", lig!.id)).data!.length, 2);
  // user_id'li eski işlevler kapalı; uye'li olanlar çalışır
  assert.ok((await a.sezgi().rpc("transfer_league", { p_league: lig!.id, p_user: b.id })).error);
  assert.ok((await a.sezgi().rpc("remove_league_member", { p_league: lig!.id, p_user: b.id })).error);
  const bUye = (await b.sezgi().from("league_members_v").select("uye").eq("league_id", lig!.id).eq("ben", true).single()).data!.uye;
  assert.equal((await a.sezgi().rpc("transfer_league_uye", { p_league: lig!.id, p_uye: bUye })).error, null);
  assert.equal((await sql`select owner_id from sezgi.leagues where id = ${lig!.id}`)[0]!.owner_id, b.id);
  // my_daily_stats girişli oyuncuda çalışır
  const { data: ist, error } = await a.sezgi().rpc("my_daily_stats");
  assert.equal(error, null);
  assert.equal(typeof ist.days, "number");
  await sql`delete from sezgi.leagues where id = ${lig!.id}`;
});
