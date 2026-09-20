# Private Workspace

Samostalna Docker aplikacija za privatni server: frontend, backend, PostgreSQL baza, zajednički file storage, kanban/task manager i obavijesti kod tagiranja korisnika.

## Što je uključeno

- Web aplikacija na `http://server:8080`
- FastAPI backend iza `/api`
- PostgreSQL baza u Docker volumenu
- Lokalni file storage u Docker volumenu
- Više korisnika s prijavom i registracijom
- Kanban ploče, kolone, taskovi, dodjela taska i tagiranje preko `@korisnicko_ime`
- Interna lista obavijesti za svakog korisnika
- Self-hosted `ntfy` servis za Android/UnifiedPush scenarij

## Važna napomena o mobilnim notifikacijama

Potpuno privatne mobilne notifikacije ovise o uređaju:

- Android: izvedivo uz self-hosted `ntfy` ili UnifiedPush kompatibilnu aplikaciju.
- iPhone: pravi push bez Apple APNs-a nije realno izvediv za standardne aplikacije ili PWA. Aplikacija i dalje bilježi interne obavijesti, ali native iOS push bi koristio Appleovu infrastrukturu.

## Pokretanje na privatnom serveru

1. Instaliraj Docker i Docker Compose plugin.
2. Kopiraj ovaj direktorij na server.
3. U `docker-compose.yml` promijeni lozinku baze i `JWT_SECRET`.
4. Pokreni:

```bash
docker compose up -d --build
```

5. Ako koristiš server compose, pripremi direktorije:

```bash
mkdir -p /mnt/docker/apps/aplikacija/data/postgres
mkdir -p /mnt/docker/apps/aplikacija/data/ntfy
mkdir -p /mnt/nas/aplikacija
```

6. Otvori:

```text
http://IP_ADRESA_SERVERA:8080
```

## Mobilne obavijesti preko ntfy

`ntfy` je izložen na portu `8081`.

1. Na Android instaliraj ntfy aplikaciju.
2. Pretplati se na privatni topic, npr. `branko-private-123`.
3. U web aplikaciji otvori `Postavke` i upiši isti topic.
4. Kada te drugi korisnik tagira u tasku, npr. `@branko`, backend šalje internu obavijest i ntfy poruku.

## Produkcijske preporuke

- Promijeni `POSTGRES_PASSWORD` i `JWT_SECRET`.
- Stavi aplikaciju iza lokalnog reverse proxyja s HTTPS certifikatom.
- Ograniči pristup portovima firewallom.
- Redovito backupiraj Docker volume `postgres_data` i `uploaded_files`.
- Ako server nije dostupan izvan kućne mreže, mobilne notifikacije će raditi samo dok je uređaj u istoj mreži ili preko VPN-a.

## Server putanje

Konačna server varijanta koristi:

```text
/mnt/docker/apps/aplikacija     root folder aplikacije
/mnt/nas/aplikacija             file storage za uploadane datoteke
```

Frontend je izložen na portu `9999`.

## Struktura

```text
backend/   FastAPI aplikacija i API
frontend/  statički web klijent poslužen kroz nginx
docker-compose.yml
```
