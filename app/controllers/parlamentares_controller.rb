class ParlamentaresController < ApplicationController
  PER_PAGE = 24

  def index
    resumo = Rails.cache.fetch("parlamentares/resumo_contadores", expires_in: 5.minutes) do
      {
        deputados: Parlamentar.where(casa: "camara").count,
        senadores: Parlamentar.where(casa: "senado").count,
        propostas: Proposta.count,
        ufs: Parlamentar.where.not(uf: [ nil, "" ]).distinct.order(:uf).pluck(:uf),
        partidos: Parlamentar.where.not(partido: [ nil, "" ]).distinct.order(:partido).pluck(:partido)
      }
    end

    @total_deputados = resumo[:deputados]
    @total_senadores = resumo[:senadores]
    @total_propostas = resumo[:propostas]
    @ufs = resumo[:ufs]
    @partidos = resumo[:partidos]

    escopo = Parlamentar.para_listagem
      .ordenados(params[:ordem])
      .por_casa(params[:casa])
      .por_uf(params[:uf])
      .por_partido(params[:partido])
      .busca_nome(params[:q])

    @total_filtrado = escopo.except(:select).count
    @pagina = [ params[:pagina].to_i, 1 ].max
    @total_paginas = (@total_filtrado.to_f / PER_PAGE).ceil
    @parlamentares = escopo.offset((@pagina - 1) * PER_PAGE).limit(PER_PAGE)
  end

  def show
    @parlamentar = Parlamentar.find(params[:id])
    sincronizar_parlamentar_se_necessario(@parlamentar)
    @parlamentar.reload
    carregar_propostas_do_parlamentar(@parlamentar)
    carregar_despesas_do_parlamentar(@parlamentar)
    carregar_votos_do_parlamentar(@parlamentar)
  end

  def propostas
    @parlamentar = Parlamentar.find(params[:id])
    sincronizar_parlamentar_se_necessario(@parlamentar)
    @parlamentar.reload
    carregar_propostas_do_parlamentar(@parlamentar)

    render partial: "parlamentares/propostas_frame", locals: {
      parlamentar: @parlamentar,
      propostas: @propostas,
      tipos_proposta: @tipos_proposta,
      total_propostas_parlamentar: @total_propostas_parlamentar
    }
  end

  def sincronizar
    @parlamentar = Parlamentar.find(params[:id])
    executar_sincronizacao_parlamentar(@parlamentar)
    Rails.cache.delete("parlamentares/resumo_contadores")
    redirect_to parlamentar_path(@parlamentar), notice: "Dados, gastos, votações e propostas de #{@parlamentar.nome} atualizados com sucesso!"
  end

  def sincronizar_todos
    camara = CamaraSyncService.new
    senado = SenadoSyncService.new

    dep_count = camara.sync_deputados
    sen_count = senado.sync_senadores
    Rails.cache.delete("parlamentares/resumo_contadores")

    redirect_to parlamentares_path, notice: "Sincronização concluída: #{dep_count} deputados e #{sen_count} senadores atualizados!"
  rescue StandardError => e
    redirect_to parlamentares_path, alert: "Erro ao sincronizar parlamentares: #{e.message}"
  end

  private

  def carregar_propostas_do_parlamentar(parlamentar)
    propostas_scope = parlamentar.propostas.recentes
      .por_tipo(params[:tipo])
      .busca_texto(params[:q])

    @tipos_proposta = parlamentar.propostas.distinct.order("propostas.sigla_tipo ASC").pluck("propostas.sigla_tipo")
    @total_propostas_parlamentar = propostas_scope.count
    @propostas = propostas_scope.limit(50)
  end

  def carregar_despesas_do_parlamentar(parlamentar)
    @despesas_por_categoria = parlamentar.despesas
      .group(:tipo_despesa)
      .order(Arel.sql("SUM(valor_liquido) DESC"))
      .sum(:valor_liquido)

    @despesas_recentes = parlamentar.despesas.recentes.limit(30)
  end

  def carregar_votos_do_parlamentar(parlamentar)
    @resumo_votos = parlamentar.votos_parlamentares.group(:tipo_voto).count
    @votos_recentes = parlamentar.votos_parlamentares.includes(:votacao).recentes.limit(40)
  end

  def sincronizar_parlamentar_se_necessario(parlamentar)
    precisa_detalhes = parlamentar.precisa_sincronizar_detalhes?
    precisa_propostas = parlamentar.propostas_count.zero? && parlamentar.precisa_sincronizar_propostas?
    precisa_despesas = parlamentar.despesas.empty? && parlamentar.precisa_sincronizar_despesas?
    precisa_votos = parlamentar.votos_count.zero? && parlamentar.precisa_sincronizar_votos?
    return unless precisa_detalhes || precisa_propostas || precisa_despesas || precisa_votos

    if parlamentar.deputado?
      service = CamaraSyncService.new
      service.sync_detalhes_deputado(parlamentar) if precisa_detalhes
      service.sync_propostas_deputado(parlamentar, limite: 40) if precisa_propostas
      service.sync_despesas_deputado(parlamentar, itens: 100) if precisa_despesas
      service.sync_votacoes_plenario_recentes(max_nominais: 10) if precisa_votos
    else
      service = SenadoSyncService.new
      service.sync_detalhes_senador(parlamentar) if precisa_detalhes
      service.sync_propostas_senador(parlamentar, limite: 40) if precisa_propostas
      service.sync_despesas_senador(parlamentar, limite: 100) if precisa_despesas
      service.sync_votacoes_senador(parlamentar, limite: 40) if precisa_votos
    end

    Rails.cache.delete("parlamentares/resumo_contadores")
  end

  def executar_sincronizacao_parlamentar(parlamentar)
    if parlamentar.deputado?
      service = CamaraSyncService.new
      service.sync_detalhes_deputado(parlamentar)
      service.sync_propostas_deputado(parlamentar, limite: 40)
      service.sync_despesas_deputado(parlamentar, itens: 100)
      service.sync_votacoes_plenario_recentes(max_nominais: 10)
    else
      service = SenadoSyncService.new
      service.sync_detalhes_senador(parlamentar)
      service.sync_propostas_senador(parlamentar, limite: 40)
      service.sync_despesas_senador(parlamentar, limite: 100)
      service.sync_votacoes_senador(parlamentar, limite: 40)
    end
  end
end
