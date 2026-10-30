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
  scope :por_ano, ->(ano) { where(propostas: { ano: ano.to_i }) if ano.present? }
  scope :busca_texto, ->(termo) {
    if termo.present?
      sanitized = "%#{sanitize_sql_like(termo.strip)}%"
      where(
        "propostas.ementa LIKE :q OR propostas.ementa_detalhada LIKE :q OR propostas.keywords LIKE :q OR (propostas.sigla_tipo || ' ' || propostas.numero || '/' || propostas.ano) LIKE :q OR propostas.numero LIKE :q",
        q: sanitized
      )
    end
  }
  scope :recentes, -> {
    order(Arel.sql("COALESCE(propostas.data_apresentacao, propostas.created_at) DESC, propostas.ano DESC, propostas.id DESC"))
  }

  def to_param
    "#{id}-#{sigla_tipo}-#{numero}-#{ano}".parameterize
  end

  def titulo
    "#{sigla_tipo} #{numero}/#{ano}"
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
