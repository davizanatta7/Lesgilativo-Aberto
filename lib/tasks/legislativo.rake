namespace :legislativo do
  desc "Sincroniza todos os deputados e senadores em exercício + propostas recentes"
  task sync: :environment do
    logger = Logger.new($stdout)
    camara = CamaraSyncService.new(logger: logger)
    senado = SenadoSyncService.new(logger: logger)

    puts "==> Sincronizando Deputados Federais (Câmara)..."
    dep_count = camara.sync_deputados

    puts "==> Sincronizando Senadores (Senado Federal)..."
    sen_count = senado.sync_senadores

    puts "==> Sincronizando Propostas recentes da Câmara e do Senado..."
    prop_camara = camara.sync_propostas_recentes(itens_por_tipo: 30)
    prop_senado = senado.sync_propostas_recentes(itens_por_tipo: 20)

    puts "==> Sincronizando propostas de amostra dos primeiros parlamentares..."
    Parlamentar.where(casa: "camara").limit(5).each do |dep|
      camara.sync_detalhes_deputado(dep)
      camara.sync_propostas_deputado(dep, limite: 15)
    end

    Parlamentar.where(casa: "senado").limit(5).each do |sen|
      senado.sync_detalhes_senador(sen)
      senado.sync_propostas_senador(sen, limite: 15)
    end

    puts "\nConcluído! #{dep_count} deputados, #{sen_count} senadores e #{Proposta.count} propostas no banco."
  end

  desc "Sincroniza detalhes e propostas de TODOS os parlamentares (pode levar alguns minutos)"
  task sync_propostas_todos: :environment do
    logger = Logger.new($stdout)
    camara = CamaraSyncService.new(logger: logger)
    senado = SenadoSyncService.new(logger: logger)

    total = Parlamentar.count
    Parlamentar.find_each.with_index(1) do |p, idx|
      puts "[#{idx}/#{total}] Sincronizando #{p.cargo_label} #{p.nome} (#{p.partido}-#{p.uf})..."
      if p.deputado?
        camara.sync_detalhes_deputado(p) if p.precisa_sincronizar_detalhes?
        camara.sync_propostas_deputado(p, limite: 30)
      else
        senado.sync_detalhes_senador(p) if p.precisa_sincronizar_detalhes?
        senado.sync_propostas_senador(p, limite: 30)
      end
    end
  end
end

