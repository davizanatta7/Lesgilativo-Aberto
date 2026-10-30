require "net/http"
require "json"
require "uri"
require "digest"

class CamaraSyncService
  BASE_URL = "https://dadosabertos.camara.leg.br/api/v2"

  def initialize(logger: Rails.logger)
    @logger = logger
  end

  # Sincroniza a lista de todos os deputados em exercício (513 deputados)
  def sync_deputados
    @logger.info "[CamaraSync] Buscando lista de deputados em exercício..."
    dados = fetch_paginated("/deputados", { ordem: "ASC", ordenarPor: "nome", itens: 1000 })
    if dados.size < 513
      dados_paginados = fetch_paginated("/deputados", { ordem: "ASC", ordenarPor: "nome", itens: 100 })
      dados = (dados + dados_paginados).uniq { |d| d["id"].to_s }
    end

    count = 0
    dados.each do |item|
      next if item["id"].blank?

      parlamentar = Parlamentar.find_or_initialize_by(
        casa: "camara",
        external_id: item["id"].to_s
      )
      parlamentar.assign_attributes(
        nome: item["nome"],
        partido: item["siglaPartido"],
        uf: item["siglaUf"],
        foto_url: item["urlFoto"],
        email: item["email"].presence || parlamentar.email
      )
      parlamentar.save!
      count += 1
    end

    Rails.cache.delete("parlamentares/resumo_contadores")
    @logger.info "[CamaraSync] #{count} deputados sincronizados com sucesso."
    count
  end

  # Sincroniza dados completos de gabinete, biografia e redes sociais de um deputado
  def sync_detalhes_deputado(parlamentar)
    return unless parlamentar.deputado?

    resp = get_json("/deputados/#{parlamentar.external_id}")
    dados = resp&.dig("dados")
    return unless dados

    status = dados["ultimoStatus"] || {}
    gabinete = status["gabinete"] || {}

    parlamentar.update!(
      nome: status["nome"].presence || parlamentar.nome,
      nome_civil: dados["nomeCivil"],
      partido: status["siglaPartido"].presence || parlamentar.partido,
      uf: status["siglaUf"].presence || parlamentar.uf,
      foto_url: status["urlFoto"].presence || parlamentar.foto_url,
      email: gabinete["email"].presence || status["email"].presence || parlamentar.email,
      telefone: gabinete["telefone"],
      gabinete_predio: gabinete["predio"],
      gabinete_andar: gabinete["andar"],
      gabinete_sala: gabinete["sala"],
      situacao: status["situacao"],
      escolaridade: dados["escolaridade"],
      data_nascimento: parse_date(dados["dataNascimento"]),
      municipio_nascimento: dados["municipioNascimento"],
      uf_nascimento: dados["ufNascimento"],
      url_website: dados["urlWebsite"],
      redes_sociais: Array(dados["redeSocial"]).compact,
      dados_sincronizados_em: Time.current
    )
    parlamentar
  rescue StandardError => e
    @logger.error "[CamaraSync] Erro ao sincronizar detalhes do deputado #{parlamentar.external_id}: #{e.message}"
    parlamentar
  end

  # Sincroniza despesas da Cota Parlamentar (CEAP) de um deputado
  def sync_despesas_deputado(parlamentar, itens: 100)
    return [] unless parlamentar.deputado?

    resp = get_json("/deputados/#{parlamentar.external_id}/despesas", {
      itens: itens,
      ordem: "DESC",
      ordenarPor: "ano"
    })
    dados = resp&.dig("dados") || []

    despesas_sincronizadas = []
    dados.each do |item|
      valor = item["valorLiquido"].to_f
      next if valor <= 0

      doc_id = if item["codDocumento"].present? && item["codDocumento"].to_i > 0
        item["codDocumento"].to_s
      else
        Digest::SHA1.hexdigest("#{item['ano']}-#{item['mes']}-#{item['numDocumento']}-#{item['cnpjCpfFornecedor']}-#{valor}")[0, 16]
      end

      despesa = Despesa.find_or_initialize_by(
        parlamentar: parlamentar,
        external_doc_id: doc_id
      )
      despesa.assign_attributes(
        ano: item["ano"].to_i,
        mes: item["mes"].to_i,
        tipo_despesa: item["tipoDespesa"].to_s.strip.sub(/\.\z/, ""),
        fornecedor: item["nomeFornecedor"],
        cnpj_cpf_fornecedor: item["cnpjCpfFornecedor"],
        valor_liquido: valor,
        data_documento: parse_date(item["dataDocumento"]),
        numero_documento: item["numDocumento"],
        url_documento: item["urlDocumento"]
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
    @logger.error "[CamaraSync] Erro ao sincronizar despesas do deputado #{parlamentar.external_id}: #{e.message}"
    []
  end

  # Sincroniza as propostas de autoria de um deputado (priorizando Projetos de Lei, PECs, Emendas e Requerimentos)
  def sync_propostas_deputado(parlamentar, limite: 60)
    return [] unless parlamentar.deputado?

    grupos_siglas = [
      { siglas: %w[PL PEC PLP PDL MPV PRC], itens: limite },
      { siglas: %w[EMC EMP EMR SBT], itens: 35 },
      { siglas: %w[REQ RIC INC PFC], itens: 25 }
    ]

    dados = []
    grupos_siglas.each do |grupo|
      resp = get_json("/proposicoes", {
        idDeputadoAutor: parlamentar.external_id,
        siglaTipo: grupo[:siglas],
        itens: grupo[:itens],
        ordem: "DESC",
        ordenarPor: "id"
      })
      dados.concat(resp&.dig("dados") || [])
    end

    if dados.empty?
      resp = get_json("/proposicoes", {
        idDeputadoAutor: parlamentar.external_id,
        itens: limite,
        ordem: "DESC",
        ordenarPor: "id"
      })
      dados = resp&.dig("dados") || []
    end

    propostas_sincronizadas = []
    dados.uniq { |item| item["id"] }.each do |item|
      proposta = upsert_proposta_resumo(item)
      if proposta
        Autoria.find_or_create_by!(parlamentar: parlamentar, proposta: proposta)
        propostas_sincronizadas << proposta
      end
    end

    parlamentar.update_columns(
      propostas_count: parlamentar.propostas.count,
      propostas_sincronizadas_em: Time.current
    )
    propostas_sincronizadas
  rescue StandardError => e
    @logger.error "[CamaraSync] Erro ao sincronizar propostas do deputado #{parlamentar.external_id}: #{e.message}"
    []
  end

  # Sincroniza propostas recentes gerais da Câmara (sem travar em um único ano)
  def sync_propostas_recentes(ano: nil, siglas: %w[PL PEC PLP PDL MPV EMC RIC INC], itens_por_tipo: 35)
    total = 0
    siglas.each do |sigla|
      params = {
        siglaTipo: sigla,
        itens: itens_por_tipo,
        ordem: "DESC",
        ordenarPor: "id"
      }
      params[:ano] = ano if ano.present?
      resp = get_json("/proposicoes", params)
      dados = resp&.dig("dados") || []
      dados.each do |item|
        proposta = upsert_proposta_resumo(item)
        total += 1 if proposta
      end
    end
    @logger.info "[CamaraSync] #{total} propostas recentes da Câmara sincronizadas."
    total
  end

  # Busca propostas sob demanda na API da Câmara por número/sigla ou palavras-chave da ementa
  def buscar_propostas_api(termo: nil, sigla_tipo: nil,ano: nil, limite: 30)
    params = {
      itens: limite,
      ordem: "DESC",
      ordenarPor: "id"
    }
    params[:siglaTipo] = sigla_tipo.upcase if sigla_tipo.present?
    params[:ano] = ano.to_i if ano.present? && ano.to_i > 0

    if termo.present?
      limpo = termo.strip
      if (m = limpo.match(/\A([a-zA-Z]{2,6})\s+(\d+)(?:\/(\d{4}))?\z/))
        params[:siglaTipo] = m[1].upcase
        params[:numero] = m[2]
        params[:ano] = m[3].to_i if m[3].present?
      elsif limpo.match?(/\A\d+\z/)
        params[:numero] = limpo
      else
        params[:keywords] = limpo
      end
    end

    resp = get_json("/proposicoes", params)
    dados = resp&.dig("dados") || []
    dados.filter_map { |item| upsert_proposta_resumo(item) }
  rescue StandardError => e
    @logger.warn "[CamaraSync] Erro na busca sob demanda de propostas: #{e.message}"
    []
  end

  # Sincroniza detalhes completos + autores de uma proposta específica
  def sync_detalhes_proposta(proposta)
    return unless proposta.casa == "camara"

    resp = get_json("/proposicoes/#{proposta.external_id}")
    dados = resp&.dig("dados")
    return unless dados

    status = dados["statusProposicao"] || {}

    proposta.update!(
      sigla_tipo: dados["siglaTipo"].presence || proposta.sigla_tipo,
      descricao_tipo: dados["descricaoTipo"],
      numero: dados["numero"]&.to_s.presence || proposta.numero,
      ano: dados["ano"] || proposta.ano,
      ementa: dados["ementa"].presence || proposta.ementa,
      ementa_detalhada: dados["ementaDetalhada"],
      keywords: dados["keywords"],
      data_apresentacao: parse_date(dados["dataApresentacao"]),
      status_situacao: status["descricaoSituacao"].presence || status["descricaoTramitacao"],
      status_orgao: status["siglaOrgao"],
      status_despacho: status["despacho"],
      status_regime: status["regime"],
      url_inteiro_teor: dados["urlInteiroTeor"],
      detalhes_sincronizados_em: Time.current
    )

    sync_autores_proposta(proposta)
    sync_votacoes_proposta(proposta)
    proposta
  rescue StandardError => e
    @logger.error "[CamaraSync] Erro ao sincronizar detalhes da proposta #{proposta.external_id}: #{e.message}"
    proposta
  end

  # Sincroniza as últimas votações nominais do Plenário da Câmara (popula votos para todos os deputados)
  def sync_votacoes_plenario_recentes(max_nominais: 12)
    resp = get_json("/votacoes", {
      idOrgao: 180,
      ordem: "DESC",
      ordenarPor: "dataHoraRegistro",
      itens: 45
    })
    lista = resp&.dig("dados") || []
    deputados_map = Parlamentar.where(casa: "camara").index_by(&:external_id)
    nominais_salvas = 0

    lista.each do |item|
      break if nominais_salvas >= max_nominais

      vot_id = item["id"].to_s
      next if vot_id.blank?

      votacao_existente = Votacao.find_by(casa: "camara", external_id: vot_id)
      if votacao_existente && votacao_existente.votos_parlamentares.exists?
        nominais_salvas += 1
        next
      end

      votos_resp = get_json("/votacoes/#{vot_id}/votos")
      votos_dados = votos_resp&.dig("dados") || []
      next if votos_dados.empty?

      salvar_votacao_e_votos_camara(item, votos_dados, deputados_map: deputados_map)
      nominais_salvas += 1
    end

    atualizar_contadores_votos_camara if nominais_salvas > 0
    nominais_salvas
  rescue StandardError => e
    @logger.error "[CamaraSync] Erro ao sincronizar votações do Plenário: #{e.message}"
    0
  end

  # Sincroniza votações nominais de uma proposta específica
  def sync_votacoes_proposta(proposta)
    return 0 unless proposta.casa == "camara"

    resp = get_json("/proposicoes/#{proposta.external_id}/votacoes", {
      ordem: "DESC",
      ordenarPor: "dataHoraRegistro"
    })
    lista = resp&.dig("dados") || []
    return 0 if lista.empty?

    deputados_map = Parlamentar.where(casa: "camara").index_by(&:external_id)
    salvas = 0

    lista.first(8).each do |item|
      vot_id = item["id"].to_s
      next if vot_id.blank?

      votos_resp = get_json("/votacoes/#{vot_id}/votos")
      votos_dados = votos_resp&.dig("dados") || []
      next if votos_dados.empty?

      salvar_votacao_e_votos_camara(item, votos_dados, deputados_map: deputados_map, proposta: proposta)
      salvas += 1
    end

    atualizar_contadores_votos_camara if salvas > 0
    salvas
  rescue StandardError => e
    @logger.warn "[CamaraSync] Não foi possível sincronizar votações da proposta #{proposta.external_id}: #{e.message}"
    0
  end

  private

  def salvar_votacao_e_votos_camara(item, votos_dados, deputados_map:, proposta: nil)
    vot_id = item["id"].to_s
    votacao = Votacao.find_or_initialize_by(casa: "camara", external_id: vot_id)

    sim_count = 0
    nao_count = 0
    outros_count = 0

    votos_dados.each do |v|
      case v["tipoVoto"].to_s.strip.downcase
      when "sim" then sim_count += 1
      when "não", "nao" then nao_count += 1
      else outros_count += 1
      end
    end

    votacao.assign_attributes(
      proposta: proposta || votacao.proposta,
      proposta_identificacao: item["proposicaoObjeto"].presence || proposta&.titulo || votacao.proposta_identificacao,
      orgao: item["siglaOrgao"].presence || "PLEN",
      data: parse_datetime(item["dataHoraRegistro"] || item["data"]),
      descricao: item["descricao"],
      aprovacao: item["aprovacao"],
      votos_sim: sim_count,
      votos_nao: nao_count,
      votos_outros: outros_count
    )
    votacao.save!

    now = Time.current
    registros = []

    votos_dados.each do |v|
      dep_info = v["deputado_"] || v["deputado"] || {}
      dep_ext_id = dep_info["id"]&.to_s
      next if dep_ext_id.blank?

      parlamentar = deputados_map[dep_ext_id]
      next unless parlamentar

      registros << {
        votacao_id: votacao.id,
        parlamentar_id: parlamentar.id,
        tipo_voto: v["tipoVoto"].to_s.strip,
        partido_na_votacao: dep_info["siglaPartido"],
        uf_na_votacao: dep_info["siglaUf"],
        created_at: now,
        updated_at: now
      }
    end

    if registros.any?
      VotoParlamentar.upsert_all(registros, unique_by: %i[votacao_id parlamentar_id])
    end

    votacao
  end

  def atualizar_contadores_votos_camara
    now_str = ActiveRecord::Base.connection.quote(Time.current)
    ActiveRecord::Base.connection.execute(<<~SQL)
      UPDATE parlamentares
      SET votos_count = (
        SELECT COUNT(*)
        FROM votos_parlamentares
        WHERE votos_parlamentares.parlamentar_id = parlamentares.id
      ),
      votos_sincronizados_em = #{now_str}
      WHERE casa = 'camara'
    SQL
  end

  def upsert_proposta_resumo(item)
    return nil if item["id"].blank?

    data_apres = parse_date(item["dataApresentacao"])
    ano_val = item["ano"].to_i
    ano_resolvido = if ano_val > 0
      ano_val
    elsif data_apres.present?
      data_apres.year
    end

    proposta = Proposta.find_or_initialize_by(
      casa: "camara",
      external_id: item["id"].to_s
    )
    proposta.assign_attributes(
      sigla_tipo: item["siglaTipo"] || "PROP",
      numero: item["numero"]&.to_s,
      ano: ano_resolvido || proposta.ano,
      ementa: item["ementa"].presence || proposta.ementa,
      data_apresentacao: data_apres || proposta.data_apresentacao,
      status_situacao: proposta.status_situacao.presence || "Em tramitação / Apresentada",
      uri_api: item["uri"]
    )
    proposta.save!
    proposta
  end

  def sync_autores_proposta(proposta)
    resp = get_json("/proposicoes/#{proposta.external_id}/autores")
    autores = resp&.dig("dados") || []

    autores.each do |autor|
      uri = autor["uri"].to_s
      next unless uri.include?("/deputados/")

      dep_id = uri.split("/").last
      parlamentar = Parlamentar.find_by(casa: "camara", external_id: dep_id)
      if parlamentar
        Autoria.find_or_create_by!(parlamentar: parlamentar, proposta: proposta) do |autoria|
          autoria.tipo_autoria = autor["tipo"].presence || "Autor"
        end
      end
    end
  rescue StandardError => e
    @logger.warn "[CamaraSync] Não foi possível sincronizar autores da proposta #{proposta.external_id}: #{e.message}"
  end

  def fetch_paginated(path, params = {})
    resultados = []
    pagina = 1
    itens_por_pagina = params[:itens].to_i

    loop do
      resp = get_json(path, params.merge(pagina: pagina))
      dados = resp&.dig("dados")
      break if dados.blank?

      resultados.concat(dados)
      links = resp["links"] || []
      has_next = links.any? { |l| l["rel"] == "next" } || (itens_por_pagina > 0 && dados.size >= itens_por_pagina)
      break unless has_next

      pagina += 1
      break if pagina > 20
    end

    resultados.uniq { |item| item["id"] || item.object_id }
  end

  def get_json(path, params = {})
    uri = URI("#{BASE_URL}#{path}")
    uri.query = URI.encode_www_form(params) if params.present?

    tentativas = 0
    begin
      tentativas += 1
      req = Net::HTTP::Get.new(uri)
      req["Accept"] = "application/json"
      req["User-Agent"] = "LegislativoApp/1.0 (Ruby on Rails)"

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.open_timeout = 10
      http.read_timeout = 25

      res = http.request(req)
      if res.is_a?(Net::HTTPSuccess)
        return JSON.parse(res.body)
      elsif tentativas < 3
        sleep(0.5 * tentativas)
        raise "HTTP #{res.code}"
      end
      nil
    rescue StandardError => e
      if tentativas < 3
        sleep(0.5 * tentativas)
        retry
      end
      @logger.warn "[CamaraSync] Falha em GET #{path} após #{tentativas} tentativas: #{e.message}"
      nil
    end
  end

  def parse_date(value)
    return nil if value.blank?
    Date.parse(value.to_s)
  rescue ArgumentError
    nil
  end

  def parse_datetime(value)
    return nil if value.blank?
    Time.zone.parse(value.to_s)
  rescue ArgumentError
    nil
  end
end
