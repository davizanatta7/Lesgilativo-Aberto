class VotoParlamentar < ApplicationRecord
  self.table_name = "votos_parlamentares"

  belongs_to :votacao
  belongs_to :parlamentar, counter_cache: :votos_count

  validates :tipo_voto, presence: true
  validates :parlamentar_id, uniqueness: { scope: :votacao_id }

  scope :recentes, -> {
    joins(:votacao).order(Arel.sql("COALESCE(votacoes.data, votacoes.created_at) DESC, votacoes.id DESC"))
  }

  def voto_badge_classe
    case tipo_voto.to_s.downcase
    when "sim"
      "voto-sim"
    when "não", "nao"
      "voto-nao"
    when "abstenção", "abstencao"
      "voto-abstencao"
    when "obstrução", "obstrucao"
      "voto-obstrucao"
    else
      "voto-outro"
    end
  end
end

