package br.com.oficina.integration;

import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.*;

import org.junit.jupiter.api.Test;

class FluxoCompletoOsIntegrationTest extends IntegrationTestBase {

  @Test
  void fluxoCompletoRecebidaAteEntregue() {
    String token = loginComoAdmin();

    // 1. Cadastrar cliente
    Long idCliente =
        given()
            .header("Authorization", "Bearer " + token)
            .contentType("application/json")
            .body(
                """
{"nome":"João Teste","documento":"52998224725","email":"joao@teste.com","telefone":"11999999999"}
""")
            .post("clientes")
            .then()
            .statusCode(201)
            .extract()
            .jsonPath()
            .getLong("idCliente");

    // 2. Cadastrar veículo
    given()
        .header("Authorization", "Bearer " + token)
        .contentType("application/json")
        .body(
            """
            {"placa":"ABC1234","marca":"Fiat","modelo":"Uno","ano":2020,"idCliente":%d}
            """
                .formatted(idCliente))
        .post("veiculos")
        .then()
        .statusCode(201);

    // 3. Cadastrar serviço
    Long idServico =
        given()
            .header("Authorization", "Bearer " + token)
            .contentType("application/json")
            .body(
                """
                {"nome":"Troca de óleo","descricao":"Troca completa","precoBase":150.00}
                """)
            .post("servicos")
            .then()
            .statusCode(201)
            .extract()
            .jsonPath()
            .getLong("idServico");

    // 4. Abrir OS
    String numeroOs =
        given()
            .header("Authorization", "Bearer " + token)
            .contentType("application/json")
            .body(
                """
                {"idCliente":%d,"placa":"ABC1234","descricaoProblema":"Barulho no motor"}
                """
                    .formatted(idCliente))
            .post("ordens-servico")
            .then()
            .statusCode(201)
            .body("status", equalTo("RECEBIDA"))
            .extract()
            .path("numero");

    given()
        .header("Authorization", "Bearer " + tokenCliente(idCliente + 999))
        .get("/consulta/ordens-servico/" + numeroOs + "/status")
        .then()
        .statusCode(404);

    // 5. Técnico adiciona serviço → EM_DIAGNOSTICO
    given()
        .header("Authorization", "Bearer " + token)
        .contentType("application/json")
        .body(
            """
            {"idServicoSku":%d,"quantidade":1}
            """
                .formatted(idServico))
        .post("/ordens-servico/" + numeroOs + "/servicos")
        .then()
        .statusCode(200)
        .body("status", equalTo("EM_DIAGNOSTICO"));

    // 6. Enviar para aprovação → AGUARDANDO_APROVACAO
    given()
        .header("Authorization", "Bearer " + token)
        .post("/ordens-servico/" + numeroOs + "/enviar-para-aprovacao")
        .then()
        .statusCode(200)
        .body("status", equalTo("AGUARDANDO_APROVACAO"));

    // 7. Cliente aprova → EM_EXECUCAO
    given()
        .header("Authorization", "Bearer " + tokenCliente(idCliente))
        .post("/ordens-servico/" + numeroOs + "/aprovar")
        .then()
        .statusCode(200)
        .body("status", equalTo("EM_EXECUCAO"));

    // 8. Técnico conclui reparo → AGUARDANDO_PAGAMENTO
    given()
        .header("Authorization", "Bearer " + token)
        .post("/ordens-servico/" + numeroOs + "/concluir-reparo")
        .then()
        .statusCode(200)
        .body("status", equalTo("AGUARDANDO_PAGAMENTO"));

    // 9. Cliente confirma pagamento → PAGA
    given()
        .header("Authorization", "Bearer " + tokenCliente(idCliente))
        .contentType("application/json")
        .body(
            """
            {"comprovante":"PIX-12345"}
            """)
        .post("/ordens-servico/" + numeroOs + "/confirmar-pagamento")
        .then()
        .statusCode(200)
        .body("status", equalTo("PAGA"));

    // 10. Técnico entrega → ENTREGUE
    given()
        .header("Authorization", "Bearer " + token)
        .post("/ordens-servico/" + numeroOs + "/entregar")
        .then()
        .statusCode(200)
        .body("status", equalTo("ENTREGUE"));

    given()
        .header("Authorization", "Bearer " + tokenCliente(idCliente))
        .get("/ordens-servico/" + numeroOs + "/historico")
        .then()
        .statusCode(200)
        .body("size()", equalTo(7))
        .body("[0].status", equalTo("RECEBIDA"))
        .body("[0].duracaoMilisegundos", notNullValue())
        .body("[0].correlationId", not(emptyOrNullString()))
        .body("[6].status", equalTo("ENTREGUE"));
  }
}
