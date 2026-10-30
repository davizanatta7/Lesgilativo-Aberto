class LegislativoSyncJob < ApplicationJob
  queue_as :default

  def perform(escopo: "parlamentares", parlamentar_id: nil, proposta_id: nil)
    camara = CamaraSyncService.new
    senado = SenadoSyncService.new

    case escopo.to_s
    when "parlamentares"
      camara.sync_deputados
      senado.sync_senadores
    when "tudo"
      camara.sync_deputados
      senado.sync_senadores
      camara.sync_propostas_recentes
      senado.sync_propostas_recentes
    when "parlamentar"
      parlamentar = Parlamentar.find_by(id: parlamentar_id)
      return unless parlamentar

      if parlamentar.deputado?
        camara.sync_detalhes_deputado(parlamentar)
        camara.sync_propostas_deputado(parlamentar)
      else
        senado.sync_detalhes_senador(parlamentar)
        senado.sync_propostas_senador(parlamentar)
      end
    when "proposta"
      proposta = Proposta.find_by(id: proposta_id)
      return unless proposta

      if proposta.casa == "camara"
        camara.sync_detalhes_proposta(proposta)
      else
        senado.sync_detalhes_proposta(proposta)
      end
    end
  end
end

