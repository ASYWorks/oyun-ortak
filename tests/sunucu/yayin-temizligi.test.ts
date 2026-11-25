// Hata bulgusu 3 (Codex): yayın temizliği yalnız önizleme verisini (testçi satırları) siler, normal oyuncu satırına dokunmaz;
// oyun önizlemede değilse ya da yayın tarihi uyuşmuyorsa hiçbir şey silmeden durur; ikinci çalıştırma güvenlidir.
import { after, before, test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { DB_URL, kaliciKullanici, sql } from "./yardimci.ts";

const OYUN = "yytest";
const yarin = new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Istanbul" }).format(new Date(Date.now() + 86_400_000));
const calistir = (y: string, ...arg: string[]) =>
  spawnSync(process.execPath, ["scripts/yayin-temizligi.ts", ...arg], {
    env: { ...process.env, PG_URL: DB_URL, OYUN, Y: y }, encoding: "utf8",
  });
let testci = "", normal = "";

before(async () => {
  await sql`delete from ortak.oyunlar where id = ${OYUN}`;
  await sql`insert into ortak.oyunlar (id, ad, ayarlar) values (${OYUN}, 'YY Test', ${sql.json({ yayin: "onizleme", yayin_tarihi: yarin })})`;
  testci = (await kaliciKullanici()).id;
  normal = (await kaliciKullanici()).id;
  await sql`insert into ortak.testciler (kullanici_id) values (${testci}) on conflict do nothing`;
  for (const k of [testci, normal])
    await sql`insert into ortak.skorlar (oyun_id, kullanici_id, tur, donem, puan, run_id) values (${OYUN}, ${k}, 'gunluk', '2026-11-20', 5, gen_random_uuid())`;
});
after(async () => {
  await sql`delete from ortak.testciler where kullanici_id = ${testci}`;
  await sql`delete from ortak.oyunlar where id = ${OYUN}`;
  await sql.end();
});

const skorlar = async () => (await sql`select kullanici_id from ortak.skorlar where oyun_id = ${OYUN}`).map((r) => r.kullanici_id).sort();
const yayin = async () => (await sql`select ayarlar ->> 'yayin' as y from ortak.oyunlar where id = ${OYUN}`)[0]!.y;

test("yayın tarihi uyuşmazsa hiçbir şey silinmez", async () => {
  const r = calistir("2099-01-01", "uygula");
  assert.notEqual(r.status, 0);
  assert.match(r.stderr + r.stdout, /yayin_tarihi/);
  assert.equal((await skorlar()).length, 2);
  assert.equal(await yayin(), "onizleme");
});

test("kuru koşu yalnız sayar; uygula testçi satırını siler, normal oyuncununkini korur; ikinci çalıştırma durur", async () => {
  const kuru = calistir(yarin);
  assert.equal(kuru.status, 0, kuru.stderr);
  assert.equal((await skorlar()).length, 2);

  const u = calistir(yarin, "uygula");
  assert.equal(u.status, 0, u.stderr);
  assert.deepEqual(await skorlar(), [normal]);
  assert.equal(await yayin(), "acik");

  const iki = calistir(yarin, "uygula");
  assert.notEqual(iki.status, 0);
  assert.match(iki.stderr + iki.stdout, /onizleme/);
  assert.deepEqual(await skorlar(), [normal]);
});
