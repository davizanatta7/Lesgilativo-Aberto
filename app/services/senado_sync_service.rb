require "net/http"
require "json"
require "uri"
require "digest"

class SenadoSyncService
  BASE_URL = "https://legis.senado.leg.br/dadosabertos"
  ADM_BASE_URL = "https://adm.senado.gov.br/adm-dadosabertos/api/v1"

  def initialize(logger: Rails.logger)
    @logger = logger
  end

  # Sincroniza a lista de todos os senadores em exercício
  def sync_senadores
    @logger.info "[SenadoSync] Buscando lista de senadores em exercício..."
    resp = get_json("/senador/lista/atual.json")
    lista = resp&.dig("ListaParlamentarEmExercicio", "Parlamentares", "Parlamentar")
    parlamentares_raw = wrap_array(lista)
    count = 0

    parlamentares_raw.each do |item|
      ident = item["IdentificacaoParlamentar"] || {}
      codigo = ident["CodigoParlamentar"]&.to_s
      next if codigo.blank?

      telefones = wrap_array(ident.dig("Telefones", "Telefone"))
      primeiro_telefone = telefones.first&.dig("NumeroTelefone")

      parlamentar = Parlamentar.find_or_initialize_by(
        casa: "senado",
        external_id: codigo
      )
      parlamentar.assign_attributes(
        nome: ident["NomeParlamentar"].presence || ident["NomeCompletoParlamentar"],
        nome_civil: ident["NomeCompletoParlamentar"],
        partido: ident["SiglaPartidoParlamentar"],
        uf: ident["UfParlamentar"],
        foto_url: normalize_url(ident["UrlFotoParlamentar"]),
        email: ident["EmailParlamentar"].presence || parlamentar.email,
        telefone: primeiro_telefone.presence || parlamentar.telefone,
        url_website: ident["UrlPaginaParticular"].presence || ident["UrlPaginaParlamentar"],
        situacao: "Exercício"
      )
      parlamentar.save!
      count += 1
    end

    @logger.info "[SenadoSync] #{count} senadores sincronizados com sucesso."
    count
  end

  # Sincroniza detalhes biográficos de um senador
  def sync_detalhes_senador(parlamentar)
    return unless parlamentar.senador?

    resp = get_json("/senador/#{parlamentar.external_id}.json")
    dados = resp&.dig("DetalheParlamentar", "Parlamentar")
    return unless dados

    ident = dados["IdentificacaoParlamentar"] || {}
    basicos = dados["DadosBasicosParlamentar"] || {}
    telefones = wrap_array(ident.dig("Telefones", "Telefone"))
    primeiro_telefone = telefones.first&.dig("NumeroTelefone")

    redes = Array(parlamentar.redes_sociais).dup
    [ ident["UrlPaginaParticular"], ident["UrlPaginaParlamentar"] ].compact_blank.each do |u|
      redes << u unless redes.include?(u)
    end

    parlamentar.update!(
      nome: ident["NomeParlamentar"].presence || parlamentar.nome,
      nome_civil: ident["NomeCompletoParlamentar"].presence || parlamentar.nome_civil,
      partido: ident["SiglaPartidoParlamentar"].presence || parlamentar.partido,
      uf: ident["UfParlamentar"].presence || parlamentar.uf,
      foto_url: normalize_url(ident["UrlFotoParlamentar"]).presence || parlamentar.foto_url,
      email: ident["EmailParlamentar"].presence || parlamentar.email,
      telefone: primeiro_telefone.presence || parlamentar.telefone,
      data_nascimento: parse_date(basicos["DataNascimento"]),
      municipio_nascimento: basicos["Naturalidade"],
      uf_nascimento: basicos["UfNaturalidade"],
      gabinete_sala: basicos["EnderecoParlamentar"],
      url_website: ident["UrlPaginaParticular"].presence || ident["UrlPaginaParlamentar"].presence || parlamentar.url_website,
      redes_sociais: redes.uniq,
      dados_sincronizados_em: Time.current
    )
    parlamentar
  rescue StandardError => e
    @logger.error "[SenadoSync] Erro ao sincronizar detalhes do senador #{parlamentar.external_id}: #{e.message}"
    parlamentar
  end

  # Sincroniza despesas da Cota dos Senadores (CEAPS)
  def sync_despesas_senador(parlamentar, limite: 100)
    return [] unless parlamentar.senador?

    nome_alvo = normalize_name(parlamentar.nome)
    despesas_raw = []

    [ 2025, 2024 ].each do |ano|
      lista_ano = fetch_ceaps_ano(ano)
      next if lista_ano.blank?

      do_senador = lista_ano.select do |item|
        normalize_name(item["nomeSenador"].to_s) == nome_alvo ||
          item["codSenador"]&.to_s == parlamentar.external_id
      end

      if do_senador.any?
        despesas_raw = do_senador
        break
      end
    end

    despesas_sincronizadas = []
    despesas_raw.first(limite).each do |item|
      valor_str = item["valorReembolsado"].to_s.tr(",", ".")
      valor = valor_str.to_f
      next if valor <= 0

      doc_id = (item["id"].presence || Digest::SHA1.hexdigest("#{item['ano']}-#{item['mes']}-#{item['documento']}-#{item['cpfCnpj']}-#{valor}")[0, 16]).to_s

      despesa = Despesa.find_or_initialize_by(
        parlamentar: parlamentar,
        external_doc_id: doc_id
      )
      despesa.assign_attributes(
        ano: item["ano"].to_i,
        mes: item["mes"].to_i,
        tipo_despesa: item["tipoDespesa"].to_s.strip,
        fornecedor: item["fornecedor"],
        cnpj_cpf_fornecedor: item["cpfCnpj"],
        valor_liquido: valor,
        data_documento: parse_date(item["data"]),
        numero_documento: item["documento"]
      )
      despesa.save!
      despesas_sincronizadas << despesa
    end

    parlamentar.update_columns(
      total_despesas: parlamentar.despesas.sum(:valor_liquido),
      despesas_sincronizadas_em: Time.current
    )
    despesas_sincronizadas
  rescue StandardError => e
    @logger.error "[SenadoSync] Erro ao sincronizar despesas do senador #{parlamentar.external_id}: #{e.message}"
    []
  end

  # Sincroniza as propostas/matérias de autoria de um senador
  def sync_propostas_senador(parlamentar, limite: 50)
    return [] unless parlamentar.senador?

    propostas_sincronizadas = sync_via_endpoint_processo(parlamentar, limite: limite)
    if propostas_sincronizadas.empty?
      propostas_sincronizadas = sync_via_endpoint_autorias(parlamentar, limite: limite)
    end

    parlamentar.update_column(:propostas_sincronizadas_em, Time.current)
    propostas_sincronizadas
  rescue StandardError => e
    @logger.error "[SenadoSync] Erro ao sincronizar propostas do senador #{parlamentar.external_id}: #{e.message}"
    []
  end

  # Sincroniza o histórico de votações nominais de um senador
  def sync_votacoes_senador(parlamentar, limite: 40)
    return 0 unless parlamentar.senador?

    salvas = sync_votacoes_via_endpoint_moderno(parlamentar, limite: limite)
    if salvas.zero?
      salvas = sync_votacoes_via_endpoint_classico(parlamentar, limite: limite)
    end

    parlamentar.update_columns(
      votos_count: parlamentar.votos_parlamentares.count,
      votos_sincronizados_em: Time.current
    )
    salvas
  rescue StandardError => e
    @logger.error "[SenadoSync] Erro ao sincronizar votações do senador #{parlamentar.external_id}: #{e.message}"
    0
  end

  # Sincroniza detalhes completos de uma matéria do Senado
  def sync_detalhes_proposta(proposta)
    return unless proposta.casa == "senado"

    resp = get_json("/materia/#{proposta.external_id}.json")
    materia = resp&.dig("DetalheMateria", "Materia")
    return unless materia

    ident = materia["IdentificacaoMateria"] || {}
    basicos = materia["DadosBasicosMateria"] || {}
    autuacoes = wrap_array(materia.dig("SituacaoAtual", "Autuacoes", "Autuacao"))
    autuacao_atual = autuacoes.first || {}
    situacao = autuacao_atual["Situacao"] || {}
    local = autuacao_atual["Local"] || {}

    url_texto = fetch_url_texto_materia(proposta.external_id)

    proposta.update!(
      sigla_tipo: ident["SiglaSubtipoMateria"].presence || ident["SiglaCasaIdentificacaoMateria"].presence || proposta.sigla_tipo,
      descricao_tipo: ident["DescricaoSubtipoMateria"].presence || proposta.descricao_tipo,
      numero: ident["NumeroMateria"]&.to_i&.to_s.presence || ident["NumeroMateria"].presence || proposta.numero,
      ano: ident["AnoMateria"]&.to_i || proposta.ano,
      ementa: basicos["EmentaMateria"].presence || proposta.ementa,
      ementa_detalhada: basicos["ExplicacaoEmentaMateria"].presence || proposta.ementa_detalhada,
      keywords: basicos["IndexacaoMateria"].presence || proposta.keywords,
      data_apresentacao: parse_date(basicos["DataApresentacao"]) || proposta.data_apresentacao,
      status_situacao: situacao["DescricaoSituacao"].presence || proposta.status_situacao,
      status_orgao: local["SiglaLocal"].presence || local["NomeLocal"].presence || proposta.status_orgao,
      url_inteiro_teor: url_texto.presence || proposta.url_inteiro_teor,
      detalhes_sincronizados_em: Time.current
    )
    proposta
  rescue StandardError => e
    @logger.error "[SenadoSync] Erro ao sincronizar detalhes da matéria #{proposta.external_id}: #{e.message}"
    proposta
  end

  private

  def fetch_ceaps_ano(ano)
    Rails.cache.fetch("senado/ceaps/#{ano}", expires_in: 6.hours) do
      uri = URI("#{ADM_BASE_URL}/senadores/despesas_ceaps/#{ano}")
      req = Net::HTTP::Get.new(uri)
      req["Accept"] = "application/json"
      req["User-Agent"] = "LegislativoApp/1.0 (Ruby on Rails)"

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 8
      http.read_timeout = 20

      res = http.request(req)
      res.is_a?(Net::HTTPSuccess) ? JSON.parse(res.body) : []
    end
  rescue StandardError => e
    @logger.warn "[SenadoSync] Não foi possível baixar CEAPS #{ano}: #{e.message}"
    []
  end

  def normalize_name(str)
    I18n.transliterate(str.to_s).upcase.gsub(/[^A-Z0-9 ]/, "").squeeze(" ").strip
  end

  def sync_via_endpoint_processo(parlamentar, limite: 50)
    resp = get_json("/processo", { codigoParlamentarAutor: parlamentar.external_id })
    return [] unless resp.is_a?(Array)

    propostas = []
    resp.first(limite).each do |item|
      codigo_materia = (item["codigoMateria"] || item["id"])&.to_s
      next if codigo_materia.blank?

      identificacao = item["identificacao"].to_s
      sigla, num_ano = identificacao.split(" ", 2)
      numero, ano = num_ano.to_s.split("/")

      proposta = Proposta.find_or_initialize_by(casa: "senado", external_id: codigo_materia)
      proposta.assign_attributes(
        sigla_tipo: sigla.presence || item["sigla"] || "MAT",
        descricao_tipo: item["tipoConteudo"],
        numero: numero.presence || item["numero"]&.to_s,
        ano: (ano.presence || item["ano"])&.to_i,
        ementa: item["ementa"].presence || proposta.ementa,
        data_apresentacao: parse_date(item["dataApresentacao"]) || proposta.data_apresentacao,
        status_situacao: item["tramitando"] == "Sim" ? "Em tramitação" : (proposta.status_situacao || "Tramitação encerrada")
      )
      proposta.save!
      Autoria.find_or_create_by!(parlamentar: parlamentar, proposta: proposta)
      propostas << proposta
    end

    propostas
  rescue StandardError => e
    @logger.warn "[SenadoSync] Fallback para autorias (endpoint /processo falhou: #{e.message})"
    []
  end

  def sync_via_endpoint_autorias(parlamentar, limite: 50)
    resp = get_json("/senador/#{parlamentar.external_id}/autorias.json")
    autorias_raw = wrap_array(resp&.dig("MateriasAutoriaParlamentar", "Parlamentar", "Autorias", "Autoria"))

    autorias_ordenadas = autorias_raw.sort_by do |a|
      ano = a.dig("Materia", "Ano").to_i
      codigo = a.dig("Materia", "Codigo").to_i
      [ -ano, -codigo ]
    end

    propostas = []
    autorias_ordenadas.first(limite).each do |autoria_item|
      mat = autoria_item["Materia"] || {}
      codigo = mat["Codigo"]&.to_s
      next if codigo.blank?

      proposta = Proposta.find_or_initialize_by(casa: "senado", external_id: codigo)
      proposta.assign_attributes(
        sigla_tipo: mat["Sigla"].presence || "MAT",
        descricao_tipo: mat["DescricaoSubtipo"],
        numero: mat["Numero"]&.to_i&.to_s.presence || mat["Numero"],
        ano: mat["Ano"]&.to_i,
        ementa: mat["Ementa"].presence || proposta.ementa,
        data_apresentacao: parse_date(mat["Data"]) || proposta.data_apresentacao
      )
      proposta.save!
      Autoria.find_or_create_by!(parlamentar: parlamentar, proposta: proposta)
      propostas << proposta
    end

    propostas
  end

  def fetch_url_texto_materia(codigo_materia)
    resp = get_json("/materia/textos/#{codigo_materia}.json")
    textos = wrap_array(resp&.dig("TextoMateria", "Materia", "Textos", "Texto"))
    textos.first&.dig("UrlTexto")
  rescue StandardError
    nil
  end

  def sync_votacoes_via_endpoint_moderno(parlamentar, limite: 40)
    resp = get_json("/votacao", { codigoParlamentar: parlamentar.external_id })
    return 0 unless resp.is_a?(Array) && resp.any?

    salvas = 0
    resp.sort_by { |v| v["dataSessao"].to_s }.reverse.first(limite).each do |item|
      vot_id = (item["codigoSessaoVotacao"] || item["sequencialSessao"] || item["id"])&.to_s
      next if vot_id.blank?

      votos_lista = Array(item["votos"])
      meu_voto_obj = votos_lista.find { |v| v["codigoParlamentar"]&.to_s == parlamentar.external_id } || votos_lista.first
      sigla_voto = meu_voto_obj&.dig("siglaVotoParlamentar").presence || meu_voto_obj&.dig("descricaoVotoParlamentar")
      next if sigla_voto.blank?

      aprovacao = case item["resultadoVotacao"].to_s.upcase
      when "A" then 1
      when "R" then 0
      else nil
      end

      proposta_vinc = if item["codigoMateria"].present?
        Proposta.find_by(casa: "senado", external_id: item["codigoMateria"].to_s)
      end

      votacao = Votacao.find_or_initialize_by(casa: "senado", external_id: vot_id)
      votacao.assign_attributes(
        proposta: proposta_vinc || votacao.proposta,
        proposta_identificacao: item["identificacao"].presence || votacao.proposta_identificacao,
        orgao: "Plenário do Senado",
        data: parse_datetime(item["dataSessao"]),
        descricao: item["descricaoVotacao"].presence || item["ementa"],
        aprovacao: aprovacao,
        votos_sim: item["totalVotosSim"].to_i,
        votos_nao: item["totalVotosNao"].to_i,
        votos_outros: item["totalVotosAbstencao"].to_i
      )
      votacao.save!

      voto_p = VotoParlamentar.find_or_initialize_by(votacao: votacao, parlamentar: parlamentar)
      voto_p.assign_attributes(
        tipo_voto: normalizar_tipo_voto(sigla_voto),
        partido_na_votacao: meu_voto_obj&.dig("siglaPartidoParlamentar") || parlamentar.partido,
        uf_na_votacao: meu_voto_obj&.dig("ufParlamentar") || parlamentar.uf
      )
      voto_p.save!
      salvas += 1
    end

    salvas
  rescue StandardError => e
    @logger.warn "[SenadoSync] Fallback para votações clássicas (#{e.message})"
    0
  end

  def sync_votacoes_via_endpoint_classico(parlamentar, limite: 40)
    resp = get_json("/senador/#{parlamentar.external_id}/votacoes.json")
    votacoes_raw = wrap_array(resp&.dig("VotacaoParlamentar", "Parlamentar", "Votacoes", "Votacao"))
    return 0 if votacoes_raw.empty?

    salvas = 0
    votacoes_raw.reverse.first(limite).each do |item|
      sessao = item["SessaoPlenaria"] || {}
      materia = item["Materia"] || {}
      vot_id = (item["CodigoSessaoVotacao"] || "#{sessao['CodigoSessao']}-#{materia['Codigo']}")&.to_s
      next if vot_id.blank?

      sigla_voto = item["SiglaDescricaoVoto"].presence || item["DescricaoVoto"]
      next if sigla_voto.blank?

      ident_mat = [ materia["Sigla"], [ materia["Numero"]&.to_i, materia["Ano"] ].compact.join("/") ].compact_blank.join(" ")
      aprovacao = if item["DescricaoResultado"].to_s.match?(/aprovad/i)
        1
      elsif item["DescricaoResultado"].to_s.match?(/rejeitad/i)
        0
      end

      votacao = Votacao.find_or_initialize_by(casa: "senado", external_id: vot_id)
      votacao.assign_attributes(
        proposta_identificacao: ident_mat.presence || votacao.proposta_identificacao,
        orgao: "Plenário do Senado",
        data: parse_datetime(sessao["DataSessao"]),
        descricao: item["DescricaoVotacao"],
        aprovacao: aprovacao
      )
      votacao.save!

      voto_p = VotoParlamentar.find_or_initialize_by(votacao: votacao, parlamentar: parlamentar)
      voto_p.assign_attributes(
        tipo_voto: normalizar_tipo_voto(sigla_voto),
        partido_na_votacao: parlamentar.partido,
        uf_na_votacao: parlamentar.uf
      )
      voto_p.save!
      salvas += 1
    end

    salvas
  end

  def normalizar_tipo_voto(voto)
    v = voto.to_s.strip
    case v.downcase
    when "sim", "yes" then "Sim"
    when "não", "nao", "no" then "Não"
    when "abstenção", "abstencao" then "Abstenção"
    when "obstrução", "obstrucao" then "Obstrução"
    when "p-nrv" then "Presente (Não registrou voto)"
    else v
    end
  end

  def parse_datetime(value)
    return nil if value.blank?
    Time.zone.parse(value.to_s)
  rescue ArgumentError
    nil
  end

  def get_json(path, params = {})
    uri = URI("#{BASE_URL}#{path}")
    uri.query = URI.encode_www_form(params) if params.present?

    req = Net::HTTP::Get.new(uri)
    req["Accept"] = "application/json"
    req["User-Agent"] = "LegislativoApp/1.0 (Ruby on Rails)"

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == "https")
    http.open_timeout = 10
    http.read_timeout = 25

    res = http.request(req)
    return nil unless res.is_a?(Net::HTTPSuccess)

    JSON.parse(res.body)
  end

  def wrap_array(obj)
    case obj
    when nil then []
    when Array then obj
    else [ obj ]
    end
  end

  def normalize_url(url)
    return nil if url.blank?
    url.to_s.sub(/\Ahttp:\/\//i, "https://")
  end

  def parse_date(value)
    return nil if value.blank?
    Date.parse(value.to_s)
  rescue ArgumentError
    nil
  end
end
