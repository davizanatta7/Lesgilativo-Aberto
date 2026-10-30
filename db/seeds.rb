puts "==> Sincronizando dados das APIs da Câmara dos Deputados e do Senado Federal..."

begin
  camara = CamaraSyncService.new(logger: Logger.new($stdout))
  senado = SenadoSyncService.new(logger: Logger.new($stdout))

  dep_count = camara.sync_deputados
  sen_count = senado.sync_senadores
  prop_count = camara.sync_propostas_recentes(itens_por_tipo: 20)

  puts "Seeds concluído: #{dep_count} deputados, #{sen_count} senadores e #{prop_count} propostas sincronizadas!"
rescue StandardError => e
  puts "Aviso: Não foi possível conectar às APIs externas durante o seed (#{e.message})."
  puts "Você pode sincronizar a qualquer momento pelo botão na tela inicial ou via `bin/rails legislativo:sync`."
end
