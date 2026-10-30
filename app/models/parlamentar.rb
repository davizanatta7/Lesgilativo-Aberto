class Parlamentar < ApplicationRecord
  self.table_name = "parlamentares"

  CASAS = %w[camara senado].freeze
  COLUNAS_LISTAGEM = %i[id external_id casa nome partido uf foto_url email propostas_count total_despesas votos_count updated_at].freeze
  SUBSIDIO_MENSAL_BRUTO = 46_366.19

  has_many :autorias, dependent: :destroy
  has_many :propostas, through: :autorias
  has_many :despesas, dependent: :destroy
  has_many :votos_parlamentares, dependent: :destroy
  has_many :votacoes, through: :votos_parlamentares

  validates :external_id, presence: true, uniqueness: { scope: :casa }
  validates :casa, presence: true, inclusion: { in: CASAS }
  validates :nome, presence: true

  scope :para_listagem, -> { select(COLUNAS_LISTAGEM) }
  scope :por_casa, ->(casa) { where(casa: casa) if casa.present? && CASAS.include?(casa) }
  scope :por_uf, ->(uf) { where(uf: uf.upcase) if uf.present? }
  scope :por_partido, ->(partido) { where(partido: partido.upcase) if partido.present? }
  scope :busca_nome, ->(termo) {
    if termo.present?
      termos = termo.to_s.strip.split(/\s+/).reject(&:blank?)
      termos.reduce(all) do |relacao, palavra|
        q = "%#{sanitize_sql_like(palavra)}%"
        relacao.where(
          "nome LIKE :q OR nome_civil LIKE :q OR partido LIKE :q OR uf LIKE :q",
          q: q
        )
      end
    end
  }
  scope :ordenados, ->(ordem = nil) {
    case ordem.to_s
    when "propostas"
      order(propostas_count: :desc, nome: :asc)
    when "gastos"
      order(total_despesas: :desc, nome: :asc)
    else
      order(:nome)
    end
  }

  def to_param
    "#{id}-#{nome}-#{partido}-#{uf}".parameterize
  end

  def deputado?
    casa == "camara"
  end

  def senador?
    casa == "senado"
  end

  def cargo_label
    deputado? ? "Deputado(a) Federal" : "Senador(a)"
  end

  def casa_label
    deputado? ? "Câmara dos Deputados" : "Senado Federal"
  end

  def subsidio_mensal
    SUBSIDIO_MENSAL_BRUTO
  end

  def gabinete_formatado
    partes = []
    partes << "Prédio #{gabinete_predio}" if gabinete_predio.present?
    partes << "#{gabinete_andar}º andar" if gabinete_andar.present?
    partes << "Sala #{gabinete_sala}" if gabinete_sala.present?
    partes.join(" • ").presence
  end

  def precisa_sincronizar_detalhes?
    dados_sincronizados_em.nil? || dados_sincronizados_em < 7.days.ago
  end

  def precisa_sincronizar_propostas?
    propostas_sincronizadas_em.nil? || propostas_sincronizadas_em < 12.hours.ago
  end

  def precisa_sincronizar_despesas?
    despesas_sincronizadas_em.nil? || despesas_sincronizadas_em < 12.hours.ago
  end

  def precisa_sincronizar_votos?
    votos_sincronizados_em.nil? || votos_sincronizados_em < 12.hours.ago
  end

  def url_perfil_oficial
    if deputado?
      "https://www.camara.leg.br/deputados/#{external_id}"
    else
      "https://www25.senado.leg.br/web/senadores/senador/-/perfil/#{external_id}"
    end
  end

  def url_transparencia_oficial
    if deputado?
      "https://www.camara.leg.br/deputados/#{external_id}/verba-gabinete"
    else
      "https://www6g.senado.leg.br/transparencia/sen/#{external_id}"
    end
  end

  def redes_sociais_detalhadas
    lista = Array(redes_sociais).compact_blank.dup
    if url_website.present? && !lista.include?(url_website)
      lista.unshift(url_website)
    end

    lista.map do |raw_url|
      url = raw_url.to_s.strip
      url = "https://#{url}" unless url.match?(/\Ahttps?:\/\//i)
      host = (URI.parse(url).host.to_s.downcase.sub(/\Awww\./, "") rescue "")

      if host.include?("instagram.com")
        { id: "instagram", nome: "Instagram", classe: "social-instagram", url: url }
      elsif host.include?("twitter.com") || host.include?("x.com")
        { id: "x", nome: "X (Twitter)", classe: "social-x", url: url }
      elsif host.include?("facebook.com") || host.include?("fb.com")
        { id: "facebook", nome: "Facebook", classe: "social-facebook", url: url }
      elsif host.include?("youtube.com") || host.include?("youtu.be")
        { id: "youtube", nome: "YouTube", classe: "social-youtube", url: url }
      elsif host.include?("tiktok.com")
        { id: "tiktok", nome: "TikTok", classe: "social-tiktok", url: url }
      elsif host.include?("linkedin.com")
        { id: "linkedin", nome: "LinkedIn", classe: "social-linkedin", url: url }
      elsif host.include?("threads.net")
        { id: "threads", nome: "Threads", classe: "social-threads", url: url }
      else
        { id: "site", nome: "Site Oficial", classe: "social-site", url: url }
      end
    end
  end
end
