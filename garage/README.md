<h3>1. Secret Key File (Important)</h3>

```bash
chmod +x ./init-garage-key.sh

./init-garage-key.sh
```

<h3>2. Use that keys in garage.toml</h3>

<h3>3. Create a cluster layout</h3>

Get <node-id>

```bash
docker exec -it garage /garage status
```

Init cluster layout

```bash
docker exec -it garage /garage layout assign --zone dc1 --capacity 10G <node-id>

docker exec -it garage /garage layout apply --version 1
```

<h3>4. Create bucket and access key</h3>

Create an access key

```bash
docker exec -it garage /garage key create brandmate-file-key
```

Create a bucket (private)

```bash
docker exec -it garage /garage bucket create brandmate-file
```

Delete a bucket

```bash
docker exec -it garage /garage bucket delete brandmate-file --yes
```

Allow the key to access the bucket

```bash
docker exec -it garage /garage bucket allow \
  --read \
  --write \
  --owner \
  brandmate-file \
  --key brandmate-file-key
```

Create a bucket (public)

```bash
docker exec -it garage /garage bucket create brandmate-public
```

Allow public read access to public bucket

```bash
docker exec -it garage /garage bucket allow \
  --read \
  --write \
  --owner \
  brandmate-public \
  --key brandmate-file-key
```

Configure public bucket for web access

```bash
docker exec -it garage /garage bucket website --allow brandmate-public
```
