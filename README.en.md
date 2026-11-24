# Individual Activity 1: Serverless (Rota Vital)

![Python](https://img.shields.io/badge/Python-3.12-3776AB?logo=python&logoColor=white)
![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?logo=gnubash&logoColor=white)

[Português](README.md) | **English**

Software Infrastructure · ADS · CESAR School · 2026.2 · Author: Micaella Cabral

A serverless function that receives a Rota Vital request and returns its **transport slip** (`guia de transporte`). It runs locally with the **AWS SAM CLI**, with no AWS account and nothing deployed to the cloud.

- **Path chosen:** A (local AWS SAM CLI, Python 3.12, Docker Desktop).
- **Environment:** Windows with Docker Desktop 29.4.3, SAM CLI 1.174.0 and Python 3.12.10, using Git Bash.
- **Evidence:** the [`evidencias/`](evidencias/) folder, one output file per command, written by `scripts/rodar-evidencias.sh` on 2026-11-24.

## How to run

```bash
export SAM_CLI_TELEMETRY=0
python -m pytest tests/unit -v
sam local generate-event apigateway aws-proxy --method POST --path guias \
  --body '{"requisicaoId":"R-001","hospital":"H-Recife","bolsas":["O-NEG-0142"]}' > events/pedido.json
sam build
sam local invoke -e events/pedido.json
sam local start-api            # then: sam local start-api --warm-containers LAZY
curl -X POST http://127.0.0.1:3000/guias -H "Content-Type: application/json" \
  -d '{"requisicaoId":"R-002","hospital":"H-Caruaru"}'
```

To rerun everything and regenerate the evidence: `bash scripts/rodar-evidencias.sh`. The template `Timeout` is set to **10**; set it back to 3 and run `sam build` to reproduce the timeout error.

## Change from the assignment

SAM CLI 1.174 generates the event `body` as base64 (`"isBase64Encoded": true`), so the assignment handler fails with `json.loads`. The handler now decodes the body when `isBase64Encoded` is true, with a unit test. Over HTTP (`start-api`) the body arrives as plain text.

## Measured results

| Experiment | Result | Time |
|---|---|---|
| `sam local invoke`, 1st | 201, `G-R-001`, counter 1, Duration 105.42 ms | 31.36 s wall clock (SAM refreshed and built the runtime image) |
| `sam local invoke`, 2nd | 201, counter 1, Duration 113.66 ms | 5.80 s |
| `start-api`, 3 calls | 201, counter 1, 2, 3 | 1.22 s, 1.14 s, 1.10 s |
| `start-api --warm-containers LAZY`, 3 calls | 201, counter 1, 2, 3 | 3.71 s, 1.13 s, 1.09 s |
| `demorar: true`, Timeout 3 | HTTP 502; log: `timed out after 3 seconds` | 4.22 s |
| `demorar: true`, Timeout 10 | 201, `G-R-003` | 6.19 s |

## Answers (summary; the full answers are in the Portuguese README)

1. **First call slower:** the Init phase prepares the runtime container, loads the code and runs everything outside the handler. That is the cold start. Locally, the first `invoke` also built the Docker runtime image.
2. **Counter:** it grew 1, 2, 3 in both modes. Without the option the container is created at startup; with `LAZY` it is created on the first request (3.71 s). `invoke` creates a new container each time (counter stays 1). Global variables survive only while the environment is reused, which the cloud does not guarantee, so state must live outside the function.
3. **Timeout:** the 5 s sleep exceeded the 3 s limit, giving HTTP 502. Lambda's maximum is 15 minutes; longer work goes to queues, Step Functions, ECS/Fargate or AWS Batch.
4. **Cost per million executions (128 MB, 100 ms):** requests 1,000,000 × US$ 0.20/million = US$ 0.20; compute 0.125 GB × 0.1 s × 1,000,000 = 12,500 GB-s × US$ 0.0000166667 ≈ US$ 0.2083; total ≈ **US$ 0.41**, before the free tier.
5. **In Rota Vital:** it fits event-driven, short, stateless work such as generating the transport slip or alerting on cold-chain telemetry. It does not fit the stock core and FEFO allocation (transactions, PostgreSQL connection pool, low latency) or Dijkstra routing (in-memory graph state).

## AI use

Per PO-CESAR-021: Claude (Anthropic) was used to scaffold the project from `sam init`, write the evidence script, the unit tests and the README draft, and to run the commands. The outputs in `evidencias/` come from commands that actually ran with Docker and SAM, and the numbers were checked against those files. The commands ran on a teammate's notebook that already had Docker and SAM installed.
