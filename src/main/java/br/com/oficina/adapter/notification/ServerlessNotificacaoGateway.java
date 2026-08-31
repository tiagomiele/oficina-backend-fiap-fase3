package br.com.oficina.adapter.notification;

import br.com.oficina.usecase.gateway.NotificacaoGateway;
import br.com.oficina.usecase.gateway.ObservabilidadeGateway;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;

@Service
@ConditionalOnProperty(name = "oficina.notificacao.tipo", havingValue = "serverless")
public class ServerlessNotificacaoGateway implements NotificacaoGateway {

  private static final Logger log = LoggerFactory.getLogger(ServerlessNotificacaoGateway.class);
  private static final String API_KEY_HEADER = "X-Notification-Key";

  private final RestClient client;
  private final ObservabilidadeGateway observabilidade;

  public ServerlessNotificacaoGateway(
      RestClient.Builder builder,
      ObservabilidadeGateway observabilidade,
      @Value("${oficina.notificacao.serverless.endpoint}") String endpoint,
      @Value("${oficina.notificacao.serverless.api-key}") String apiKey) {
    this.client = builder.baseUrl(endpoint).defaultHeader(API_KEY_HEADER, apiKey).build();
    this.observabilidade = observabilidade;
  }

  @Override
  public void enviar(String destinatario, String assunto, String corpo) {
    try {
      client
          .post()
          .contentType(MediaType.APPLICATION_JSON)
          .body(new NotificacaoRequest(destinatario, assunto, corpo))
          .retrieve()
          .toBodilessEntity();
      log.info("Notificacao serverless aceita para processamento");
    } catch (RestClientException ex) {
      observabilidade.integracaoExternaFalhou(
          "serverless-notification", "enfileirar-notificacao", ex.getClass().getSimpleName());
      log.error(
          "Falha na integracao serverless de notificacao: tipoErro={}",
          ex.getClass().getSimpleName());
    }
  }

  private record NotificacaoRequest(String destinatario, String assunto, String corpo) {}
}
