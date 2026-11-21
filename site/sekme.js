// Görünen bölümün ve dilin sekmesini işaretler (görünürlük CSS'te; bu yalnız vurgu ve erişilebilirlik için).
const isaretle = () => {
  const gorunen = [...document.querySelectorAll(".bolum")].find((b) => b.offsetParent);
  if (!gorunen) return;
  const en = !!gorunen.closest(".dil.en");
  for (const a of document.querySelectorAll(".bolumler a, .diller a")) {
    const etkin = a.classList.contains("d-en") ? en : a.classList.contains("d-tr") ? !en : a.getAttribute("href") === "#" + gorunen.id;
    if (etkin) a.setAttribute("aria-current", "true"); else a.removeAttribute("aria-current");
  }
  // Dil düğmesi öbür dilin karşılık gelen bölümüne gider (genel kural: dil değişince sayfa değişmez)
  const karsi = gorunen.dataset.karsi;
  if (karsi) document.querySelector(en ? ".diller .d-tr" : ".diller .d-en").setAttribute("href", "#" + karsi);
  // Panel her sekme değişiminde başa döner
  gorunen.closest(".panel").scrollTop = 0;
};
addEventListener("hashchange", isaretle);
// İlk yüklemede yerleşim hazır olmadan hesaplanabilir; dil düğmesine basılınca yeniden hesaplanır (tıklama, gezinmeden önce çalışır).
document.querySelector(".diller")?.addEventListener("click", isaretle);
isaretle();

// Oyun içinden ?oyun=<kimlik> ile açılınca yalnız o oyun anılır (hesaplar oyun oyun ayrı, A16); yasal sayfalar arası
// bağlantılar kimliği taşır.
const OYUN_ADLARI = { halka: "Halka Kelime", sticky: "Sticky Ten", sezgi: "Beat Greedy" };
const oyunKimligi = new URLSearchParams(location.search).get("oyun");
if (OYUN_ADLARI[oyunKimligi]) {
  for (const e of document.querySelectorAll("[data-genel]")) e.hidden = true;
  for (const e of document.querySelectorAll("[data-oyun]")) e.hidden = false;
  for (const e of document.querySelectorAll("[data-yalniz]")) e.hidden = e.dataset.yalniz !== oyunKimligi;
  for (const e of document.querySelectorAll(".oyun-adi")) if (!e.textContent.trim() || e.closest("[data-oyun]")) e.textContent = OYUN_ADLARI[oyunKimligi];
  for (const a of document.querySelectorAll('a[href^="/gizlilik/"], a[href^="/hesap-sil/"]')) {
    const u = new URL(a.getAttribute("href"), location.origin);
    u.searchParams.set("oyun", oyunKimligi);
    a.setAttribute("href", u.pathname + u.search + u.hash);
  }
}

