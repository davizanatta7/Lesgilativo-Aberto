class Proposta < ApplicationRecord
  self.table_name = "propostas"

  CASAS = %w[camara senado].freeze

  has_many :autorias, dependent: :destroy
  has_many :parlamentares, through: :autorias
  has_many :votacoes, dependent: :destroy

  validates :external_id, presence: true, uniqueness: { scope: :casa }
  validates :casa, presence: true, inclusion: { in: CASAS }
  validates :sigla_tipo, presence: true

  scope :por_casa, ->(casa) { where(propostas: { casa: casa }) if casa.present? && CASAS.include?(casa) }
  scope :por_tipo, ->(tipo) { where(propostas: { sigla_tipo: tipo.upcase }) if tipo.present? }
  scope :por_ano, ->(ano) { where(propostas: { ano: ano.to_i }) if ano.present? && ano.to_i > 0 }
  scope :busca_texto, ->(termo) {
    if termo.present?
      limpo = termo.strip
      if (m = limpo.match(/\A([a-zA-Z]{2,6})\s+(\d+)(?:\/(\d{4}))?\z/))
        sigla = m[1].upcase
        num = m[2]
        ano_busca = m[3]
        rel = where(propostas: { sigla_tipo: sigla, numero: num })
        rel = rel.where(propostas: { ano: ano_busca.to_i }) if ano_busca.present?
        rel
      else
        sanitized = "%#{sanitize_sql_like(limpo)}%"
        where(
          "propostas.ementa LIKE :q OR propostas.ementa_detalhada LIKE :q OR propostas.keywords LIKE :q OR (propostas.sigla_tipo || ' ' || propostas.numero || '/' || COALESCE(propostas.ano, '')) LIKE :q OR (propostas.sigla_tipo || ' ' || propostas.numero) LIKE :q OR propostas.numero LIKE :q",
          q: sanitized
        )
      end
    end
  }
  scope :recentes, -> {
    order(Arel.sql("CASE WHEN propostas.sigla_tipo IN ('PL', 'PEC', 'PLP', 'PDL', 'MPV') THEN 0 ELSE 1 END ASC, COALESCE(propostas.data_apresentacao, propostas.created_at) DESC, COALESCE(propostas.ano, 0) DESC, propostas.id DESC"))
  }

  def to_param
    "#{id}-#{sigla_tipo}-#{numero}-#{ano}".parameterize
  end

  def titulo
    if ano.present? && ano.to_i > 0
      "#{sigla_tipo} #{numero}/#{ano}"
    else
      "#{sigla_tipo} #{numero}"
    end
  end

  def casa_label
    casa == "camara" ? "Câmara dos Deputados" : "Senado Federal"
  end

  def precisa_sincronizar_detalhes?
    detalhes_sincronizados_em.nil? || detalhes_sincronizados_em < 3.days.ago
  end

  def url_pagina_oficial
    if casa == "camara"
      "https://www.camara.leg.br/proposicoesWeb/fichadetramitacao?idProposicao=#{external_id}"
    else
      "https://www25.senado.leg.br/web/atividade/materias/-/materia/#{external_id}"
    end
  end
end
