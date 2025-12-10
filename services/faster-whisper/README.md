# Faster-Whisper

Production-ready speech-to-text API using [faster-whisper](https://github.com/SYSTRAN/faster-whisper), providing OpenAI-compatible endpoints.

## Features

- OpenAI-compatible API (`/v1/audio/transcriptions`)
- 4x faster than original Whisper
- CPU and GPU support
- Multiple model sizes (tiny to large-v3)
- 99+ languages supported
- Word-level timestamps
- Translation to English
- Traefik integration with rate limiting

## Quick Start

```bash
cp .env.example .env
docker compose up -d

# Check health
curl http://localhost:8000/health
```

## Deployment Options

```bash
# CPU mode (default)
docker compose up -d

# GPU mode (NVIDIA)
docker compose --profile gpu up -d
```

## API Usage

### Transcription

```bash
# Basic
curl -X POST http://localhost:8000/v1/audio/transcriptions \
  -F "file=@audio.mp3"

# With language hint (faster)
curl -X POST http://localhost:8000/v1/audio/transcriptions \
  -F "file=@audio.mp3" \
  -F "language=vi"

# Get subtitles (SRT)
curl -X POST http://localhost:8000/v1/audio/transcriptions \
  -F "file=@video.mp4" \
  -F "response_format=srt" \
  -o subtitles.srt
```

### Translation (to English)

```bash
curl -X POST http://localhost:8000/v1/audio/translations \
  -F "file=@vietnamese_audio.mp3"
```

## Model Selection

| Model | RAM | Speed | Accuracy | Use Case |
|-------|-----|-------|----------|----------|
| tiny | 1GB | 32x | Low | Real-time, low resource |
| base | 1GB | 16x | Fair | Quick drafts |
| **small** | 2GB | 6x | Good | **CPU production** |
| medium | 5GB | 2x | High | Better accuracy |
| **large-v3** | 10GB | 1x | Best | **GPU production** |

## Traefik Integration

1. Update `.env`:
```bash
TRAEFIK_ENABLED=true
WHISPER_DOMAIN=whisper.yourdomain.com
```

2. Uncomment in docker-compose.yml:
```yaml
networks:
  - whisper-network
  - traefik-public  # Uncomment this

# And at the bottom:
networks:
  traefik-public:
    external: true
    name: traefik-public
```

3. Restart:
```bash
docker compose up -d
```

Access via: `https://whisper.yourdomain.com`

Rate limiting is configured: 10 requests/minute with burst of 5.

## GPU Setup (NVIDIA)

```bash
# Install NVIDIA Container Toolkit
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt update && sudo apt install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker

# Verify
docker run --rm --gpus all nvidia/cuda:12.0-base nvidia-smi

# Start GPU version
docker compose --profile gpu up -d
```

## Client Examples

### Python

```python
import requests

def transcribe(file_path: str, language: str = None) -> str:
    with open(file_path, "rb") as f:
        response = requests.post(
            "http://localhost:8000/v1/audio/transcriptions",
            files={"file": f},
            data={"language": language} if language else {}
        )
        return response.json()["text"]

# Usage
text = transcribe("audio.mp3", language="en")
```

### Using OpenAI SDK

```python
from openai import OpenAI

client = OpenAI(api_key="not-needed", base_url="http://localhost:8000/v1")

with open("audio.mp3", "rb") as f:
    result = client.audio.transcriptions.create(model="whisper-1", file=f)
    print(result.text)
```

## Supported Formats

**Audio:** MP3, WAV, M4A, OGG, FLAC, WebM, MP4

**Languages:** English, Vietnamese, Chinese, Japanese, Korean, Spanish, French, German, and 90+ more.

## Troubleshooting

```bash
# Check logs
docker compose logs -f faster-whisper

# Check resources
docker stats faster-whisper

# Out of memory? Use smaller model
WHISPER_MODEL=tiny
```

## File Structure

```
faster-whisper/
├── docker-compose.yml
├── .env.example
├── .gitignore
└── README.md
```
