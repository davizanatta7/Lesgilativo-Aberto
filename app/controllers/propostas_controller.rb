class PropostasController < ApplicationController
  PER_PAGE = 20

  def index
    escopo = montar_escopo_filtrado
    live_typing = request.headers["X-Live-Search"] == "1"

    if params[:q].present? || params[:tipo].present? || params[:ano].present?
      # Durante a digitação em tempo real, responde instantaneamente com o banco local;
      # só consulta as APIs externas se o usuário submeter (Enter/Buscar) ou se não houver nenhum resultado local após 4+ letras.
      deve_consultar_api = if live_typing
        escopo.count.zero? && params[:q].to_s.strip.length >= 4
      else
        escopo.count < 12
      end

      if deve_consultar_api
        buscar_propostas_ao_vivo_nas_apis
        escopo = montar_escopo_filtrado
      end
    end

    @tipos = Proposta.where.not(sigla_tipo: [ nil, "" ]).distinct.order(:sigla_tipo).pluck(:sigla_tipo)
    @anos = Proposta.where("ano IS NOT NULL AND ano > 0").distinct.order(ano: :desc).pluck(:ano)

    @total_filtrado = escopo.count
    @pagina = [ params[:pagina].to_i, 1 ].max
    @total_paginas = (@total_filtrado.to_f / PER_PAGE).ceil
    @propostas = escopo.offset((@pagina - 1) * PER_PAGE).limit(PER_PAGE)
  end

  def show
    @proposta = Proposta.includes(:parlamentares).find(params[:id])

    if @proposta.precisa_sincronizar_detalhes?
      executar_sincronizacao_proposta(@proposta)
      @proposta.reload
    end

    @votacoes = @proposta.votacoes.includes(votos_parlamentares: :parlamentar).recentes
  end

  def sincronizar
    @proposta = Proposta.find(params[:id])
    executar_sincronizacao_proposta(@proposta)
    redirect_to proposta_path(@proposta), notice: "Detalhes e votações da proposta #{@proposta.titulo} atualizados com sucesso!"
  end

  def sincronizar_recentes
    total_camara = CamaraSyncService.new.sync_propostas_recentes(itens_por_tipo: 35)
    total_senado = SenadoSyncService.new.sync_propostas_recentes(itens_por_tipo: 25)
    Rails.cache.delete("parlamentares/resumo_contadores")
    redirect_to propostas_path, notice: "#{total_camara + total_senado} propostas e projetos em tramitação sincronizados (Câmara: #{total_camara}, Senado: #{total_senado})!"
  rescue StandardError => e
    redirect_to propostas_path, alert: "Erro ao sincronizar propostas: #{e.message}"
  end

  private

  def montar_escopo_filtrado
    Proposta.includes(:parlamentares).recentes
      .por_casa(params[:casa])
      .por_tipo(params[:tipo])
      .por_ano(params[:ano])
      .busca_texto(params[:q])
  end

  def buscar_propostas_ao_vivo_nas_apis
    chave_cache = "propostas/busca_api/#{params[:casa]}/#{params[:tipo]}/#{params[:ano]}/#{params[:q].to_s.strip.downcase}"
    return if Rails.cache.read(chave_cache)

    Rails.cache.write(chave_cache, true, expires_in: 10.minutes)
    if params[:casa].blank? || params[:casa] == "camara"
      CamaraSyncService.new.buscar_propostas_api(
        termo: params[:q],
        sigla_tipo: params[:tipo],
        ano: params[:ano],
        limite: 30
      )
    end
    if params[:casa].blank? || params[:casa] == "senado"
      SenadoSyncService.new.buscar_propostas_api(
        termo: params[:q],
        sigla_tipo: params[:tipo],
        ano: params[:ano],
        limite: 20
      )
    end
    Rails.cache.delete("parlamentares/resumo_contadores")
  end

  def executar_sincronizacao_proposta(proposta)
    if proposta.casa == "camara"
      CamaraSyncService.new.sync_detalhes_proposta(proposta)
    else
      SenadoSyncService.new.sync_detalhes_proposta(proposta)
    end
  end
end
