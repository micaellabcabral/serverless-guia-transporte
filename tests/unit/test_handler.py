import base64
import json

from hello_world import app


def evento(corpo, base64_=False):
    texto = json.dumps(corpo)
    if base64_:
        texto = base64.b64encode(texto.encode()).decode()
    return {"body": texto, "isBase64Encoded": base64_}


def setup_function():
    app.contador = 0


def test_cria_guia_com_201():
    r = app.lambda_handler(evento({"requisicaoId": "R-001", "hospital": "H-Recife",
                                   "bolsas": ["O-NEG-0142"]}), None)
    corpo = json.loads(r["body"])
    assert r["statusCode"] == 201
    assert corpo["guia"] == "G-R-001"
    assert corpo["bolsas"] == ["O-NEG-0142"]


def test_sem_requisicao_id_devolve_400():
    r = app.lambda_handler(evento({"hospital": "H-Recife"}), None)
    assert r["statusCode"] == 400


def test_corpo_em_base64():
    r = app.lambda_handler(evento({"requisicaoId": "R-009"}, base64_=True), None)
    assert json.loads(r["body"])["guia"] == "G-R-009"


def test_contador_cresce_no_mesmo_ambiente():
    app.lambda_handler(evento({"requisicaoId": "R-1"}), None)
    r = app.lambda_handler(evento({"requisicaoId": "R-2"}), None)
    assert json.loads(r["body"])["invocacaoNesteAmbiente"] == 2
