**Deploying `my_server` to a cloud VM (Docker)**

Follow these steps to run the Node server in a cloud VM (DigitalOcean/AWS/Hetzner) so it can reach Supabase.

1) Prepare a VM and install Docker

Ubuntu example:
```bash
# on the remote VM
sudo apt update && sudo apt install -y docker.io docker-compose
sudo usermod -aG docker $USER
newgrp docker
```

2) Copy repository (or build locally and push image)

Option A — Build & run on the VM (quick):

```bash
# on the VM in a directory where you uploaded the my_server folder
cd my_server
# create a production env file with Supabase credentials
cat > .env.prod <<EOF
PORT=8080
API_SECRET_KEY=YOUR_API_SECRET_KEY
DB_HOST=db.qrotqdrpiampytdzakbm.supabase.co
DB_PORT=5432
DB_USER=postgres
DB_PASSWORD=YOUR_SUPABASE_DB_PASSWORD
DB_NAME=postgres
DB_SSL=true
EOF

# build and run
docker compose -f docker-compose.supabase.yml up -d --build
```

Option B — Build locally, push to Docker Hub, run on VM (preferred for CI):

```bash
# locally
docker build -t <dockerhub-username>/campus-bus-server:latest my_server
docker push <dockerhub-username>/campus-bus-server:latest

# on the VM
docker run -d --restart unless-stopped --env-file .env.prod -p 8080:8080 <dockerhub-username>/campus-bus-server:latest
```

3) Verify the service

From the VM:
```bash
curl -sS http://localhost:8080/api/health | jq
```

4) Troubleshooting
- If connection to Supabase fails, verify the values in `.env.prod` and network egress from the VM.
- Check container logs:
  `docker logs -f <container-id>`

5) Notes
- Keep `.env.prod` secret. Do not commit it to git.
- If you want automatic deploys, set up a CI pipeline to build and push the image on commit.

## Render deployment

If you are deploying the Node API to Render, set these environment variables in the Render dashboard or copy them from `.env.render.example`:

- `PORT=8080` or leave it unset and let Render provide the port
- `API_SECRET_KEY=<strong-random-secret>`
- `JWT_SECRET=<separate-strong-random-secret>`
- `DB_HOST=<your-supabase-host>`
- `DB_PORT=5432`
- `DB_USER=postgres`
- `DB_PASSWORD=<your-supabase-password>`
- `DB_NAME=postgres`
- `DB_SSL=true`

Render start command:

```bash
node server.js
```

If you prefer blueprint deploys, use [render.yaml](render.yaml) and set the secret env vars in Render.

After deploy, verify:

```bash
curl -sS https://nitmz-bus-tracker.onrender.com/api/health
```
