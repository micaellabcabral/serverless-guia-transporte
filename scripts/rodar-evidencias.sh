#!/usr/bin/env bash
# Roda os Passos 3 a 5 do enunciado e grava a saída de cada comando em evidencias/.
# Pré-requisitos: Docker Desktop aberto, sam no PATH, Python 3.12. Rodar no Git Bash, na raiz do projeto.
export SAM_CLI_TELEMETRY=0
export MSYS_NO_PATHCONV=1
cd "$(dirname "$0")/.." || exit 1
mkdir -p evidencias events

EV=evidencias
URL=http://127.0.0.1:3000/guias
JSON='Content-Type: application/json'

cab() { echo "\$ $*"; }
chamada() {  # chamada <corpo>
  cab "curl -X POST $URL -H \"$JSON\" -d '$1'"
  curl -s -X POST "$URL" -H "$JSON" -d "$1" -w "\nHTTP %{http_code} | tempo %{time_total}s\n"
  echo
}
sobe_api() {  # sobe_api <log> [opcoes]
  local log=$1; shift
  sam local start-api "$@" > "$log" 2>&1 &
  API_PID=$!
  for i in $(seq 1 60); do grep -q "Running on" "$log" && break; sleep 1; done
  sleep 1
}
derruba_api() {
  taskkill //F //IM sam.exe > /dev/null 2>&1
  kill "$API_PID" 2>/dev/null
  sleep 3
}

# Passo 1: versões
{ cab "sam --version"; sam --version; cab "docker --version"; docker --version; cab "python --version"; python --version; } > $EV/01-versoes.txt 2>&1

# testes unitários
{ cab "python -m pytest tests/unit -v"; python -m pytest tests/unit -v; } > $EV/01b-testes-unitarios.txt 2>&1

# Passo 3: gerar evento, build e duas invocações
{ cab "sam local generate-event apigateway aws-proxy --method POST --path guias --body '{...}' > events/pedido.json"
  sam local generate-event apigateway aws-proxy --method POST --path guias \
    --body '{"requisicaoId":"R-001","hospital":"H-Recife","bolsas":["O-NEG-0142"]}' > events/pedido.json
  echo "(evento gravado em events/pedido.json)"; } > $EV/02-generate-event.txt 2>&1
{ cab "sam build"; sam build; } > $EV/03-sam-build.txt 2>&1
for n in 1 2; do
  { cab "sam local invoke -e events/pedido.json   # execução $n"
    start=$(date +%s.%N)
    sam local invoke -e events/pedido.json
    fim=$(date +%s.%N)
    echo; echo "tempo no relógio: $(python -c "print(round($fim-$start,2))") s"
  } > $EV/04-invoke-$n.txt 2>&1
done

# Passo 4: start-api sem e com --warm-containers LAZY
sobe_api $EV/05-start-api-sem-warm.log
{ for i in 1 2 3; do chamada '{"requisicaoId":"R-002","hospital":"H-Caruaru"}'; done; } > $EV/05a-curl-sem-warm.txt 2>&1
derruba_api
sobe_api $EV/05-start-api-warm.log --warm-containers LAZY
{ for i in 1 2 3; do chamada '{"requisicaoId":"R-002","hospital":"H-Caruaru"}'; done; } > $EV/05b-curl-warm-lazy.txt 2>&1
derruba_api

# Passo 5: limite de tempo (Timeout 3) e depois 10
sobe_api $EV/06-start-api-timeout3.log
{ chamada '{"requisicaoId":"R-003","demorar":true}'; } > $EV/06a-curl-timeout3.txt 2>&1
derruba_api
sed -i 's/Timeout: 3/Timeout: 10/' template.yaml
{ cab "sam build  # Timeout alterado para 10"; sam build; } > $EV/06b-sam-build-timeout10.txt 2>&1
sobe_api $EV/06-start-api-timeout10.log
{ chamada '{"requisicaoId":"R-003","demorar":true}'; } > $EV/06c-curl-timeout10.txt 2>&1
derruba_api
echo "pronto"
