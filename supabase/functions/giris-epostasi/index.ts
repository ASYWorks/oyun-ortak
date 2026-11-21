// Supabase Auth Send Email Hook: giriş kodunu dile göre giris@ / login@asyworks.com'dan gönderir. Ayrıntı: eposta.ts.
import { isle } from "./eposta.ts";

Deno.serve((req) => isle(req, (ad) => Deno.env.get(ad)));
