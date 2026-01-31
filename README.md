# MonoDash

Monad testnet uzerinde calisan, mikro-event tabanli merkeziyetsiz bahis platformu. Monad'in 400ms blok suresi ve paralel transaction execution modelini kullanarak ultra-hizli betting deneyimi sunar.

## Ozellikler

- **Mikro-eventler:** 30-60 saniyelik bahis pencereleri
- **Sharded storage:** 16 shard ile %93.75 paralel guvenlik - ayni anda bahis yapan kullanicilar neredeyse tamamen paralel calisir
- **Session key destegi:** Cuzdan popup'i olmadan gasless bahis deneyimi
- **Aura AI dogrulama:** Event'ler ECDSA tabanli AI attestation ile dogrulanir
- **Pyth oracle entegrasyonu:** Gercek zamanli fiyat feed'leri
- **Oransal odeme:** Kazananlar havuzu stake oranina gore paylasilir (%2 house fee)

## Gereksinimler

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (forge, anvil, cast)
- Python 3 (frontend icin HTTP server)
- MetaMask veya uyumlu bir cuzdan

## Kurulum

```bash
git clone https://github.com/unw4/MonoDash.git
cd MonoDash
forge install
```

## Calistirilmasi

### Frontend

```bash
chmod +x start.sh
./start.sh
```

Tarayicida `http://localhost:8080` adresini ac.

### MetaMask Ayarlari

| Alan         | Deger                              |
|--------------|------------------------------------|
| Network Name | Monad Testnet                      |
| RPC URL      | https://testnet-rpc.monad.xyz      |
| Chain ID     | 10143                              |
| Currency     | MON                                |
| Explorer     | https://testnet.monadscan.com      |

### Kontrat Deploy

Kontratlar Monad testnet uzerinde zaten deploy edilmis durumda. Yeniden deploy etmek istersen:

```bash
# .env dosyasini olustur
cp .env.example .env
# DEPLOYER_PRIVATE_KEY degerini doldur

# Deploy
source .env && forge script script/Deploy.s.sol --rpc-url $MONAD_RPC_URL --broadcast --legacy
```

### Lokal Test (Anvil)

```bash
anvil
# Baska bir terminalde:
forge script script/LocalDeploy.s.sol --rpc-url http://localhost:8545 --broadcast
```

## Kontrat Mimarisi

```
src/
├── core/
│   ├── EventManager.sol          # Event yasam dongusu (OPEN -> LOCKED -> SETTLED/VOIDED)
│   ├── BettingEngine.sol         # Sharded bahis motoru (16 shard, paralel yazma)
│   ├── SettlementProcessor.sol   # Toplu settlement orkestrator
│   └── UserVault.sol             # Kullanici bazli bakiye yonetimi
├── oracle/
│   ├── PythAdapter.sol           # Pyth Network oracle wrapper
│   └── AuraVerifier.sol          # AI attestation dogrulamasi (ECDSA)
├── account/
│   ├── SessionKeyManager.sol     # Gecici session key yetkilendirmesi
│   └── DelegatedSigner.sol       # EIP-712 imza dogrulama
├── libraries/
│   ├── MicroEventLib.sol         # Event ID uretimi, pencere dogrulama
│   ├── BetLib.sol                # Bahis dogrulama, odeme hesaplama
│   └── ShardLib.sol              # Storage sharding mantigi
└── interfaces/                   # 6 interface dosyasi
```

### Deploy Edilen Kontratlar (Monad Testnet)

| Kontrat              | Adres                                        |
|----------------------|----------------------------------------------|
| AuraVerifier         | `0x758658c989648597db25630264a7b2b58d849099` |
| PythAdapter          | `0x85348658d774e024b4ae31e16e0da9a3e16703a1` |
| UserVault            | `0x472d1f17e59a952f2856bd7c5dfa48fc017746bd` |
| DelegatedSigner      | `0xeee18e9c6f8f6d5999053c22a2919bed74689c9f` |
| EventManager         | `0x794fdb692cc382643a2da6d3036ba1b17beaec98` |
| BettingEngine        | `0x3605249370edaca26da4f8f8d6eee9bb63a45ed9` |
| SessionKeyManager    | `0x21da3d98da6e97ff10d0c493feb97c697832daa6` |
| SettlementProcessor  | `0x5cdeddbc014c919a16da9f6061f92fca8e1cc8ca` |

## Paralel Calisma Tasarimi

MonoDash'in sharded state yapisi sayesinde ayni anda bahis yapan kullanicilar birbirini bloklamaz:

```
userBets[user][eventId]                    -> Kullanici bazli slot (PARALEL)
poolShards[eventId][outcome][shard]        -> 16 bagimsiz shard (%93.75 paralel)
UserVault._balances[user]                  -> Kullanici bazli slot (PARALEL)
```

Shard indeksi kullanicinin adresinin son 4 bitinden turetilir (`uint8(uint160(user) & 0x0F)`), bu da 16 bagimsiz yazma slotu olusturur.

## Testler

```bash
# Tum testler
forge test

# Belirli kontrat
forge test --match-contract EventManager

# Detayli cikti
forge test -vvv

# Gas snapshot
forge snapshot
```

## Proje Yapisi

```
MonoDash/
├── src/                    # Solidity kontratlar
├── test/
│   ├── unit/               # Birim testler (5 dosya)
│   ├── integration/        # Entegrasyon testi
│   └── mocks/              # Mock kontratlar
├── script/
│   ├── Deploy.s.sol        # Monad testnet deploy
│   └── LocalDeploy.s.sol   # Lokal Anvil deploy
├── frontend/
│   ├── index.html          # Tek sayfalik uygulama (ethers.js v6)
│   └── monodashlogo.png    # Logo
├── foundry.toml            # Foundry konfigurasyonu
└── start.sh                # Frontend baslatma scripti
```

## Kullanim Akisi

1. `start.sh` ile frontend'i baslat
2. MetaMask'i Monad Testnet'e bagla
3. Faucet'ten test MON al
4. UI'dan cuzdan bagla
5. MON yatir (Deposit)
6. Event olustur veya mevcut event'e bahis yap
7. Event kapandiktan sonra settlement bekle
8. Kazanciniz varsa Claim ile cek

## Teknik Detaylar

| Parametre         | Deger                |
|-------------------|----------------------|
| Solidity          | 0.8.24 (Cancun EVM) |
| Bahis penceresi   | 30-60 saniye         |
| Outcome sayisi    | 2-10                 |
| Min bahis         | 0.001 MON            |
| Max bahis         | 100 MON              |
| House fee         | %2 (200 bps)         |
| Shard sayisi      | 16                   |
| Paralel oran      | %93.75               |

## Lisans

MIT
