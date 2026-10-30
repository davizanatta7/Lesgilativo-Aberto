puts "==> Sincronizando dados das APIs da Câmara dos Deputados e do Senado Federal..."

begin
  camara = CamaraSyncService.new(logger: Logger.new($stdout))
  senado = SenadoSyncService.new(logger: Logger.new($stdout))

  dep_count = camara.sync_deputados
  sen_count = senado.sync_senadores
  prop_camara = camara.sync_propostas_recentes(itens_por_tipo: 30)
  prop_senado = senado.sync_propostas_recentes(itens_por_tipo: 20)
  vot_count = camara.sync_votacoes_plenario_recentes(max_nominais: 8)
  Rails.cache.delete("parlamentares/resumo_contadores")

  puts "Seeds concluído: #{dep_count} deputados, #{sen_count} senadores, #{prop_camara + prop_senado} propostas e #{vot_count} votações sincronizadas!"
rescue StandardError => e
  puts "Aviso: Não foi possível conectar às APIs externas durante o seed (#{e.message})."
  puts "Você pode sincronizar a qualquer momento pelo botão na tela inicial ou via `bin/rails legislativo:sync`."
end
