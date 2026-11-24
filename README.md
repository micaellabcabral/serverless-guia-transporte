# Atividade individual 1: Serverless (Rota Vital)

![Python](https://img.shields.io/badge/Python-3.12-3776AB?logo=python&logoColor=white)
![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?logo=gnubash&logoColor=white)

**Português** | [English](README.en.md)

Infraestrutura de Software · ADS · CESAR School · 2026.2 · Autora: Micaella Cabral

Uma função serverless que recebe uma requisição do Rota Vital e devolve a **guia de transporte**. Ela roda no computador com o **AWS SAM CLI**, sem conta na AWS e sem publicar nada na nuvem.

- **Caminho escolhido:** A (AWS SAM CLI local, Python 3.12, Docker Desktop).
- **Ambiente:** Windows com Docker Desktop 29.4.3, SAM CLI 1.174.0 e Python 3.12.10. Comandos rodados no Git Bash.
- **Evidências:** pasta [`evidencias/`](evidencias/), uma saída por comando, gravada pelo script `scripts/rodar-evidencias.sh` em 24/11/2026.

## Como rodar

```bash
export SAM_CLI_TELEMETRY=0
# Docker Desktop precisa estar aberto

# testes unitários do handler (não usam Docker)
python -m pytest tests/unit -v

# Passo 3: evento, build e invocação
sam local generate-event apigateway aws-proxy --method POST --path guias \
  --body '{"requisicaoId":"R-001","hospital":"H-Recife","bolsas":["O-NEG-0142"]}' > events/pedido.json
sam build
sam local invoke -e events/pedido.json

# Passo 4: HTTP (o curl vai em outro terminal)
sam local start-api            # depois: sam local start-api --warm-containers LAZY
curl -X POST http://127.0.0.1:3000/guias -H "Content-Type: application/json" \
  -d '{"requisicaoId":"R-002","hospital":"H-Caruaru"}'

# Passo 5: limite de tempo
curl -X POST http://127.0.0.1:3000/guias -H "Content-Type: application/json" \
  -d '{"requisicaoId":"R-003","demorar":true}'
```

Para repetir tudo de uma vez e regravar as evidências: `bash scripts/rodar-evidencias.sh`.

O projeto saiu do `sam init` (Hello World, Python 3.12, zip). No `template.yaml` troquei a rota de `/hello` (GET) para `/guias` (POST), e o `hello_world/app.py` é a função do enunciado. O `Timeout` do template está em **10**, porque o Passo 5 termina com esse ajuste. Para repetir o erro de tempo, volte `Timeout` para 3 e rode `sam build` de novo.

## O que mudou em relação ao enunciado

O `sam local generate-event` da versão 1.174 entrega o `body` codificado em base64 (`"isBase64Encoded": true`). O handler do enunciado lê o `body` direto, então com esse evento o `json.loads` falha. Acrescentei ao handler a decodificação quando `isBase64Encoded` é verdadeiro e um teste unitário para esse caso. Pelo HTTP (`start-api`) o corpo chega em texto e nada muda.

## Resultados medidos

| Experimento | Resultado | Tempo | Evidência |
|---|---|---|---|
| `sam local invoke`, 1ª vez | 201, guia `G-R-001`, contador 1, Duration 105,42 ms, Init 0,09 ms | 31,36 s no relógio (o SAM atualizou e montou a imagem Docker do runtime) | `04-invoke-1.txt` |
| `sam local invoke`, 2ª vez | 201, contador 1, Duration 113,66 ms, Init 0,11 ms | 5,80 s | `04-invoke-2.txt` |
| `start-api` sem opção, 3 chamadas | 201 nas três, contador 1, 2, 3 | 1,22 s, 1,14 s, 1,10 s | `05a-curl-sem-warm.txt` |
| `start-api --warm-containers LAZY`, 3 chamadas | 201 nas três, contador 1, 2, 3 | 3,71 s, 1,13 s, 1,09 s | `05b-curl-warm-lazy.txt` |
| `demorar: true`, Timeout 3 | HTTP 502 `{"message":"Internal server error"}`; o log diz `Function 'HelloWorldFunction' timed out after 3 seconds` | 4,22 s | `06a-curl-timeout3.txt` |
| `demorar: true`, Timeout 10 | 201, guia `G-R-003` | 6,19 s | `06c-curl-timeout10.txt` |

Testes unitários: 4 passaram (`01b-testes-unitarios.txt`).

## Perguntas

**1. Por que a primeira invocação demorou mais que a segunda? O que acontece na fase de Init?**

Antes de rodar o handler, o ambiente de execução precisa existir. Na fase de Init, o serviço prepara o container com o runtime do Python, carrega o código da função e executa tudo o que está fora do handler, como o `import` e a linha `contador = 0`. Esse custo é o *cold start*, e só acontece quando não há ambiente pronto. Na primeira execução do `sam local invoke` o relógio marcou 31,36 s contra 5,80 s da segunda, porque o SAM atualizou e montou a imagem Docker do runtime (o log mostra "Local image is out of date"). Esse tempo não é o `Duration` da função, que ficou em 105 ms e 114 ms. No `start-api` o efeito apareceu de forma mais limpa: com `--warm-containers LAZY` a primeira chamada levou 3,71 s, e as seguintes cerca de 1,1 s.

**2. O que o campo `invocacaoNesteAmbiente` mostrou com e sem `--warm-containers`? O que isso diz sobre guardar estado numa variável global da função?**

Nos dois modos o contador subiu 1, 2, 3, porque o mesmo container atendeu as três chamadas. A diferença foi quando o container nasceu. Sem a opção, o log mostra "Initializing the lambda functions containers" já na subida do servidor, e a primeira chamada levou 1,22 s. Com `LAZY`, o container só é criado quando chega a primeira requisição, e por isso ela levou 3,71 s. Já o `sam local invoke` cria um container novo a cada execução, e o contador ficou em 1 nas duas. Isso mostra que a variável global só sobrevive enquanto o ambiente é reaproveitado, e a nuvem não garante isso: o ambiente pode ser descartado, e várias chamadas ao mesmo tempo usam ambientes diferentes, cada um com o seu contador. Estado que importa tem que ficar fora da função, em um banco ou cache, e a variável global serve no máximo como cache descartável.

**3. O que aconteceu com `demorar = true`? Qual é o tempo máximo de uma execução no Lambda, e o que fazer com um trabalho mais longo?**

A função dorme 5 s e o template limita a execução a 3 s. O SAM interrompeu a função e o log registrou `Function 'HelloWorldFunction' timed out after 3 seconds`. Quem chamou recebeu HTTP 502 com `{"message":"Internal server error"}`, depois de 4,22 s. Com `Timeout: 10`, a mesma chamada voltou 201 em 6,19 s. No Lambda o limite máximo configurável é de 15 minutos (900 s). Um trabalho mais longo deve ser quebrado em etapas menores, por exemplo com uma fila ou o Step Functions, ou rodar em um serviço sem esse limite, como container no ECS/Fargate ou o AWS Batch.

**4. Com os preços de us-east-1 da aula, quanto custa um milhão de execuções desta função com 128 MB e 100 ms?**

- Requisições: 1.000.000 × US$ 0,20 por milhão = **US$ 0,20**.
- Computação: 128 MB = 128 / 1024 = 0,125 GB. Cada execução usa 0,125 GB × 0,1 s = 0,0125 GB-s. Em um milhão de execuções são 12.500 GB-s, e 12.500 × US$ 0,0000166667 ≈ **US$ 0,2083**.
- Total: 0,20 + 0,2083 ≈ **US$ 0,41** por milhão de execuções, sem contar a faixa gratuita.

**5. Em que parte do Rota Vital uma função assim faria sentido, e em qual não faria?**

Faz sentido onde o trabalho é curto, sem estado e disparado por evento. Um exemplo é gerar a guia de transporte quando uma requisição é aprovada, ou tratar a telemetria da cadeia fria e disparar um alerta quando a temperatura sai da faixa. Essas cargas aparecem em picos e ficam paradas no resto do tempo, e é aí que pagar só pela execução compensa. Não faria sentido no núcleo do estoque e na alocação por FEFO: ali as regras exigem transação no banco (PostgreSQL, via JDBC e pool de conexões) e baixa latência constante, e um cold start ou um ambiente descartado atrapalharia. A roteirização com Dijkstra também sofre por manter o grafo de rotas em memória, que é estado que a função perderia.

## Uso de IA

Seguindo a PO-CESAR-021, declaro o uso de IA nesta atividade.

- **Ferramenta:** Claude (Anthropic), pelo app do Claude.
- **Finalidade:** montar a estrutura do projeto a partir do `sam init`, escrever o script de evidências, os testes unitários e o rascunho deste README, e executar os comandos.
- **Como foi validado:** as saídas em `evidencias/` vêm de comandos que realmente rodaram, com Docker e SAM, e os números das tabelas e das respostas foram conferidos contra esses arquivos. A conta de custo usa os preços do enunciado e pode ser refeita à mão.
- **Onde rodou:** os comandos foram executados no notebook de um colega da equipe, que já tinha Docker e SAM instalados.
