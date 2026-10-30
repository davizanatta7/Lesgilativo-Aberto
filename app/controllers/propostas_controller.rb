class PropostasController < ApplicationController
  PER_PAGE = 20

  def index
    @tipos = Proposta.where.not(sigla_tipo: [ nil, "" ]).distinct.order(:sigla_tipo).pluck(:sigla_tipo)
    @anos = Proposta.where.not(ano: nil).distinct.order(ano: :desc).pluck(:ano)

    escopo = Proposta.includes(:parlamentares).recentes
      .por_casa(params[:casa])
      .por_tipo(params[:tipo])
      .por_ano(params[:ano])
      .busca_texto(params[:q])

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
    total = CamaraSyncService.new.sync_propostas_recentes(itens_por_tipo: 25)
    redirect_to propostas_path, notice: "#{total} propostas recentes sincronizadas da Câmara dos Deputados!"
  rescue StandardError => e
    redirect_to propostas_path, alert: "Erro ao sincronizar propostas: #{e.message}"
  end

  private

  def executar_sincronizacao_proposta(proposta)
    if proposta.casa == "camara"
      CamaraSyncService.new.sync_detalhes_proposta(proposta)
    else
      SenadoSyncService.new.sync_detalhes_proposta(proposta)
    end
  end
end
