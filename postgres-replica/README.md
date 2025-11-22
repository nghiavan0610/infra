<h3>1. Authenticate file: Postgres is running on the user 1001</h3>

```bash
sudo groupadd 1001
sudo useradd -r -g 1001 1001
sudo chown -R 1001:1001 persistence/
sudo chmod -R 777 persistence/
```

<h3>2. Create CA certificates</h3>

```bash
openssl genrsa -out ca.key 2048
openssl req -x509 -new -nodes -key ca.key -sha256 -days 1024 -out ca.pem -subj "/CN=postgres.benlab.site"
```

<h3>3. Create Server certificates</h3>

```bash
openssl genrsa -out postgres.key 2048
openssl req -new -key postgres.key -out postgres.csr -subj "/CN=postgres.benlab.site"
openssl x509 -req -in postgres.csr -CA ca.pem -CAkey ca.key -CAcreateserial -out postgres.crt -days 500 -sha256
cat postgres.key postgres.crt > postgres.pem
```

openssl req -new -text -passout pass:abcd -subj /CN=postgres.benlab.site -out server.req
openssl rsa -in privkey.pem -passin pass:abcd -out server.key
openssl req -x509 -in server.req -text -key server.key -out server.crt
