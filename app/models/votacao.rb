class Votacao < ApplicationRecord
  self.table_name = "votacoes"

  CASAS = %w[camara senado].freeze

  belongs_to :proposta, optional: true
  has_many :votos_parlamentares, dependent: :destroy
  has_many :parlamentares, through: :votos_parlamentares

  validates :external_id, presence: true, uniqueness: { scope: :casa }
  validates :casa, presence: true, inclusion: { in: CASAS }

  scope :recentes, -> { order(Arel.sql("COALESCE(votacoes.data, votacoes.created_at) DESC, votacoes.id DESC")) }

  def resultado_label
    case aprovacao
    when 1 then "Aprovado"
    when 0 then "Rejeitado"
    else "Votação Registrada"
    end
  end

  def resultado_classe
    case aprovacao
    when 1 then "badge-aprovado"
    when 0 then "badge-rejeitado"
    else "badge-neutral"
    end
  end
end

