package br.com.oficina.adapter.notification;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;

import br.com.oficina.usecase.gateway.ObservabilidadeGateway;
import ch.qos.logback.classic.Logger;
import ch.qos.logback.classic.spi.ILoggingEvent;
import ch.qos.logback.core.read.ListAppender;
import org.junit.jupiter.api.Test;
import org.slf4j.LoggerFactory;
import org.springframework.mail.MailSendException;
import org.springframework.mail.javamail.JavaMailSender;

class NotificacaoGatewayTest {

  @Test
  void notificacaoSimuladaNaoRegistraDadosPessoais() {
    Logger logger = (Logger) LoggerFactory.getLogger(LogNotificacaoGateway.class);
    ListAppender<ILoggingEvent> appender = new ListAppender<>();
    appender.start();
    logger.addAppender(appender);
    try {
      new LogNotificacaoGateway()
          .enviar(
              "cliente@example.com",
              "OS 2026-000001 — PAGA",
              "Cliente CPF 52998224725 teve a OS atualizada");
    } finally {
      logger.detachAppender(appender);
    }

    assertThat(appender.list).hasSize(1);
    assertThat(appender.list.getFirst().getFormattedMessage())
        .isEqualTo("Notificacao simulada processada")
        .doesNotContain("cliente@example.com", "52998224725", "2026-000001");
  }

  @Test
  void falhaSmtpGeraEventoTecnicoSemPropagarDadosPessoais() {
    JavaMailSender mailSender = mock(JavaMailSender.class);
    ObservabilidadeGateway observabilidade = mock(ObservabilidadeGateway.class);
    MailSendException falha = new MailSendException("falha para cliente@example.com");
    org.mockito.Mockito.doThrow(falha)
        .when(mailSender)
        .send(org.mockito.ArgumentMatchers.any(org.springframework.mail.SimpleMailMessage.class));
    SmtpNotificacaoGateway gateway =
        new SmtpNotificacaoGateway(mailSender, observabilidade, "nao-responder@oficina.local");

    gateway.enviar(
        "cliente@example.com", "OS 2026-000001", "CPF 52998224725 e outros dados privados");

    verify(observabilidade)
        .integracaoExternaFalhou("smtp", "enviar-notificacao", "MailSendException");
  }
}
