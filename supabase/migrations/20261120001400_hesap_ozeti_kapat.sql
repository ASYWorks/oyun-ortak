-- OA-1 (15 Kasım 2026): üç oyun da hesabiSil()'e geçti; öbür oyunları listeleyen ortak.hesap_ozeti istemciye kapanır.
-- Hesaplar oyuncunun gözünde oyun oyun ayrıdır: istemci kişinin başka hangi oyunlarda olduğunu öğrenemez.
revoke execute on function ortak.hesap_ozeti() from authenticated;
