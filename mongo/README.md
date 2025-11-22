<h3>1. First create a keyfile</h3>

```bash
openssl rand -base64 756 > keyfile
```

<h3>2. Secure MongoDB Connection TL/SSLS</h3>

<p>Sign CSR with root CA key</p>

```bash
openssl genrsa -out ca.key 2048
openssl req -x509 -new -nodes -key ca.key -sha256 -days 1024 -out ca.pem -subj "/CN=mongo.benlab.site"
```

<p>Create A Certificate (Done Once Per Device)</p>

```bash
openssl genrsa -out mongodb.key 2048
openssl req -new -key mongodb.key -out mongodb.csr -subj "/CN=mongo.benlab.site"
openssl x509 -req -in mongodb.csr -CA ca.pem -CAkey ca.key -CAcreateserial -out mongodb.crt -days 500 -sha256
cat mongodb.key mongodb.crt > mongodb.pem
```

<h3>3. Authenticate file: Mongodb is running on the user mongodb</h3>

```bash
sudo groupadd mongodb
sudo useradd -r -g mongodb mongodb
sudo chown -R mongodb:mongodb certs/
sudo find ./certs -type f -exec chmod 600 {} \;
```

<h3>4. DNS</h3>
<p>4 A records</p>
<p>3 SRV records</p>
<p>Optional: 1 TXT records</p>

<h4>4. Test Replica Set is Correctly Configured</h4>

```bash
docker exec -it mongo-primary mongosh -u ${MONGO_INITDB_ROOT_USERNAME} -p ${MONGO_INITDB_ROOT_PASSWORD} --authenticationDatabase admin
```
